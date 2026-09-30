import Foundation

enum CheckRunnerRestoreBeginFailureV1: Error, Equatable {
    case invalidDependency
    case invalidEvidence
    case invalidBinding
}

/// Presence is independent of the journal frontier. Imported rows can be at
/// revision zero, and a retained tombstone can leave an absent row above zero.
enum CheckRunnerDependencyStateV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    case absent(revision: UInt64)
    case present(revision: UInt64, semanticSHA256: String)

    var revision: UInt64 {
        switch self {
        case let .absent(revision), let .present(revision, _): return revision
        }
    }

    func validate() throws {
        if case let .present(_, digest) = self, !KernelCanonicalHashV1.validSHA256(digest) {
            throw CheckRunnerRestoreBeginFailureV1.invalidDependency
        }
        // UInt64.max is a valid observation. Increment eligibility belongs to
        // the live effect planner, which must check the actual current state.
    }

    private enum CodingKeys: String, CodingKey { case state, revision, semanticSHA256 }
    private enum State: String, Codable { case absent = "ABSENT", present = "PRESENT" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let state = try c.decode(State.self, forKey: .state)
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed:
            state == .absent ? ["state", "revision"] : ["state", "revision", "semanticSHA256"])
        let revision = try c.decode(UInt64.self, forKey: .revision)
        switch state {
        case .absent: self = .absent(revision: revision)
        case .present:
            self = .present(revision: revision, semanticSHA256: try c.decode(String.self, forKey: .semanticSHA256))
        }
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(revision, forKey: .revision)
        switch self {
        case .absent: try c.encode(State.absent, forKey: .state)
        case let .present(_, digest):
            try c.encode(State.present, forKey: .state)
            try c.encode(digest, forKey: .semanticSHA256)
        }
    }
}

/// Immutable observations on each side of a restore. Construction establishes
/// value shape; a writer/journal read must authenticate both states before use.
struct CheckRunnerDestinationDependencyV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let sourceIdentity: WorkspaceEntityIdentityV1
    let sourceState: CheckRunnerDependencyStateV1
    let destinationIdentity: WorkspaceEntityIdentityV1
    let destinationStateAtMapping: CheckRunnerDependencyStateV1

    init(sourceIdentity: WorkspaceEntityIdentityV1, sourceState: CheckRunnerDependencyStateV1,
         destinationIdentity: WorkspaceEntityIdentityV1,
         destinationStateAtMapping: CheckRunnerDependencyStateV1) throws {
        self.sourceIdentity = sourceIdentity
        self.sourceState = sourceState
        self.destinationIdentity = destinationIdentity
        self.destinationStateAtMapping = destinationStateAtMapping
        try validate()
    }

    func validate() throws {
        _ = try WorkspaceEntityIdentityV1(kind: sourceIdentity.kind, id: sourceIdentity.id)
        _ = try WorkspaceEntityIdentityV1(kind: destinationIdentity.kind, id: destinationIdentity.id)
        try sourceState.validate()
        try destinationStateAtMapping.validate()
        guard sourceIdentity.kind == destinationIdentity.kind else {
            throw CheckRunnerRestoreBeginFailureV1.invalidDependency
        }
        switch sourceIdentity.kind {
        case .site, .asset, .issue, .workflowRecord: break
        default: throw CheckRunnerRestoreBeginFailureV1.invalidDependency
        }
    }

    func validate(map: CheckRunnerRestoreIdentityMapV1, kind: CheckRunnerRestoreIdentityKindV1) throws {
        try validate()
        try map.validate()
        let expectedKind: WorkspaceEntityKindV1
        switch kind {
        case .site: expectedKind = .site
        case .asset: expectedKind = .asset
        case .issue: expectedKind = .issue
        case .parentRecord, .workflowRecord: expectedKind = .workflowRecord
        default: throw CheckRunnerRestoreBeginFailureV1.invalidDependency
        }
        guard sourceIdentity.kind == expectedKind,
              try map.destinationID(for: sourceIdentity.id, kind: kind) == destinationIdentity.id else {
            throw CheckRunnerRestoreBeginFailureV1.invalidDependency
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceIdentity, sourceState, destinationIdentity, destinationStateAtMapping
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func identity(_ key: CodingKeys) throws -> WorkspaceEntityIdentityV1 {
            let nested = try c.superDecoder(forKey: key)
            try ClosedContractDecodingV1.rejectUnknownKeys(nested, allowed: ["kind", "id"])
            return try WorkspaceEntityIdentityV1(from: nested)
        }
        try self.init(sourceIdentity: identity(.sourceIdentity),
            sourceState: c.decode(CheckRunnerDependencyStateV1.self, forKey: .sourceState),
            destinationIdentity: identity(.destinationIdentity),
            destinationStateAtMapping: c.decode(CheckRunnerDependencyStateV1.self, forKey: .destinationStateAtMapping))
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sourceIdentity, forKey: .sourceIdentity)
        try c.encode(sourceState, forKey: .sourceState)
        try c.encode(destinationIdentity, forKey: .destinationIdentity)
        try c.encode(destinationStateAtMapping, forKey: .destinationStateAtMapping)
    }
}

/// Historical source expectation is separate from entity presence. The exact
/// case preserves the original envelope/receipt, including historical generation
/// provenance. Neither case authorizes a new effect or supplies a current lease.
enum CheckRunnerExpectedSourceBeginEvidenceV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    case absent
    case exact(CheckRunnerBeginCommittedEvidenceV1)

    func validate() throws {
        if case let .exact(evidence) = self {
            _ = try CheckRunnerBeginCommittedEvidenceV1(envelope: evidence.envelope, receipt: evidence.receipt)
        }
    }

    func validate(sourceWorkspaceID: WorkspaceID, sourceMutationID: MutationIDV1) throws {
        _ = try MutationIDV1(rawValue: sourceWorkspaceID.rawValue)
        _ = try MutationIDV1(rawValue: sourceMutationID.rawValue)
        try validate()
        if case let .exact(evidence) = self {
            guard evidence.envelope.workspaceID == sourceWorkspaceID,
                  evidence.envelope.mutationID == sourceMutationID else {
                throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
            }
        }
    }

    private enum CodingKeys: String, CodingKey { case state, envelopeCanonicalData, receiptCanonicalData }
    private enum State: String, Codable { case absent = "ABSENT", exact = "EXACT" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let state = try c.decode(State.self, forKey: .state)
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed:
            state == .absent ? ["state"] : ["state", "envelopeCanonicalData", "receiptCanonicalData"])
        switch state {
        case .absent: self = .absent
        case .exact:
            let envelope = try MutationEnvelopeV1.decodeCanonical(
                from: c.decode(Data.self, forKey: .envelopeCanonicalData))
            let receipt = try MutationReceiptV1.decodeCanonical(
                from: c.decode(Data.self, forKey: .receiptCanonicalData))
            self = .exact(try CheckRunnerBeginCommittedEvidenceV1(envelope: envelope, receipt: receipt))
        }
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .absent: try c.encode(State.absent, forKey: .state)
        case let .exact(evidence):
            try c.encode(State.exact, forKey: .state)
            try c.encode(evidence.envelope.canonicalData(), forKey: .envelopeCanonicalData)
            try c.encode(evidence.receipt.canonicalData(), forKey: .receiptCanonicalData)
        }
    }
}

/// A separate destination overlay. The original source attempt remains intact:
/// its operational record mutation still equals its canonical record ID. A fork
/// maps only this overlay's operational mutation IDs through the identity map.
struct CheckRunnerDestinationBeginBindingV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let destinationWorkspaceID: WorkspaceID
    let recordMutationID: MutationIDV1
    let recordCommand: CheckDraftMutationV1
    let recordMappedDependencyBasis: [CheckRunnerDestinationDependencyV1]
    let recordCommittedAt: Date
    let timeZoneMutationID: MutationIDV1?
    let timeZoneCommand: SiteTimeZoneMutationV1?
    let timeZoneMappedDependencyBasis: [CheckRunnerDestinationDependencyV1]?
    let timeZoneCommittedAt: Date?

    init(source: CheckRunnerFrozenBeginAttemptV1, map: CheckRunnerRestoreIdentityMapV1,
         recordMappedDependencyBasis: [CheckRunnerDestinationDependencyV1],
         timeZoneMappedDependencyBasis: [CheckRunnerDestinationDependencyV1]?) throws {
        try source.validate()
        try map.validate()
        destinationWorkspaceID = WorkspaceID(rawValue: map.destinationWorkspaceID)
        recordMutationID = try MutationIDV1(rawValue:
            map.destinationID(for: source.recordMutationID.rawValue, kind: .beginRecordMutation))
        recordCommand = source.recordCommand
        self.recordMappedDependencyBasis = recordMappedDependencyBasis.sorted(by: Self.precedes)
        recordCommittedAt = source.recordCommittedAt
        if let zone = source.timeZone {
            timeZoneMutationID = try MutationIDV1(rawValue:
                map.destinationID(for: zone.mutationID.rawValue, kind: .beginTimeZoneMutation))
            timeZoneCommand = zone.command
            timeZoneCommittedAt = zone.committedAt
        } else {
            timeZoneMutationID = nil
            timeZoneCommand = nil
            timeZoneCommittedAt = nil
        }
        self.timeZoneMappedDependencyBasis = timeZoneMappedDependencyBasis?.sorted(by: Self.precedes)
        try validate(source: source, map: map)
    }

    /// Decoded value shape only. Before publication or live use, the enclosing
    /// correspondence must also validate against its original source and map.
    func validate() throws {
        _ = try MutationIDV1(rawValue: destinationWorkspaceID.rawValue)
        _ = try MutationIDV1(rawValue: recordMutationID.rawValue)
        guard recordCommittedAt.timeIntervalSince1970.isFinite,
              recordCommittedAt.timeIntervalSince1970 >= 0 else {
            throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
        let record = recordCommand
        var required = try [
            WorkspaceEntityIdentityV1(kind: .workflowRecord, id: record.recordID),
            WorkspaceEntityIdentityV1(kind: .asset, id: record.assetID)
        ]
        if let id = record.issueID { required.append(try .init(kind: .issue, id: id)) }
        if let id = record.parentRecordID { required.append(try .init(kind: .workflowRecord, id: id)) }
        let sites = recordMappedDependencyBasis.filter { $0.sourceIdentity.kind == .site }
        guard sites.count == 1 else { throw CheckRunnerRestoreBeginFailureV1.invalidBinding }
        required.append(sites[0].sourceIdentity)
        try Self.validateBasis(recordMappedDependencyBasis, required: required)
        for dependency in recordMappedDependencyBasis {
            // Only the new workflow target has an absence alternative. Every
            // referenced row must exist on both sides, including imported zero
            // revisions. Live readers must still authenticate these observations.
            if dependency.sourceIdentity.kind == .workflowRecord,
               dependency.sourceIdentity.id == record.recordID { continue }
            guard case .present = dependency.sourceState,
                  case .present = dependency.destinationStateAtMapping else {
                throw CheckRunnerRestoreBeginFailureV1.invalidBinding
            }
        }

        switch (timeZoneMutationID, timeZoneCommand, timeZoneMappedDependencyBasis, timeZoneCommittedAt) {
        case (nil, nil, nil, nil): break
        case let (.some(mutationID), .some(command), .some(basis), .some(committedAt)):
            _ = try MutationIDV1(rawValue: mutationID.rawValue)
            guard mutationID != recordMutationID,
                  committedAt.timeIntervalSince1970.isFinite,
                  committedAt.timeIntervalSince1970 >= 0,
                  command.confirmedAt.timeIntervalSince1970.isFinite,
                  TimeZone.knownTimeZoneIdentifiers.contains(command.timeZoneID),
                  TimeZone(identifier: command.timeZoneID) != nil,
                  command.siteID == sites[0].sourceIdentity.id,
                  command.timeZoneID == record.timeZoneID,
                  command.confirmedAt == record.observedAtUTC else {
                throw CheckRunnerRestoreBeginFailureV1.invalidBinding
            }
            try Self.validateBasis(basis, required: [sites[0].sourceIdentity])
            guard basis == sites else { throw CheckRunnerRestoreBeginFailureV1.invalidBinding }
        default: throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
        _ = try FieldDraftCanonicalCodecV1.encode(record)
    }

    func validate(source: CheckRunnerFrozenBeginAttemptV1, map: CheckRunnerRestoreIdentityMapV1) throws {
        try validate()
        try source.validate()
        try map.validate()
        guard map.sourceWorkspaceID == source.sourceWorkspaceID.rawValue,
              destinationWorkspaceID.rawValue == map.destinationWorkspaceID,
              recordMutationID.rawValue == (try map.destinationID(
                for: source.recordMutationID.rawValue, kind: .beginRecordMutation)),
              try FieldDraftCanonicalCodecV1.encode(recordCommand) == FieldDraftCanonicalCodecV1.encode(source.recordCommand),
              recordCommittedAt == source.recordCommittedAt else {
            throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
        for dependency in recordMappedDependencyBasis {
            let kind: CheckRunnerRestoreIdentityKindV1
            switch dependency.sourceIdentity.kind {
            case .site:
                guard dependency.sourceIdentity.id == source.siteID else {
                    throw CheckRunnerRestoreBeginFailureV1.invalidBinding
                }
                kind = .site
            case .asset: kind = .asset
            case .issue: kind = .issue
            case .workflowRecord:
                kind = dependency.sourceIdentity.id == source.recordCommand.recordID ? .workflowRecord : .parentRecord
            default: throw CheckRunnerRestoreBeginFailureV1.invalidBinding
            }
            try dependency.validate(map: map, kind: kind)
        }
        switch (source.timeZone, timeZoneMutationID, timeZoneCommand, timeZoneCommittedAt) {
        case (nil, nil, nil, nil): break
        case let (.some(original), .some(mutationID), .some(command), .some(committedAt)):
            guard mutationID.rawValue == (try map.destinationID(
                    for: original.mutationID.rawValue, kind: .beginTimeZoneMutation)),
                  try FieldDraftCanonicalCodecV1.encode(command) == FieldDraftCanonicalCodecV1.encode(original.command),
                  committedAt == original.committedAt else {
                throw CheckRunnerRestoreBeginFailureV1.invalidBinding
            }
        default: throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
    }

    func canonicalSHA256() throws -> String {
        try validate()
        return try FieldDraftCanonicalCodecV1.sha256(self)
    }

    private static func precedes(_ lhs: CheckRunnerDestinationDependencyV1,
                                 _ rhs: CheckRunnerDestinationDependencyV1) -> Bool {
        lhs.sourceIdentity.stableKey < rhs.sourceIdentity.stableKey
    }

    private static func validateBasis(_ basis: [CheckRunnerDestinationDependencyV1],
                                      required: [WorkspaceEntityIdentityV1]) throws {
        try basis.forEach { try $0.validate() }
        guard Set(required).count == required.count,
              basis == basis.sorted(by: precedes),
              basis.map(\.sourceIdentity) == required.sorted(by: { $0.stableKey < $1.stableKey }),
              Set(basis.map(\.destinationIdentity)).count == basis.count else {
            throw CheckRunnerRestoreBeginFailureV1.invalidBinding
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case destinationWorkspaceID, recordMutationID, recordCommand, recordMappedDependencyBasis, recordCommittedAt
        case timeZoneMutationID, timeZoneCommand, timeZoneMappedDependencyBasis, timeZoneCommittedAt
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let workspace = try c.superDecoder(forKey: .destinationWorkspaceID)
        try ClosedContractDecodingV1.rejectUnknownKeys(workspace, allowed: ["rawValue"])
        destinationWorkspaceID = try WorkspaceID(from: workspace)
        recordMutationID = try c.decode(MutationIDV1.self, forKey: .recordMutationID)
        let command = try c.superDecoder(forKey: .recordCommand)
        try ClosedContractDecodingV1.rejectUnknownKeys(command, allowed: [
            "recordID", "assetID", "issueID", "parentRecordID", "stage", "draftStepKey",
            "startedAt", "observedAtUTC", "timeZoneID", "utcOffsetMinutes", "localDate", "localTime",
            "afterDarkAcknowledgementKey", "afterDarkAcknowledgementCopy", "afterDarkAcknowledgementVersion",
            "afterDarkAcknowledgementAccepted", "safePositionAcknowledgementKey", "safePositionAcknowledgementCopy",
            "safePositionAcknowledgementVersion", "safePositionAcknowledgementAccepted", "packID", "packSchemaVersion",
            "packContentVersion", "pdfTemplateID", "pdfTemplateVersion", "observationBasis", "temporalContext"
        ])
        recordCommand = try CheckDraftMutationV1(from: command)
        recordMappedDependencyBasis = try c.decode([CheckRunnerDestinationDependencyV1].self, forKey: .recordMappedDependencyBasis)
        recordCommittedAt = try c.decode(Date.self, forKey: .recordCommittedAt)
        timeZoneMutationID = try c.decodeIfPresent(MutationIDV1.self, forKey: .timeZoneMutationID)
        if c.contains(.timeZoneCommand), try !c.decodeNil(forKey: .timeZoneCommand) {
            let zone = try c.superDecoder(forKey: .timeZoneCommand)
            try ClosedContractDecodingV1.rejectUnknownKeys(zone, allowed: ["siteID", "timeZoneID", "confirmedAt"])
            timeZoneCommand = try SiteTimeZoneMutationV1(from: zone)
        } else { timeZoneCommand = nil }
        timeZoneMappedDependencyBasis = try c.decodeIfPresent([CheckRunnerDestinationDependencyV1].self, forKey: .timeZoneMappedDependencyBasis)
        timeZoneCommittedAt = try c.decodeIfPresent(Date.self, forKey: .timeZoneCommittedAt)
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(destinationWorkspaceID, forKey: .destinationWorkspaceID)
        try c.encode(recordMutationID, forKey: .recordMutationID)
        try c.encode(recordCommand, forKey: .recordCommand)
        try c.encode(recordMappedDependencyBasis, forKey: .recordMappedDependencyBasis)
        try c.encode(recordCommittedAt, forKey: .recordCommittedAt)
        try c.encodeIfPresent(timeZoneMutationID, forKey: .timeZoneMutationID)
        try c.encodeIfPresent(timeZoneCommand, forKey: .timeZoneCommand)
        try c.encodeIfPresent(timeZoneMappedDependencyBasis, forKey: .timeZoneMappedDependencyBasis)
        try c.encodeIfPresent(timeZoneCommittedAt, forKey: .timeZoneCommittedAt)
    }
}

/// A stable reference to one original Begin receipt. Its postimage fields are
/// immutable provenance, never a substitute for current typed target readback
/// or the allowed successor-lineage validation required during adoption.
struct CheckRunnerBeginReceiptReferenceV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let workspaceID: WorkspaceID
    let mutationID: MutationIDV1
    let receiptIdentity: MutationReceiptIdentityV1
    let envelopeSHA256: String
    let commandBodySHA256: String
    let resultSHA256: String
    let expectedWorkspaceRevision: UInt64
    let resultingWorkspaceRevision: UInt64
    let beginPostimageIdentity: WorkspaceEntityIdentityV1
    let beginPostimageRevision: UInt64
    let beginPostimageSemanticSHA256: String
    let committedAt: Date
    let sourceKind: MutationSourceKindV1

    init(evidence: CheckRunnerBeginCommittedEvidenceV1) throws {
        _ = try CheckRunnerBeginCommittedEvidenceV1(envelope: evidence.envelope, receipt: evidence.receipt)
        guard let image = evidence.receipt.postImages.first else {
            throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
        }
        workspaceID = evidence.envelope.workspaceID
        mutationID = evidence.envelope.mutationID
        receiptIdentity = evidence.receipt.identity
        envelopeSHA256 = evidence.receipt.envelopeSHA256
        commandBodySHA256 = evidence.receipt.commandBodySHA256
        resultSHA256 = evidence.receipt.resultSHA256
        expectedWorkspaceRevision = evidence.receipt.expectedRevision.workspaceRevision
        resultingWorkspaceRevision = evidence.receipt.resultingRevision.workspaceRevision
        beginPostimageIdentity = try image.identity
        beginPostimageRevision = image.revision
        beginPostimageSemanticSHA256 = image.semanticSHA256
        committedAt = evidence.receipt.committedAt
        sourceKind = evidence.receipt.sourceKind
        try validate()
    }

    /// Shape and internal consistency only. The evidence overload binds every
    /// field to the selected exact receipt returned by the authenticated reader.
    func validate() throws {
        try receiptIdentity.validate()
        _ = try MutationIDV1(rawValue: mutationID.rawValue)
        _ = try WorkspaceEntityIdentityV1(kind: beginPostimageIdentity.kind, id: beginPostimageIdentity.id)
        guard workspaceID == receiptIdentity.workspaceID,
              beginPostimageIdentity.kind == .workflowRecord || beginPostimageIdentity.kind == .site,
              beginPostimageRevision > 0,
              expectedWorkspaceRevision < UInt64.max,
              resultingWorkspaceRevision == expectedWorkspaceRevision + 1,
              KernelCanonicalHashV1.validSHA256(envelopeSHA256),
              KernelCanonicalHashV1.validSHA256(commandBodySHA256),
              KernelCanonicalHashV1.validSHA256(resultSHA256),
              KernelCanonicalHashV1.validSHA256(beginPostimageSemanticSHA256),
              committedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
        }
    }

    func validate(evidence: CheckRunnerBeginCommittedEvidenceV1) throws {
        try validate()
        guard self == (try Self(evidence: evidence)) else {
            throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case workspaceID, mutationID, receiptIdentity, envelopeSHA256, commandBodySHA256, resultSHA256
        case expectedWorkspaceRevision, resultingWorkspaceRevision
        case beginPostimageIdentity, beginPostimageRevision, beginPostimageSemanticSHA256, committedAt, sourceKind
    }

    private enum ReceiptKeys: String, CodingKey { case workspaceID, replicaID, localSequence }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let workspace = try c.superDecoder(forKey: .workspaceID)
        try ClosedContractDecodingV1.rejectUnknownKeys(workspace, allowed: ["rawValue"])
        workspaceID = try WorkspaceID(from: workspace)
        mutationID = try c.decode(MutationIDV1.self, forKey: .mutationID)
        let receipt = try c.superDecoder(forKey: .receiptIdentity)
        try ClosedContractDecodingV1.rejectUnknownKeys(receipt, allowed: ["workspaceID", "replicaID", "localSequence"])
        let identity = try receipt.container(keyedBy: ReceiptKeys.self)
        let receiptWorkspace = try identity.superDecoder(forKey: .workspaceID)
        let receiptReplica = try identity.superDecoder(forKey: .replicaID)
        try ClosedContractDecodingV1.rejectUnknownKeys(receiptWorkspace, allowed: ["rawValue"])
        try ClosedContractDecodingV1.rejectUnknownKeys(receiptReplica, allowed: ["rawValue"])
        receiptIdentity = MutationReceiptIdentityV1(
            workspaceID: try WorkspaceID(from: receiptWorkspace),
            replicaID: try ReplicaID(from: receiptReplica),
            localSequence: try identity.decode(UInt64.self, forKey: .localSequence))
        envelopeSHA256 = try c.decode(String.self, forKey: .envelopeSHA256)
        commandBodySHA256 = try c.decode(String.self, forKey: .commandBodySHA256)
        resultSHA256 = try c.decode(String.self, forKey: .resultSHA256)
        expectedWorkspaceRevision = try c.decode(UInt64.self, forKey: .expectedWorkspaceRevision)
        resultingWorkspaceRevision = try c.decode(UInt64.self, forKey: .resultingWorkspaceRevision)
        let target = try c.superDecoder(forKey: .beginPostimageIdentity)
        try ClosedContractDecodingV1.rejectUnknownKeys(target, allowed: ["kind", "id"])
        beginPostimageIdentity = try WorkspaceEntityIdentityV1(from: target)
        beginPostimageRevision = try c.decode(UInt64.self, forKey: .beginPostimageRevision)
        beginPostimageSemanticSHA256 = try c.decode(String.self, forKey: .beginPostimageSemanticSHA256)
        committedAt = try c.decode(Date.self, forKey: .committedAt)
        sourceKind = try c.decode(MutationSourceKindV1.self, forKey: .sourceKind)
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(workspaceID, forKey: .workspaceID)
        try c.encode(mutationID, forKey: .mutationID)
        try c.encode(receiptIdentity, forKey: .receiptIdentity)
        try c.encode(envelopeSHA256, forKey: .envelopeSHA256)
        try c.encode(commandBodySHA256, forKey: .commandBodySHA256)
        try c.encode(resultSHA256, forKey: .resultSHA256)
        try c.encode(expectedWorkspaceRevision, forKey: .expectedWorkspaceRevision)
        try c.encode(resultingWorkspaceRevision, forKey: .resultingWorkspaceRevision)
        try c.encode(beginPostimageIdentity, forKey: .beginPostimageIdentity)
        try c.encode(beginPostimageRevision, forKey: .beginPostimageRevision)
        try c.encode(beginPostimageSemanticSHA256, forKey: .beginPostimageSemanticSHA256)
        try c.encode(committedAt, forKey: .committedAt)
        try c.encode(sourceKind, forKey: .sourceKind)
    }
}
