import Foundation

/// A selected asset post-image, not proof that the asset exists or is current.
struct FindingAssetSubjectSelectionV1: Codable, Equatable, Sendable {
    let assetID: UUID
    let entityRevision: UInt64
    let postImageSHA256: String

    init(assetID: UUID, entityRevision: UInt64, postImageSHA256: String) throws {
        self.assetID = assetID
        self.entityRevision = entityRevision
        self.postImageSHA256 = postImageSHA256
        try validate()
    }

    func validate() throws {
        try FindingMutationValidationV1.id(assetID)
        guard Int(exactly: entityRevision) != nil, KernelCanonicalHashV1.validSHA256(postImageSHA256) else {
            throw FindingContractFailureV1.invalidValue
        }
    }

    func subject() throws -> FindingSubjectV1 {
        try validate()
        guard let revision = Int(exactly: entityRevision) else { throw FindingContractFailureV1.invalidValue }
        return try FindingSubjectV1(subjectKindID: "asset", subjectID: assetID.uuidString.lowercased(), subjectRevision: revision)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case assetID, entityRevision, postImageSHA256 }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(assetID: c.decode(UUID.self, forKey: .assetID), entityRevision: c.decode(UInt64.self, forKey: .entityRevision),
                      postImageSHA256: c.decode(String.self, forKey: .postImageSHA256))
    }
    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(assetID, forKey: .assetID)
        try c.encode(entityRevision, forKey: .entityRevision)
        try c.encode(postImageSHA256, forKey: .postImageSHA256)
    }
}

/// This operation records a new human fact. It cannot import an existing source,
/// select a different source kind, or smuggle prior histories into creation.
struct FindingHumanObservationCreationV1: Codable, Equatable, Sendable {
    let findingID: String
    let sourceID: String
    let categoryID: String
    let summary: String
    let severity: FindingSeverityBindingV1
    let severityScale: SeverityScaleReleaseV1
    let subject: FindingAssetSubjectSelectionV1
    let classification: FindingClassificationBindingV1?
    let activitySource: FindingActivitySourceReferenceV1?

    init(findingID: String, sourceID: String, categoryID: String, summary: String,
         severity: FindingSeverityBindingV1, severityScale: SeverityScaleReleaseV1,
         subject: FindingAssetSubjectSelectionV1, classification: FindingClassificationBindingV1? = nil,
         activitySource: FindingActivitySourceReferenceV1? = nil) throws {
        self.findingID = findingID
        self.sourceID = sourceID
        self.categoryID = categoryID
        self.summary = summary
        self.severity = severity
        self.severityScale = severityScale
        self.subject = subject
        self.classification = classification
        self.activitySource = activitySource
        try validate()
    }

    func validate() throws {
        try subject.validate()
        try severityScale.validate()
        guard severityScale.recordedAt.timeIntervalSince1970.isFinite else { throw FindingContractFailureV1.invalidValue }
        for level in severityScale.levels {
            _ = try SeverityLevelDefinitionV1(levelID: level.levelID, localizedLabelKey: level.localizedLabelKey,
                                              descriptionKey: level.descriptionKey)
        }
        try severity.validate(against: severityScale)
        let value = try finding()
        if let classification {
            guard classification.workspaceID == severityScale.workspaceID,
                  classification.recordedAt.timeIntervalSince1970.isFinite else { throw FindingContractFailureV1.invalidValue }
            try value.validateClassification(classification, scale: severityScale)
        }
        try activitySource?.validate()
        if let activitySource {
            guard activitySource.selected.workspaceID == severityScale.workspaceID else { throw FindingContractFailureV1.invalidValue }
        }
    }

    func finding() throws -> FindingV1 {
        let source = try FindingSourceV1(kind: .humanObservation, sourceID: sourceID, sourceRevision: 0)
        return try FindingV1(findingID: findingID, revision: 0, severity: severity, categoryID: categoryID,
                             subject: subject.subject(), source: source, summary: summary)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case findingID, sourceID, categoryID, summary, severity, severityScale, subject, classification, activitySource
    }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue),
            required: ["findingID", "sourceID", "categoryID", "summary", "severity", "severityScale", "subject"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try FindingMutationValidationV1.nonnull(c, keys: [.classification, .activitySource])
        let scale = try FindingMutationValidationV1.scale(c.superDecoder(forKey: .severityScale))
        let classification: FindingClassificationBindingV1?
        if c.contains(.classification) {
            classification = try FindingMutationValidationV1.classification(c.superDecoder(forKey: .classification))
        } else { classification = nil }
        try self.init(findingID: c.decode(String.self, forKey: .findingID), sourceID: c.decode(String.self, forKey: .sourceID),
            categoryID: c.decode(String.self, forKey: .categoryID), summary: c.decode(String.self, forKey: .summary),
            severity: c.decode(FindingSeverityBindingV1.self, forKey: .severity), severityScale: scale,
            subject: c.decode(FindingAssetSubjectSelectionV1.self, forKey: .subject), classification: classification,
            activitySource: c.decodeIfPresent(FindingActivitySourceReferenceV1.self, forKey: .activitySource))
    }
    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(findingID, forKey: .findingID)
        try c.encode(sourceID, forKey: .sourceID)
        try c.encode(categoryID, forKey: .categoryID)
        try c.encode(summary, forKey: .summary)
        try c.encode(severity, forKey: .severity)
        try c.encode(severityScale, forKey: .severityScale)
        try c.encode(subject, forKey: .subject)
        try c.encodeIfPresent(classification, forKey: .classification)
        try c.encodeIfPresent(activitySource, forKey: .activitySource)
    }
}

struct FindingTransitionOperationV1: Codable, Equatable, Sendable {
    let event: FindingTransitionV1
    let verifiedRecheck: FindingVerifiedRecheckReferenceV1?

    init(event: FindingTransitionV1, verifiedRecheck: FindingVerifiedRecheckReferenceV1? = nil) throws {
        self.event = event
        self.verifiedRecheck = verifiedRecheck
        try validate()
    }
    func validate() throws {
        try FindingMutationValidationV1.incrementable(event.expectedFindingRevision)
        _ = try JSONDecoder().decode(FindingTransitionV1.self, from: WorkspaceMutationCanonicalV1.data(event))
        try verifiedRecheck?.validate()
        guard (event.toState == .verifiedResolved) == (verifiedRecheck != nil),
              event.verifiedRecheckID == verifiedRecheck?.recheckID else { throw FindingContractFailureV1.recheckRequired }
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case event, verifiedRecheck }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue), required: ["event"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try FindingMutationValidationV1.nonnull(c, keys: [.verifiedRecheck])
        try FindingMutationValidationV1.preflight(c.superDecoder(forKey: .event), field: "expectedFindingRevision")
        try self.init(event: c.decode(FindingTransitionV1.self, forKey: .event),
                      verifiedRecheck: c.decodeIfPresent(FindingVerifiedRecheckReferenceV1.self, forKey: .verifiedRecheck))
    }
    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(event, forKey: .event)
        try c.encodeIfPresent(verifiedRecheck, forKey: .verifiedRecheck)
    }
}

struct FindingC14LinkOperationV1: Codable, Equatable, Sendable {
    let event: CorrectiveWorkLinkV1
    let support: FindingC14SupportReferenceV1

    init(event: CorrectiveWorkLinkV1, support: FindingC14SupportReferenceV1) throws {
        self.event = event
        self.support = support
        try validate()
    }
    func validate() throws {
        try FindingMutationValidationV1.link(event)
        try support.validate()
        guard event.action == .linked,
              let revision = Int(exactly: support.original.eventRevision),
              event.workRevision == revision, support.correctiveWorkRevision == revision,
              event.workID == support.correctiveWorkID else { throw FindingContractFailureV1.invalidValue }
        try event.validateCorrectiveActionSource(findingID: event.findingID, findingRevision: event.findingRevision,
                                                actionID: support.original.actionID)
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case event, support }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try FindingMutationValidationV1.preflight(c.superDecoder(forKey: .event), field: "expectedLinkRevision")
        try self.init(event: c.decode(CorrectiveWorkLinkV1.self, forKey: .event),
                      support: c.decode(FindingC14SupportReferenceV1.self, forKey: .support))
    }
    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(event, forKey: .event)
        try c.encode(support, forKey: .support)
    }
}

/// Unsupported source/evidence and relationship write adapters remain separate
/// required work. This command family does not narrow historical C04 decoding.
enum FindingOwnerOperationV1: Codable, Equatable, Sendable {
    case createHumanObservation(FindingHumanObservationCreationV1)
    case transitionFinding(FindingTransitionOperationV1)
    case linkC14CorrectiveWork(FindingC14LinkOperationV1)
    case removeCorrectiveWork(CorrectiveWorkLinkV1)

    var createsOwner: Bool {
        if case .createHumanObservation = self { return true }
        return false
    }
    func validate() throws {
        switch self {
        case let .createHumanObservation(value): try value.validate()
        case let .transitionFinding(value): try value.validate()
        case let .linkC14CorrectiveWork(value): try value.validate()
        case let .removeCorrectiveWork(value):
            try FindingMutationValidationV1.link(value)
            guard value.action == .removed else { throw FindingContractFailureV1.invalidValue }
        }
    }
    private enum CodingKeys: String, CodingKey { case kind, createHumanObservation, transitionFinding, linkC14CorrectiveWork, removeCorrectiveWork }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "createHumanObservation":
            try FindingClosedCodingV1.requireExact(decoder, keys: ["kind", "createHumanObservation"])
            self = .createHumanObservation(try c.decode(FindingHumanObservationCreationV1.self, forKey: .createHumanObservation))
        case "transitionFinding":
            try FindingClosedCodingV1.requireExact(decoder, keys: ["kind", "transitionFinding"])
            self = .transitionFinding(try c.decode(FindingTransitionOperationV1.self, forKey: .transitionFinding))
        case "linkC14CorrectiveWork":
            try FindingClosedCodingV1.requireExact(decoder, keys: ["kind", "linkC14CorrectiveWork"])
            self = .linkC14CorrectiveWork(try c.decode(FindingC14LinkOperationV1.self, forKey: .linkC14CorrectiveWork))
        case "removeCorrectiveWork":
            try FindingClosedCodingV1.requireExact(decoder, keys: ["kind", "removeCorrectiveWork"])
            try FindingMutationValidationV1.preflight(c.superDecoder(forKey: .removeCorrectiveWork), field: "expectedLinkRevision")
            self = .removeCorrectiveWork(try c.decode(CorrectiveWorkLinkV1.self, forKey: .removeCorrectiveWork))
        default: throw FindingContractFailureV1.incompatibleVersion
        }
        try validate()
    }
    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .createHumanObservation(value):
            try c.encode("createHumanObservation", forKey: .kind)
            try c.encode(value, forKey: .createHumanObservation)
        case let .transitionFinding(value):
            try c.encode("transitionFinding", forKey: .kind)
            try c.encode(value, forKey: .transitionFinding)
        case let .linkC14CorrectiveWork(value):
            try c.encode("linkC14CorrectiveWork", forKey: .kind)
            try c.encode(value, forKey: .linkC14CorrectiveWork)
        case let .removeCorrectiveWork(value):
            try c.encode("removeCorrectiveWork", forKey: .kind)
            try c.encode(value, forKey: .removeCorrectiveWork)
        }
    }
}

/// One causal intent and one derived owner result. No field contains caller-
/// selected replacement evidence or claims that its dependencies are authentic.
struct FindingOwnerMutationV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let expectedRevision: WorkspaceExpectedRevisionV1
    let mutationID: MutationIDV1
    let ownerID: UUID
    let predecessor: FindingSelectedOwnerReferenceV1?
    let recordedBy: ActorSnapshotV1
    let recordedAt: Date
    let operation: FindingOwnerOperationV1

    init(workspaceID: WorkspaceID, expectedRevision: WorkspaceExpectedRevisionV1, mutationID: MutationIDV1,
         ownerID: UUID, predecessor: FindingSelectedOwnerReferenceV1? = nil,
         recordedBy: ActorSnapshotV1, recordedAt: Date, operation: FindingOwnerOperationV1) throws {
        self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision
        self.mutationID = mutationID
        self.ownerID = ownerID
        self.predecessor = predecessor
        self.recordedBy = recordedBy
        self.recordedAt = recordedAt
        self.operation = operation
        try validate()
    }

    func validate() throws {
        try FindingMutationValidationV1.id(workspaceID.rawValue)
        try FindingMutationValidationV1.id(ownerID)
        try FindingMutationValidationV1.id(mutationID.rawValue)
        try FindingMutationValidationV1.frontier(expectedRevision)
        try recordedBy.validate()
        try operation.validate()
        guard expectedRevision.workspaceID == workspaceID, recordedBy.workspaceID == workspaceID,
              recordedBy.responsibility == .recordedBy, recordedAt.timeIntervalSince1970.isFinite,
              recordedBy.capturedAt <= recordedAt, operation.createsOwner == (predecessor == nil) else {
            throw FindingContractFailureV1.invalidValue
        }
        try requireRead(.actorSnapshot, id: recordedBy.snapshotID)
        var acceptances: [FindingAcceptedMutationReferenceV1] = []
        if let predecessor {
            try predecessor.validate()
            guard predecessor.selected.workspaceID == workspaceID, predecessor.selected.kind == .finding,
                  predecessor.selected.ownerID == ownerID, predecessor.selected.ownerRevision < UInt64.max else {
                throw FindingContractFailureV1.staleRevision
            }
            acceptances.append(predecessor.originalAcceptance)
            acceptances.append(predecessor.selectedAcceptance)
        }
        switch operation {
        case let .createHumanObservation(value):
            guard value.severityScale.workspaceID == workspaceID else { throw FindingContractFailureV1.invalidValue }
            try requireRead(.asset, id: value.subject.assetID, revision: value.subject.entityRevision)
            try requireRead(.severityScaleRelease, id: value.severityScale.releaseID)
            if let classification = value.classification { try requireRead(.findingClassificationBinding, id: classification.bindingID) }
            if let source = value.activitySource {
                try requireRead(.activitySessionEnvelope, id: source.selected.activityID)
                acceptances.append(source.originalAcceptance)
                acceptances.append(source.selectedAcceptance)
            }
        case let .transitionFinding(value):
            if let recheck = value.verifiedRecheck {
                guard recheck.owner == predecessor?.selected else { throw FindingContractFailureV1.invalidValue }
            }
        case let .linkC14CorrectiveWork(value):
            guard value.support.selected.workspaceID == workspaceID else { throw FindingContractFailureV1.invalidValue }
            try requireRead(.correctiveActionEvent, id: value.support.selected.eventID)
            acceptances.append(value.support.original.acceptance)
            acceptances.append(value.support.selected.acceptance)
        case .removeCorrectiveWork: break
        }
        try FindingMutationValidationV1.acceptances(acceptances)
    }

    private func requireRead(_ kind: WorkspaceEntityKindV1, id: UUID, revision: UInt64? = nil) throws {
        let identity = try WorkspaceEntityIdentityV1(kind: kind, id: id)
        guard let selected = expectedRevision.entityRevisions.first(where: { $0.identity == identity }) else {
            throw FindingContractFailureV1.staleRevision
        }
        if let revision, selected.revision != revision { throw FindingContractFailureV1.staleRevision }
    }

    /// Pure derivation from supplied values. The actual writer must authenticate
    /// the complete read set, original receipts, current membership and mappings,
    /// independently repeat this derivation and journal its sole exact effect.
    func derive(predecessor prior: FindingOwnerRecordV1?) throws -> FindingOwnerRecordV1 {
        try validate()
        if case let .createHumanObservation(creation) = operation {
            guard prior == nil else { throw FindingContractFailureV1.historyRewrite }
            let finding = try creation.finding()
            let lifecycle = try FindingLifecycleV1(findingID: finding.findingID)
            let evidence = try FindingLifecycleCanonicalEvidenceV1(finding: finding, lifecycle: lifecycle)
            let facts = try FindingOwnedFactsV1(evidence: evidence, activitySource: creation.activitySource)
            let origin = try FindingOwnerOriginIdentityV1(workspaceID: workspaceID, kind: .finding,
                ownerID: ownerID, creationMutationID: mutationID)
            return try FindingOwnerRecordV1(workspaceID: workspaceID, kind: .finding, ownerID: ownerID,
                ownerRevision: 1, mutationID: mutationID, recordedBy: recordedBy, recordedAt: recordedAt,
                origin: origin, finding: facts)
        }
        guard let prior, let selection = predecessor else { throw FindingContractFailureV1.missingTarget }
        try prior.validate()
        guard try selection.selected == prior.reference, let old = prior.finding, prior.kind == .finding,
              prior.ownerRevision < UInt64.max else { throw FindingContractFailureV1.staleRevision }
        let basis = old.evidence
        var finding = basis.finding
        var lifecycle = basis.lifecycle
        var links = basis.correctiveWorkLinks
        var supports = old.correctiveActions
        switch operation {
        case .createHumanObservation: throw FindingContractFailureV1.invalidValue
        case let .transitionFinding(value):
            let event = value.event
            guard event.findingID == finding.findingID, event.expectedFindingRevision == finding.revision,
                  event.fromState == lifecycle.currentState else { throw FindingContractFailureV1.staleRevision }
            if let reference = value.verifiedRecheck {
                let rechecks = basis.verifiedRechecks.filter { $0.recheckID == reference.recheckID }
                guard rechecks.count == 1, let recheck = rechecks.first else { throw FindingContractFailureV1.missingTarget }
                try reference.validate(recheck: recheck)
                guard recheck.findingID == finding.findingID, recheck.findingRevision == finding.revision,
                      recheck.permitsVerifiedResolution else { throw FindingContractFailureV1.recheckRequired }
            }
            guard !lifecycle.transitions.contains(where: { $0.transitionID == event.transitionID || $0.mutationID == event.mutationID }) else {
                throw FindingContractFailureV1.duplicateIdentity
            }
            lifecycle = try FindingLifecycleV1(findingID: lifecycle.findingID, initialRevision: lifecycle.initialRevision,
                initialState: lifecycle.initialState, transitions: lifecycle.transitions + [event])
            finding = try FindingV1(findingID: finding.findingID, revision: event.resultingFindingRevision,
                severity: finding.severity, categoryID: finding.categoryID, subject: finding.subject,
                source: finding.source, summary: finding.summary)
        case let .linkC14CorrectiveWork(value):
            try validateLinkBasis(value.event, finding: finding, links: links)
            links.append(value.event)
            let support = value.support
            if let retained = supports.first(where: {
                $0.correctiveWorkID == support.correctiveWorkID && $0.correctiveWorkRevision == support.correctiveWorkRevision
                    && $0.selected.eventRevision == support.selected.eventRevision
            }) {
                guard try WorkspaceMutationCanonicalV1.data(retained) == WorkspaceMutationCanonicalV1.data(support) else {
                    throw FindingContractFailureV1.historyRewrite
                }
            } else { supports.append(support) }
            supports.sort(by: FindingMutationValidationV1.supportPrecedes)
        case let .removeCorrectiveWork(event):
            try validateLinkBasis(event, finding: finding, links: links)
            let history = links.filter { $0.workID == event.workID }
            guard let last = history.last, last.action == .linked, last.workRevision == event.workRevision else {
                throw FindingContractFailureV1.invalidTransition
            }
            links.append(event)
        }
        let evidence = try FindingLifecycleCanonicalEvidenceV1(finding: finding, lifecycle: lifecycle,
            correctiveWorkLinks: links, verifiedRechecks: basis.verifiedRechecks, releasesToService: basis.releasesToService,
            operationalDispositionEvents: basis.operationalDispositionEvents)
        let facts = try FindingOwnedFactsV1(evidence: evidence, activitySource: old.activitySource, correctiveActions: supports)
        let result = try FindingOwnerRecordV1(workspaceID: workspaceID, kind: .finding, ownerID: ownerID,
            ownerRevision: prior.ownerRevision + 1, predecessor: prior.reference, mutationID: mutationID,
            recordedBy: recordedBy, recordedAt: recordedAt, origin: prior.origin, finding: facts)
        try result.validateAppendOnlySuccessor(of: prior)
        return result
    }

    private func validateLinkBasis(_ event: CorrectiveWorkLinkV1, finding: FindingV1,
                                   links: [CorrectiveWorkLinkV1]) throws {
        guard event.findingID == finding.findingID, event.findingRevision == finding.revision else {
            throw FindingContractFailureV1.staleRevision
        }
        guard !links.contains(where: { $0.linkID == event.linkID || $0.mutationID == event.mutationID }) else {
            throw FindingContractFailureV1.duplicateIdentity
        }
    }

    func canonicalSHA256() throws -> String {
        KernelCanonicalHashV1.sha256(try FindingOwnerMutationCanonicalCodecV1.encode(self))
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case workspaceID, expectedRevision, mutationID, ownerID, predecessor, recordedBy, recordedAt, operation
    }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue),
            required: CodingKeys.allCases.filter { $0 != .predecessor }.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try FindingMutationValidationV1.nonnull(c, keys: [.predecessor])
        try self.init(workspaceID: FindingMutationValidationV1.workspace(c.superDecoder(forKey: .workspaceID)),
            expectedRevision: FindingMutationValidationV1.frontier(c.superDecoder(forKey: .expectedRevision)),
            mutationID: c.decode(MutationIDV1.self, forKey: .mutationID), ownerID: c.decode(UUID.self, forKey: .ownerID),
            predecessor: c.decodeIfPresent(FindingSelectedOwnerReferenceV1.self, forKey: .predecessor),
            recordedBy: FindingMutationValidationV1.actor(c.superDecoder(forKey: .recordedBy)),
            recordedAt: c.decode(Date.self, forKey: .recordedAt), operation: c.decode(FindingOwnerOperationV1.self, forKey: .operation))
    }
    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(workspaceID, forKey: .workspaceID)
        try c.encode(expectedRevision, forKey: .expectedRevision)
        try c.encode(mutationID, forKey: .mutationID)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encodeIfPresent(predecessor, forKey: .predecessor)
        try c.encode(recordedBy, forKey: .recordedBy)
        try c.encode(recordedAt, forKey: .recordedAt)
        try c.encode(operation, forKey: .operation)
    }
}

enum FindingOwnerMutationCanonicalCodecV1 {
    static func encode(_ value: FindingOwnerMutationV1) throws -> Data {
        try value.validate()
        let bytes = try WorkspaceMutationCanonicalV1.data(value)
        guard bytes.count <= FindingContractLimitsV1.maximumCanonicalBytes else { throw FindingContractFailureV1.limitExceeded }
        return bytes
    }
    static func decode(_ bytes: Data) throws -> FindingOwnerMutationV1 {
        guard !bytes.isEmpty, bytes.count <= FindingContractLimitsV1.maximumCanonicalBytes else {
            throw FindingContractFailureV1.limitExceeded
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(FindingOwnerMutationV1.self, from: bytes)
        guard try encode(value) == bytes else { throw FindingContractFailureV1.canonicalEvidenceIncomplete }
        return value
    }
}

private enum FindingMutationValidationV1 {
    private struct AcceptanceKey: Hashable {
        let workspaceID: WorkspaceID
        let mutationID: MutationIDV1
    }
    /// One command may select several facts from one acceptance. This only
    /// checks their agreement; the writer must authenticate the actual bytes.
    static func acceptances(_ values: [FindingAcceptedMutationReferenceV1]) throws {
        var seen: [AcceptanceKey: FindingAcceptedMutationReferenceV1] = [:]
        for value in values {
            try value.validate()
            let key = AcceptanceKey(workspaceID: value.workspaceID, mutationID: value.mutationID)
            if let prior = seen[key], prior != value { throw FindingContractFailureV1.historyRewrite }
            seen[key] = value
        }
    }
    private static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static func id(_ value: UUID) throws {
        guard value != zero else { throw FindingContractFailureV1.invalidValue }
    }
    static func incrementable(_ value: Int) throws {
        guard value >= 0, value < Int.max else { throw FindingContractFailureV1.invalidValue }
    }
    static func nonnull<Key: CodingKey>(_ c: KeyedDecodingContainer<Key>, keys: [Key]) throws {
        for key in keys where c.contains(key) {
            if try c.decodeNil(forKey: key) { throw FindingContractFailureV1.invalidValue }
        }
    }
    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }
    static func preflight(_ decoder: any Decoder, field: String) throws {
        let c = try decoder.container(keyedBy: Key.self)
        try incrementable(c.decode(Int.self, forKey: Key(field)))
    }
    static func link(_ value: CorrectiveWorkLinkV1) throws {
        try incrementable(value.expectedLinkRevision)
        _ = try JSONDecoder().decode(CorrectiveWorkLinkV1.self, from: WorkspaceMutationCanonicalV1.data(value))
    }
    static func workspace(_ decoder: any Decoder) throws -> WorkspaceID {
        try FindingClosedCodingV1.requireExact(decoder, keys: ["rawValue"])
        let value = try WorkspaceID(from: decoder)
        try id(value.rawValue)
        return value
    }
    static func frontier(_ value: WorkspaceExpectedRevisionV1) throws {
        try id(value.workspaceID.rawValue)
        try id(value.generationID)
        try id(value.writerInstanceID)
        // This is the whole workspace frontier, not a selected C04 registry.
        // Bound allocation by the command byte limit, as the selection codec does.
        guard value.workspaceRevision < UInt64.max,
              value.entityRevisions.count <= FindingContractLimitsV1.maximumCanonicalBytes else {
            throw FindingContractFailureV1.limitExceeded
        }
        var seen = Set<WorkspaceEntityIdentityV1>()
        var previous: String?
        for entry in value.entityRevisions {
            try id(entry.identity.id)
            guard seen.insert(entry.identity).inserted else { throw FindingContractFailureV1.duplicateIdentity }
            if let previous, previous >= entry.identity.stableKey { throw FindingContractFailureV1.invalidValue }
            previous = entry.identity.stableKey
        }
    }
    static func frontier(_ decoder: any Decoder) throws -> WorkspaceExpectedRevisionV1 {
        try FindingClosedCodingV1.requireExact(decoder,
            keys: ["workspaceID", "generationID", "writerInstanceID", "workspaceRevision", "entityRevisions"])
        let c = try decoder.container(keyedBy: Key.self)
        _ = try workspace(c.superDecoder(forKey: Key("workspaceID")))
        var entries = try c.nestedUnkeyedContainer(forKey: Key("entityRevisions"))
        var count = 0
        while !entries.isAtEnd {
            guard count < FindingContractLimitsV1.maximumCanonicalBytes else { throw FindingContractFailureV1.limitExceeded }
            let entry = try entries.superDecoder()
            try FindingClosedCodingV1.requireExact(entry, keys: ["identity", "revision"])
            let fields = try entry.container(keyedBy: Key.self)
            try FindingClosedCodingV1.requireExact(fields.superDecoder(forKey: Key("identity")), keys: ["kind", "id"])
            count += 1
        }
        let value = try WorkspaceExpectedRevisionV1(from: decoder)
        try frontier(value)
        return value
    }
    static func actor(_ decoder: any Decoder) throws -> ActorSnapshotV1 {
        try FindingClosedCodingV1.requireExact(decoder, keys: ["schemaVersion", "snapshotID", "workspaceID", "actor",
            "responsibility", "displayNameAtTime", "capturedAt", "snapshotSHA256"])
        let c = try decoder.container(keyedBy: Key.self)
        _ = try workspace(c.superDecoder(forKey: Key("workspaceID")))
        let local = try c.superDecoder(forKey: Key("actor"))
        try FindingClosedCodingV1.requireClosed(local,
            allowed: ["schemaVersion", "actorReferenceID", "workspaceID", "partyID", "displayName"],
            required: ["schemaVersion", "actorReferenceID", "workspaceID", "displayName"])
        let fields = try local.container(keyedBy: Key.self)
        _ = try workspace(fields.superDecoder(forKey: Key("workspaceID")))
        try nonnull(fields, keys: [Key("partyID")])
        let value = try ActorSnapshotV1(from: decoder)
        try value.validate()
        return value
    }
    static func scale(_ decoder: any Decoder) throws -> SeverityScaleReleaseV1 {
        let required = ["schemaVersion", "releaseID", "workspaceID", "scaleID", "designation", "levels", "recordedAt",
                        "revision", "mutationID", "releaseSHA256"]
        try FindingClosedCodingV1.requireClosed(decoder, allowed: required + ["supersedesReleaseID"], required: required)
        let c = try decoder.container(keyedBy: Key.self)
        _ = try workspace(c.superDecoder(forKey: Key("workspaceID")))
        try nonnull(c, keys: [Key("supersedesReleaseID")])
        var levels = try c.nestedUnkeyedContainer(forKey: Key("levels"))
        var count = 0
        while !levels.isAtEnd {
            guard count < 64 else { throw FindingContractFailureV1.limitExceeded }
            try FindingClosedCodingV1.requireExact(levels.superDecoder(), keys: ["levelID", "localizedLabelKey", "descriptionKey"])
            count += 1
        }
        let value = try SeverityScaleReleaseV1(from: decoder)
        try value.validate()
        return value
    }
    static func classification(_ decoder: any Decoder) throws -> FindingClassificationBindingV1 {
        let required = ["schemaVersion", "bindingID", "workspaceID", "findingID", "criterionID", "result",
                        "applicabilityContextID", "assessmentScopeID", "recordedAt", "revision", "mutationID", "bindingSHA256"]
        let optional = ["severityScaleReleaseID", "severityLevelID", "supersedesBindingID"]
        try FindingClosedCodingV1.requireClosed(decoder, allowed: required + optional, required: required)
        let c = try decoder.container(keyedBy: Key.self)
        _ = try workspace(c.superDecoder(forKey: Key("workspaceID")))
        try nonnull(c, keys: optional.map { Key($0) })
        let value = try FindingClassificationBindingV1(from: decoder)
        try value.validate()
        return value
    }
    static func supportPrecedes(_ lhs: FindingC14SupportReferenceV1, _ rhs: FindingC14SupportReferenceV1) -> Bool {
        if lhs.correctiveWorkID != rhs.correctiveWorkID { return lhs.correctiveWorkID < rhs.correctiveWorkID }
        if lhs.correctiveWorkRevision != rhs.correctiveWorkRevision { return lhs.correctiveWorkRevision < rhs.correctiveWorkRevision }
        return lhs.selected.eventRevision < rhs.selected.eventRevision
    }
}
