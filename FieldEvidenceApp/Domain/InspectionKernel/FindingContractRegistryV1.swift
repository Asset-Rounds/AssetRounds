import Foundation

struct FindingContractRegistryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let contractSchema: String
    let severityBindingFields: [String]
    let findingStates: [String]
    let operationalDispositionStates: [String]
    let correctiveWorkLinkActions: [String]
    let verifiedRecheckOutcomes: [String]
    let relationshipKinds: [String]
    let relationshipDecisions: [String]
    let declarationOnly: Bool
    let canonicalWriteEnabled: Bool
    let migrationBehaviorDelta: Bool
    let backupBehaviorDelta: Bool
    let restoreBehaviorDelta: Bool
    let deleteBehaviorDelta: Bool
    let exportBehaviorDelta: Bool
    let downgradeDisposition: String

    init() {
        schemaVersion = Self.schemaVersion
        contractSchema = "KERNEL_FINDING_V1"
        severityBindingFields = ["severityID", "severityScaleReleaseID", "severityScaleSHA256"]
        findingStates = FindingStateV1.allCases.map(\.rawValue).sorted()
        operationalDispositionStates = OperationalDispositionStateV1.allCases.map(\.rawValue).sorted()
        correctiveWorkLinkActions = CorrectiveWorkLinkActionV1.allCases.map(\.rawValue).sorted()
        verifiedRecheckOutcomes = VerifiedRecheckOutcomeV1.allCases.map(\.rawValue).sorted()
        relationshipKinds = WorkRelationshipKindV1.allCases.map(\.rawValue).sorted()
        relationshipDecisions = WorkRelationshipDecisionKindV1.allCases.map(\.rawValue).sorted()
        declarationOnly = true
        canonicalWriteEnabled = false
        migrationBehaviorDelta = false
        backupBehaviorDelta = false
        restoreBehaviorDelta = false
        deleteBehaviorDelta = false
        exportBehaviorDelta = false
        downgradeDisposition = "DORMANT_REVERT_ALLOWED"
    }

    func validate() throws {
        guard self == Self.init() else { throw FindingContractFailureV1.incompatibleVersion }
    }
}

struct FindingContractRegistryPublicationReceiptV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let contractSchema: String
    let canonicalSHA256: String
    let canonicalByteCount: Int
    let complete: Bool
}

struct FindingLifecycleCanonicalEvidenceV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let finding: FindingV1
    let lifecycle: FindingLifecycleV1
    let correctiveWorkLinks: [CorrectiveWorkLinkV1]
    let verifiedRechecks: [VerifiedRecheckV1]
    let releasesToService: [ReleaseToServiceV1]
    let operationalDispositionEvents: [OperationalDispositionEventV1]
    let relatedWorkSuggestions: [RelatedWorkSuggestionV1]
    let workRelationships: [WorkRelationshipV1]
    let workRelationshipDecisions: [WorkRelationshipDecisionV1]

    init(
        finding: FindingV1,
        lifecycle: FindingLifecycleV1,
        correctiveWorkLinks: [CorrectiveWorkLinkV1] = [],
        verifiedRechecks: [VerifiedRecheckV1] = [],
        releasesToService: [ReleaseToServiceV1] = [],
        operationalDispositionEvents: [OperationalDispositionEventV1] = [],
        relatedWorkSuggestions: [RelatedWorkSuggestionV1] = [],
        workRelationships: [WorkRelationshipV1] = [],
        workRelationshipDecisions: [WorkRelationshipDecisionV1] = []
    ) throws {
        schemaVersion = Self.schemaVersion
        self.finding = finding
        self.lifecycle = lifecycle
        self.correctiveWorkLinks = correctiveWorkLinks.sorted {
            ($0.findingID, $0.workID, $0.expectedLinkRevision, $0.linkID)
                < ($1.findingID, $1.workID, $1.expectedLinkRevision, $1.linkID)
        }
        self.verifiedRechecks = verifiedRechecks.sorted {
            ($0.findingID, $0.correctiveWorkID, $0.expectedRecheckRevision, $0.recheckID)
                < ($1.findingID, $1.correctiveWorkID, $1.expectedRecheckRevision, $1.recheckID)
        }
        self.releasesToService = releasesToService.sorted { $0.releaseID < $1.releaseID }
        self.operationalDispositionEvents = operationalDispositionEvents.sorted {
            ($0.expectedDispositionRevision, $0.eventID)
                < ($1.expectedDispositionRevision, $1.eventID)
        }
        self.relatedWorkSuggestions = relatedWorkSuggestions.sorted { $0.suggestionID < $1.suggestionID }
        self.workRelationships = workRelationships.sorted { $0.relationshipID < $1.relationshipID }
        self.workRelationshipDecisions = workRelationshipDecisions.sorted {
            ($0.suggestionID, $0.expectedDecisionRevision, $0.decisionID)
                < ($1.suggestionID, $1.expectedDecisionRevision, $1.decisionID)
        }
        try validate()
    }

    func validate() throws {
        let counts = [
            correctiveWorkLinks.count,
            verifiedRechecks.count,
            releasesToService.count,
            operationalDispositionEvents.count,
            relatedWorkSuggestions.count,
            workRelationships.count,
            workRelationshipDecisions.count,
        ]
        guard schemaVersion == Self.schemaVersion,
              counts.allSatisfy({ $0 <= FindingContractLimitsV1.maximumRegistryEntries }),
              correctiveWorkLinks == correctiveWorkLinks.sorted(by: {
                ($0.findingID, $0.workID, $0.expectedLinkRevision, $0.linkID)
                    < ($1.findingID, $1.workID, $1.expectedLinkRevision, $1.linkID)
              }),
              verifiedRechecks == verifiedRechecks.sorted(by: {
                ($0.findingID, $0.correctiveWorkID, $0.expectedRecheckRevision, $0.recheckID)
                    < ($1.findingID, $1.correctiveWorkID, $1.expectedRecheckRevision, $1.recheckID)
              }),
              releasesToService == releasesToService.sorted(by: { $0.releaseID < $1.releaseID }),
              operationalDispositionEvents == operationalDispositionEvents.sorted(by: {
                ($0.expectedDispositionRevision, $0.eventID)
                    < ($1.expectedDispositionRevision, $1.eventID)
              }),
              relatedWorkSuggestions == relatedWorkSuggestions.sorted(by: { $0.suggestionID < $1.suggestionID }),
              workRelationships == workRelationships.sorted(by: { $0.relationshipID < $1.relationshipID }),
              workRelationshipDecisions == workRelationshipDecisions.sorted(by: {
                ($0.suggestionID, $0.expectedDecisionRevision, $0.decisionID)
                    < ($1.suggestionID, $1.expectedDecisionRevision, $1.decisionID)
              }) else {
            throw FindingContractFailureV1.canonicalEvidenceIncomplete
        }

        try lifecycle.validate()
        guard finding.findingID == lifecycle.findingID,
              finding.revision == lifecycle.currentRevision,
              correctiveWorkLinks.allSatisfy({
                $0.findingID == finding.findingID && $0.findingRevision <= lifecycle.currentRevision
              }),
              verifiedRechecks.allSatisfy({ $0.findingID == lifecycle.findingID }),
              verifiedRechecks.allSatisfy({ $0.findingRevision <= lifecycle.currentRevision }),
              releasesToService.allSatisfy({
                $0.findingID == finding.findingID
                    && $0.subjectID == finding.subject.subjectID
                    && $0.findingRevision <= lifecycle.currentRevision
              }),
              operationalDispositionEvents.allSatisfy({
                $0.findingID == finding.findingID
                    && $0.subjectID == finding.subject.subjectID
                    && $0.findingRevision <= lifecycle.currentRevision
              }),
              relatedWorkSuggestions.allSatisfy({
                $0.subjectID == finding.subject.subjectID
                    && $0.categoryID == finding.categoryID
              }) else {
            throw FindingContractFailureV1.canonicalEvidenceIncomplete
        }
        try requireUnique(correctiveWorkLinks.map(\.linkID))
        try requireUnique(correctiveWorkLinks.map(\.mutationID))
        try requireUnique(verifiedRechecks.map(\.recheckID))
        try requireUnique(verifiedRechecks.map(\.mutationID))
        try requireUnique(releasesToService.map(\.releaseID))
        try requireUnique(releasesToService.map(\.mutationID))
        try lifecycle.validateVerifiedResolutionLineage(verifiedRechecks)

        let correctiveGroups = Dictionary(grouping: correctiveWorkLinks) {
            "\($0.findingID)|\($0.workID)"
        }
        for key in correctiveGroups.keys.sorted() {
            guard let history = correctiveGroups[key] else { continue }
            try CorrectiveWorkLinkLedgerV1.validate(history)
        }
        let recheckGroups = Dictionary(grouping: verifiedRechecks) {
            "\($0.findingID)|\($0.correctiveWorkID)"
        }
        for key in recheckGroups.keys.sorted() {
            guard let history = recheckGroups[key] else { continue }
            try VerifiedRecheckLineageV1.validate(history)
        }
        for recheck in verifiedRechecks {
            let key = "\(recheck.findingID)|\(recheck.correctiveWorkID)"
            let effective = correctiveGroups[key]?
                .filter { $0.findingRevision <= recheck.findingRevision }
                .max {
                    ($0.resultingLinkRevision, $0.linkID)
                        < ($1.resultingLinkRevision, $1.linkID)
                }
            guard let effective,
                  effective.action == .linked,
                  effective.workRevision == recheck.correctiveWorkRevision else {
                throw FindingContractFailureV1.canonicalEvidenceIncomplete
            }
        }

        if !operationalDispositionEvents.isEmpty {
            try OperationalDispositionLedgerV1.validate(operationalDispositionEvents)
        }
        for release in releasesToService {
            let rechecks = verifiedRechecks.filter { $0.recheckID == release.verifiedRecheckID }
            guard rechecks.count == 1 else {
                throw FindingContractFailureV1.canonicalEvidenceIncomplete
            }
            try release.validate(against: rechecks[0])
        }
        for event in operationalDispositionEvents where event.state == .returnedToServiceRecorded {
            let releases = releasesToService.filter { $0.releaseID == event.releaseToServiceID }
            guard releases.count == 1 else {
                throw FindingContractFailureV1.canonicalEvidenceIncomplete
            }
            let rechecks = verifiedRechecks.filter { $0.recheckID == releases[0].verifiedRecheckID }
            guard rechecks.count == 1 else { throw FindingContractFailureV1.canonicalEvidenceIncomplete }
            try OperationalDispositionLedgerV1.validateReturnedToService(
                event: event, release: releases[0], verifiedRecheck: rechecks[0]
            )
        }

        try WorkRelationshipValidatorV1.validateSuggestions(relatedWorkSuggestions)
        try WorkRelationshipValidatorV1.validate(workRelationships)
        try WorkRelationshipDecisionLedgerV1.validate(workRelationshipDecisions)
        for decision in workRelationshipDecisions {
            let suggestions = relatedWorkSuggestions.filter { suggestion in
                suggestion.suggestionID == decision.suggestionID
                    && suggestion.sourceWorkID == decision.sourceWorkID
                    && suggestion.sourceWorkRevision == decision.sourceWorkRevision
                    && suggestion.candidateWorkID == decision.candidateWorkID
                    && suggestion.candidateWorkRevision == decision.candidateWorkRevision
                    && suggestion.policySHA256 == decision.policySHA256
            }
            guard suggestions.count == 1,
                  RelatedWorkSuggestionV1.identity(
                    sourceWorkID: decision.sourceWorkID,
                    sourceWorkRevision: decision.sourceWorkRevision,
                    candidateWorkID: decision.candidateWorkID,
                    candidateWorkRevision: decision.candidateWorkRevision,
                    policySHA256: decision.policySHA256
                  ) == decision.suggestionID else {
                throw FindingContractFailureV1.canonicalEvidenceIncomplete
            }

            if decision.decision == .notRelated {
                guard decision.relationshipID == nil else {
                    throw FindingContractFailureV1.canonicalEvidenceIncomplete
                }
                continue
            }
            guard let relationshipID = decision.relationshipID else {
                throw FindingContractFailureV1.canonicalEvidenceIncomplete
            }
            let relationships = workRelationships.filter { $0.relationshipID == relationshipID }
            guard relationships.count == 1,
                  relationshipMatches(relationships[0], decision: decision) else {
                throw FindingContractFailureV1.canonicalEvidenceIncomplete
            }
        }
        for relationship in workRelationships {
            let confirmations = workRelationshipDecisions.filter {
                $0.decision == .confirm && $0.relationshipID == relationship.relationshipID
            }
            guard confirmations.count == 1,
                  relationshipMatches(relationship, decision: confirmations[0]) else {
                throw FindingContractFailureV1.canonicalEvidenceIncomplete
            }
        }
    }

    private func relationshipMatches(
        _ relationship: WorkRelationshipV1,
        decision: WorkRelationshipDecisionV1
    ) -> Bool {
        let forward = relationship.sourceWorkID == decision.sourceWorkID
            && relationship.sourceWorkRevision == decision.sourceWorkRevision
            && relationship.targetWorkID == decision.candidateWorkID
            && relationship.targetWorkRevision == decision.candidateWorkRevision
        if relationship.direction == .directed { return forward }
        let reverse = relationship.sourceWorkID == decision.candidateWorkID
            && relationship.sourceWorkRevision == decision.candidateWorkRevision
            && relationship.targetWorkID == decision.sourceWorkID
            && relationship.targetWorkRevision == decision.sourceWorkRevision
        return forward || reverse
    }

    private func requireUnique(_ values: [String]) throws {
        guard Set(values).count == values.count else {
            throw FindingContractFailureV1.canonicalEvidenceIncomplete
        }
    }
}

enum FindingLifecycleCanonicalEvidenceCodecV1 {
    static func encode(_ evidence: FindingLifecycleCanonicalEvidenceV1) throws -> Data {
        try evidence.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(evidence)
        guard bytes.count <= FindingContractLimitsV1.maximumCanonicalBytes else {
            throw FindingContractFailureV1.limitExceeded
        }
        return bytes
    }

    static func decode(_ bytes: Data) throws -> FindingLifecycleCanonicalEvidenceV1 {
        guard !bytes.isEmpty, bytes.count <= FindingContractLimitsV1.maximumCanonicalBytes else {
            throw FindingContractFailureV1.limitExceeded
        }
        let evidence = try JSONDecoder().decode(FindingLifecycleCanonicalEvidenceV1.self, from: bytes)
        try evidence.validate()
        guard try encode(evidence) == bytes else {
            throw FindingContractFailureV1.canonicalEvidenceIncomplete
        }
        return evidence
    }
}

extension FindingLifecycleCanonicalEvidenceV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, finding, lifecycle, correctiveWorkLinks, verifiedRechecks, releasesToService
        case operationalDispositionEvents, relatedWorkSuggestions, workRelationships
        case workRelationshipDecisions
    }

    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw FindingContractFailureV1.incompatibleVersion
        }
        let finding = try c.decode(FindingV1.self, forKey: .finding)
        let lifecycle = try c.decode(FindingLifecycleV1.self, forKey: .lifecycle)
        let correctiveWorkLinks = try c.decode([CorrectiveWorkLinkV1].self, forKey: .correctiveWorkLinks)
        let verifiedRechecks = try c.decode([VerifiedRecheckV1].self, forKey: .verifiedRechecks)
        let releases = try c.decode([ReleaseToServiceV1].self, forKey: .releasesToService)
        let events = try c.decode([OperationalDispositionEventV1].self, forKey: .operationalDispositionEvents)
        let suggestions = try c.decode([RelatedWorkSuggestionV1].self, forKey: .relatedWorkSuggestions)
        let relationships = try c.decode([WorkRelationshipV1].self, forKey: .workRelationships)
        let decisions = try c.decode([WorkRelationshipDecisionV1].self, forKey: .workRelationshipDecisions)
        try self.init(
            finding: finding,
            lifecycle: lifecycle,
            correctiveWorkLinks: correctiveWorkLinks,
            verifiedRechecks: verifiedRechecks,
            releasesToService: releases,
            operationalDispositionEvents: events,
            relatedWorkSuggestions: suggestions,
            workRelationships: relationships,
            workRelationshipDecisions: decisions
        )
        guard self.correctiveWorkLinks == correctiveWorkLinks,
              self.verifiedRechecks == verifiedRechecks,
              self.releasesToService == releases,
              self.operationalDispositionEvents == events,
              self.relatedWorkSuggestions == suggestions,
              self.workRelationships == relationships,
              self.workRelationshipDecisions == decisions else {
            throw FindingContractFailureV1.canonicalEvidenceIncomplete
        }
    }
}

enum FindingContractRegistryCanonicalCodecV1 {
    static func encode(_ registry: FindingContractRegistryV1) throws -> Data {
        try registry.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(registry)
        guard bytes.count <= FindingContractLimitsV1.maximumCanonicalBytes else {
            throw FindingContractFailureV1.limitExceeded
        }
        return bytes
    }

    static func decode(_ bytes: Data) throws -> FindingContractRegistryV1 {
        guard !bytes.isEmpty, bytes.count <= FindingContractLimitsV1.maximumCanonicalBytes else {
            throw FindingContractFailureV1.limitExceeded
        }
        let registry = try JSONDecoder().decode(FindingContractRegistryV1.self, from: bytes)
        guard try encode(registry) == bytes else { throw FindingContractFailureV1.hashMismatch }
        return registry
    }
}

enum FindingContractRegistryPublisherV1 {
    enum Boundary: String, CaseIterable, Sendable {
        case beforeValidation = "BEFORE_VALIDATION"
        case afterValidationBeforePublication = "AFTER_VALIDATION_BEFORE_PUBLICATION"
        case afterPublicationBeforeReceipt = "AFTER_PUBLICATION_BEFORE_RECEIPT"
    }
    typealias Interruption = @Sendable (Boundary) throws -> Void

    static func publish(
        interruption: Interruption = { _ in }
    ) throws -> (registry: FindingContractRegistryV1, receipt: FindingContractRegistryPublicationReceiptV1) {
        try interruption(.beforeValidation)
        let registry = FindingContractRegistryV1()
        try registry.validate()
        let bytes = try FindingContractRegistryCanonicalCodecV1.encode(registry)
        try interruption(.afterValidationBeforePublication)
        let receipt = FindingContractRegistryPublicationReceiptV1(
            schemaVersion: 1,
            contractSchema: "KERNEL_FINDING_V1",
            canonicalSHA256: KernelCanonicalHashV1.sha256(bytes),
            canonicalByteCount: bytes.count,
            complete: true
        )
        try interruption(.afterPublicationBeforeReceipt)
        return (registry, receipt)
    }

    static func recover(
        canonicalData: Data?,
        receipt: FindingContractRegistryPublicationReceiptV1?
    ) throws -> FindingContractRegistryV1? {
        switch (canonicalData, receipt) {
        case (nil, nil):
            return nil
        case (.some(let data), .some(let receipt)):
            guard receipt.schemaVersion == 1, receipt.contractSchema == "KERNEL_FINDING_V1",
                  receipt.complete, receipt.canonicalByteCount == data.count,
                  receipt.canonicalSHA256 == KernelCanonicalHashV1.sha256(data) else {
                throw FindingContractFailureV1.hashMismatch
            }
            return try FindingContractRegistryCanonicalCodecV1.decode(data)
        default:
            throw FindingContractFailureV1.publicationInterrupted
        }
    }
}

enum KernelFindingLifecycleV1 {
    static let mode = "DECLARATION_ONLY"
    static let schema = "KERNEL_FINDING_V1"
    static let persistent = false
    static let writerCommandRequired = false
    static let canonicalQueryRequired = false
    static let migrationRequired = false
    static let backupRestoreRequired = false
    static let cloneForkRequired = false
    static let importExportRequired = false
    static let journalReplayRequired = false
    static let searchRebuildReplayRequired = false
    static let deleteEraseRequired = false
    static let retentionRequired = false
    static let compatibilityWriteRequired = false
    static let downgradePolicy = "DORMANT_REVERT_ALLOWED"
    static let forwardFixRequired = false
    static let interruption = "ZERO_OR_COMPLETE"
    static let idempotentReceipt = "EXACT_CANONICAL_BYTES_ADOPTION"
    static let shippingAdoption = "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION"
}

extension FindingContractRegistryV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, contractSchema, severityBindingFields, findingStates
        case operationalDispositionStates, correctiveWorkLinkActions, verifiedRecheckOutcomes
        case relationshipKinds, relationshipDecisions, declarationOnly, canonicalWriteEnabled
        case migrationBehaviorDelta, backupBehaviorDelta, restoreBehaviorDelta
        case deleteBehaviorDelta, exportBehaviorDelta, downgradeDisposition
    }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let expected = Self.init()
        guard try c.decode(Int.self, forKey: .schemaVersion) == expected.schemaVersion,
              try c.decode(String.self, forKey: .contractSchema) == expected.contractSchema,
              try c.decode([String].self, forKey: .severityBindingFields) == expected.severityBindingFields,
              try c.decode([String].self, forKey: .findingStates) == expected.findingStates,
              try c.decode([String].self, forKey: .operationalDispositionStates) == expected.operationalDispositionStates,
              try c.decode([String].self, forKey: .correctiveWorkLinkActions) == expected.correctiveWorkLinkActions,
              try c.decode([String].self, forKey: .verifiedRecheckOutcomes) == expected.verifiedRecheckOutcomes,
              try c.decode([String].self, forKey: .relationshipKinds) == expected.relationshipKinds,
              try c.decode([String].self, forKey: .relationshipDecisions) == expected.relationshipDecisions,
              try c.decode(Bool.self, forKey: .declarationOnly) == expected.declarationOnly,
              try c.decode(Bool.self, forKey: .canonicalWriteEnabled) == expected.canonicalWriteEnabled,
              try c.decode(Bool.self, forKey: .migrationBehaviorDelta) == expected.migrationBehaviorDelta,
              try c.decode(Bool.self, forKey: .backupBehaviorDelta) == expected.backupBehaviorDelta,
              try c.decode(Bool.self, forKey: .restoreBehaviorDelta) == expected.restoreBehaviorDelta,
              try c.decode(Bool.self, forKey: .deleteBehaviorDelta) == expected.deleteBehaviorDelta,
              try c.decode(Bool.self, forKey: .exportBehaviorDelta) == expected.exportBehaviorDelta,
              try c.decode(String.self, forKey: .downgradeDisposition) == expected.downgradeDisposition else {
            throw FindingContractFailureV1.incompatibleVersion
        }
        self = expected
    }
}

extension FindingContractRegistryPublicationReceiptV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, contractSchema, canonicalSHA256, canonicalByteCount, complete }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion); contractSchema = try c.decode(String.self, forKey: .contractSchema)
        canonicalSHA256 = try c.decode(String.self, forKey: .canonicalSHA256); canonicalByteCount = try c.decode(Int.self, forKey: .canonicalByteCount)
        complete = try c.decode(Bool.self, forKey: .complete)
        guard schemaVersion == 1, contractSchema == "KERNEL_FINDING_V1", KernelCanonicalHashV1.validSHA256(canonicalSHA256), canonicalByteCount > 0, complete else { throw FindingContractFailureV1.invalidValue }
    }
}
