import Foundation

enum CheckRunnerRequestedEntryV1: Codable, Equatable, Sendable {
    case check
    case recheck(issueID: UUID)

    var stage: WorkflowStage {
        switch self { case .check: .check; case .recheck: .recheck }
    }

    var issueID: UUID? {
        switch self { case .check: nil; case let .recheck(id): id }
    }

    func validate() throws {
        if let issueID { _ = try MutationIDV1(rawValue: issueID) }
    }

    private enum CodingKeys: String, CodingKey { case tag, issueID }
    private enum Tag: String, Codable { case check = "CHECK", recheck = "RECHECK" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(Tag.self, forKey: .tag)
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: tag == .check ? ["tag"] : ["tag", "issueID"]
        )
        switch tag {
        case .check: self = .check
        case .recheck: self = .recheck(issueID: try c.decode(UUID.self, forKey: .issueID))
        }
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .check: try c.encode(Tag.check, forKey: .tag)
        case let .recheck(id):
            try c.encode(Tag.recheck, forKey: .tag)
            try c.encode(id, forKey: .issueID)
        }
    }
}

/// Immutable identity from an authenticated ENTRY read. Decoding proves shape;
/// publication additionally requires the original owner, a fresh read and access.
struct CheckRunnerRoundItemSourceV1: Codable, Equatable, Sendable {
    let sourceCheckpoint: RepetitiveCaptureSourceCheckpointReferenceV1
    let entryProgressCheckpoint: RepetitiveCaptureSourceCheckpointReferenceV1
    let roundAtEntry: RoundSessionReferenceV1
    let originalItem: RoundItemV1
    let itemAtEntry: RoundItemV1
    let assetID: UUID
    let packageRelease: RoundPackageReleaseReferenceV1
    let legacyPackageIdentity: PackageReleaseIdentityV1
    let requestedEntry: CheckRunnerRequestedEntryV1

    init(read: ProductionRepetitiveCaptureReadV2, itemID: UUID,
         publishedRelease: InspectionPackageReleaseV1, signPack: SignPack,
         requestedEntry: CheckRunnerRequestedEntryV1) throws {
        let chain = read.chain
        try chain.launch.validate()
        try chain.currentRound.validateIntrinsic()
        try requestedEntry.validate()
        guard let entry = chain.nodes.last,
              entry.step.action == .enter, entry.step.itemID == itemID,
              entry.step.navigationItemID == itemID, !entry.isPendingRoundEffect,
              chain.nodes.filter({ $0.checkpoint.draftID == entry.checkpoint.draftID }).count == 1,
              chain.sourceCheckpoint.workspaceID == chain.currentRound.workspaceID,
              chain.launch.round.workspaceID == chain.currentRound.workspaceID,
              chain.launch.round.sessionID == chain.currentRound.sessionID,
              chain.currentRound.state == .active,
              let original = chain.launch.round.items.first(where: { $0.itemID == itemID }),
              let current = chain.currentRound.items.first(where: { $0.itemID == itemID }),
              try FieldDraftCanonicalCodecV1.encode(entry.step.resultingRound)
                == FieldDraftCanonicalCodecV1.encode(chain.currentRound) else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        try entry.step.source.validate(source: chain.sourceCheckpoint)
        let reference = try RoundPackageReleaseReferenceV1(publishedRelease)
        let binding = try ShippingIlluminatedSignAdapterV1.finalizationInspectionRelease(
            from: signPack, stage: requestedEntry.stage
        )
        guard reference.packageReleaseID == binding.packageReleaseID,
              reference.packageID == binding.packageID,
              reference.packageContentVersion == binding.packageContentVersion,
              reference.packageSHA256 == binding.packageSHA256,
              reference.workflowSHA256 == binding.workflowSHA256 else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        sourceCheckpoint = try .init(source: chain.sourceCheckpoint)
        entryProgressCheckpoint = try .init(source: entry.checkpoint)
        roundAtEntry = try chain.currentRound.reference
        originalItem = original
        itemAtEntry = current
        assetID = current.selection.assetID
        packageRelease = reference
        legacyPackageIdentity = try .init(package: signPack)
        self.requestedEntry = requestedEntry
        try validate()
    }

    func validate() throws {
        try sourceCheckpoint.validate()
        try entryProgressCheckpoint.validate()
        try roundAtEntry.validate()
        try originalItem.validate(workspaceID: roundAtEntry.workspaceID)
        try itemAtEntry.validate(workspaceID: roundAtEntry.workspaceID)
        try packageRelease.validate()
        try requestedEntry.validate()
        guard sourceCheckpoint.draftID != entryProgressCheckpoint.draftID,
              sourceCheckpoint.mutationID != entryProgressCheckpoint.mutationID,
              originalItem.itemID == itemAtEntry.itemID,
              originalItem.order == itemAtEntry.order,
              originalItem.selection == itemAtEntry.selection,
              originalItem.requirement == itemAtEntry.requirement,
              !originalItem.disposition.isTerminal,
              itemAtEntry.disposition == .visited,
              itemAtEntry.selection.assetID == assetID,
              originalItem.requirement.packageRelease == packageRelease,
              legacyPackageIdentity.packageID == ShippingIlluminatedSignAdapterV1.packageID,
              legacyPackageIdentity.schemaVersion == 1,
              legacyPackageIdentity.packageID == packageRelease.packageID,
              legacyPackageIdentity.contentVersion == packageRelease.packageContentVersion else {
            throw FieldDraftFailureV1.invalidValue
        }
    }

    func validate(read: ProductionRepetitiveCaptureReadV2,
                  publishedRelease: InspectionPackageReleaseV1, signPack: SignPack) throws {
        try validate()
        let current = try Self(read: read, itemID: originalItem.itemID,
            publishedRelease: publishedRelease, signPack: signPack, requestedEntry: requestedEntry)
        guard try FieldDraftCanonicalCodecV1.encode(self)
            == FieldDraftCanonicalCodecV1.encode(current) else { throw ScanToWorkFailureV1.stale }
    }

    /// Historical correspondence only. The progress owner must authenticate a
    /// fresh complete read before publication or any separately authorized effect.
    /// The live ENTRY initializer above deliberately retains its stricter frontier.
    func validateHistoricalEntry(read: ProductionRepetitiveCaptureReadV2,
        publishedRelease: InspectionPackageReleaseV1, signPack: SignPack) throws {
        try validate()
        let chain = read.chain
        try chain.launch.validate()
        try chain.currentRound.validateIntrinsic()
        try sourceCheckpoint.validate(source: chain.sourceCheckpoint)
        let matches = chain.nodes.filter { $0.checkpoint.draftID == entryProgressCheckpoint.draftID }
        guard matches.count == 1, let entry = matches.first,
              entry.step.action == .enter, entry.step.itemID == originalItem.itemID,
              entry.step.navigationItemID == originalItem.itemID,
              !entry.isPendingRoundEffect else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        try entryProgressCheckpoint.validate(source: entry.checkpoint)
        try entry.step.source.validate(source: chain.sourceCheckpoint)
        let round = entry.step.resultingRound
        try round.validateIntrinsic()
        guard round.state == .active,
              round.workspaceID == chain.sourceCheckpoint.workspaceID,
              round.workspaceID == chain.launch.round.workspaceID,
              round.workspaceID == chain.currentRound.workspaceID,
              round.sessionID == chain.launch.round.sessionID,
              round.sessionID == chain.currentRound.sessionID,
              try round.reference == roundAtEntry,
              let original = chain.launch.round.items.first(where: { $0.itemID == originalItem.itemID }),
              let entered = round.items.first(where: { $0.itemID == originalItem.itemID }),
              original == originalItem, entered == itemAtEntry else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let reference = try RoundPackageReleaseReferenceV1(publishedRelease)
        let binding = try ShippingIlluminatedSignAdapterV1.finalizationInspectionRelease(
            from: signPack, stage: requestedEntry.stage)
        guard reference == packageRelease,
              legacyPackageIdentity == (try PackageReleaseIdentityV1(package: signPack)),
              reference.packageReleaseID == binding.packageReleaseID,
              reference.packageID == binding.packageID,
              reference.packageContentVersion == binding.packageContentVersion,
              reference.packageSHA256 == binding.packageSHA256,
              reference.workflowSHA256 == binding.workflowSHA256 else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let left = try? FieldDraftCanonicalCodecV1.encode(lhs),
              let right = try? FieldDraftCanonicalCodecV1.encode(rhs) else { return false }
        return left == right
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceCheckpoint, entryProgressCheckpoint, roundAtEntry, originalItem, itemAtEntry
        case assetID, packageRelease, legacyPackageIdentity, requestedEntry
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceCheckpoint = try c.decode(RepetitiveCaptureSourceCheckpointReferenceV1.self, forKey: .sourceCheckpoint)
        entryProgressCheckpoint = try c.decode(RepetitiveCaptureSourceCheckpointReferenceV1.self, forKey: .entryProgressCheckpoint)
        roundAtEntry = try c.decode(RoundSessionReferenceV1.self, forKey: .roundAtEntry)
        originalItem = try c.decode(RoundItemV1.self, forKey: .originalItem)
        itemAtEntry = try c.decode(RoundItemV1.self, forKey: .itemAtEntry)
        assetID = try c.decode(UUID.self, forKey: .assetID)
        packageRelease = try c.decode(RoundPackageReleaseReferenceV1.self, forKey: .packageRelease)
        let legacy = try c.superDecoder(forKey: .legacyPackageIdentity)
        try ClosedContractDecodingV1.rejectUnknownKeys(
            legacy, allowed: ["packageID", "schemaVersion", "contentVersion"]
        )
        legacyPackageIdentity = try PackageReleaseIdentityV1(from: legacy)
        requestedEntry = try c.decode(CheckRunnerRequestedEntryV1.self, forKey: .requestedEntry)
        try validate()
    }
}

struct CheckRunnerBeginTimeZoneAttemptV1: Codable, Equatable, Sendable {
    let command: SiteTimeZoneMutationV1
    let mutationID: MutationIDV1
    let expectedSiteRevision: UInt64
    let committedAt: Date

    init(command: SiteTimeZoneMutationV1, mutationID: MutationIDV1,
         expectedSiteRevision: UInt64, committedAt: Date) throws {
        self.command = command
        self.mutationID = mutationID
        self.expectedSiteRevision = expectedSiteRevision
        self.committedAt = committedAt
        try validate()
    }

    func validate() throws {
        _ = try WorkspaceEntityIdentityV1(kind: .site, id: command.siteID)
        _ = try MutationIDV1(rawValue: mutationID.rawValue)
        guard TimeZone.knownTimeZoneIdentifiers.contains(command.timeZoneID),
              TimeZone(identifier: command.timeZoneID) != nil,
              command.confirmedAt.timeIntervalSince1970.isFinite,
              committedAt.timeIntervalSince1970.isFinite,
              committedAt.timeIntervalSince1970 >= 0,
              expectedSiteRevision < UInt64.max else { throw FieldDraftFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case command, mutationID, expectedSiteRevision, committedAt
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let commandDecoder = try c.superDecoder(forKey: .command)
        try ClosedContractDecodingV1.rejectUnknownKeys(
            commandDecoder, allowed: ["siteID", "timeZoneID", "confirmedAt"]
        )
        try self.init(command: SiteTimeZoneMutationV1(from: commandDecoder),
            mutationID: c.decode(MutationIDV1.self, forKey: .mutationID),
            expectedSiteRevision: c.decode(UInt64.self, forKey: .expectedSiteRevision),
            committedAt: c.decode(Date.self, forKey: .committedAt))
    }
}

/// Original source inputs only. This value carries no receipt, destination
/// authorization, writer lease, or permission to persist/execute a Begin.
struct CheckRunnerFrozenBeginAttemptV1: Codable, Equatable, Sendable {
    let source: CheckRunnerRoundItemSourceV1
    let sourceWorkspaceID: WorkspaceID
    let recordCommand: CheckDraftMutationV1
    let recordMutationID: MutationIDV1
    let recordExpectedEntityRevisions: [WorkspaceEntityRevisionV1]
    let recordCommittedAt: Date
    let timeZone: CheckRunnerBeginTimeZoneAttemptV1?
    let siteID: UUID
    let resolvedSiteTimeZoneID: String

    init(source: CheckRunnerRoundItemSourceV1, sourceWorkspaceID: WorkspaceID,
         recordCommand: CheckDraftMutationV1, recordMutationID: MutationIDV1,
         recordExpectedEntityRevisions: [WorkspaceEntityRevisionV1], recordCommittedAt: Date,
         timeZone: CheckRunnerBeginTimeZoneAttemptV1?, siteID: UUID,
         resolvedSiteTimeZoneID: String) throws {
        self.source = source
        self.sourceWorkspaceID = sourceWorkspaceID
        self.recordCommand = recordCommand
        self.recordMutationID = recordMutationID
        self.recordExpectedEntityRevisions = recordExpectedEntityRevisions
        self.recordCommittedAt = recordCommittedAt
        self.timeZone = timeZone
        self.siteID = siteID
        self.resolvedSiteTimeZoneID = resolvedSiteTimeZoneID
        try validate()
    }

    func validate() throws {
        try source.validate()
        try timeZone?.validate()
        _ = try MutationIDV1(rawValue: recordMutationID.rawValue)
        let command = recordCommand
        let recordIdentity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: command.recordID)
        var required = try [recordIdentity, WorkspaceEntityIdentityV1(kind: .asset, id: command.assetID)]
        if let issueID = command.issueID {
            required.append(try WorkspaceEntityIdentityV1(kind: .issue, id: issueID))
        }
        if let parentID = command.parentRecordID {
            required.append(try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: parentID))
        }
        required.sort { $0.stableKey < $1.stableKey }
        let identities = recordExpectedEntityRevisions.map(\.identity)
        guard sourceWorkspaceID == source.roundAtEntry.workspaceID,
              command.assetID == source.assetID,
              siteID == source.originalItem.selection.siteID,
              recordMutationID.rawValue == command.recordID,
              command.stage == source.requestedEntry.stage.rawValue,
              command.issueID == source.requestedEntry.issueID,
              (command.parentRecordID == nil) == (source.requestedEntry == .check),
              command.draftStepKey == WorkflowDraftStep.wide.rawValue,
              command.packID == source.legacyPackageIdentity.packageID,
              command.packSchemaVersion == source.legacyPackageIdentity.schemaVersion,
              command.packContentVersion == source.legacyPackageIdentity.contentVersion,
              command.startedAt.timeIntervalSince1970.isFinite,
              command.observedAtUTC == command.startedAt,
              command.timeZoneID == resolvedSiteTimeZoneID,
              TimeZone.knownTimeZoneIdentifiers.contains(resolvedSiteTimeZoneID),
              TimeZone(identifier: resolvedSiteTimeZoneID) != nil,
              command.utcOffsetMinutes != nil, command.localDate?.isEmpty == false,
              command.localTime?.isEmpty == false,
              command.afterDarkAcknowledgementAccepted == true,
              command.safePositionAcknowledgementAccepted == true,
              command.afterDarkAcknowledgementKey?.isEmpty == false,
              command.afterDarkAcknowledgementCopy?.isEmpty == false,
              command.afterDarkAcknowledgementVersion?.isEmpty == false,
              command.safePositionAcknowledgementKey?.isEmpty == false,
              command.safePositionAcknowledgementCopy?.isEmpty == false,
              command.safePositionAcknowledgementVersion?.isEmpty == false,
              !command.pdfTemplateID.isEmpty, command.pdfTemplateVersion > 0,
              (command.observationBasis == nil) == (command.temporalContext == nil),
              recordCommittedAt.timeIntervalSince1970.isFinite,
              recordCommittedAt.timeIntervalSince1970 >= 0,
              Set(required).count == required.count, identities == required,
              recordExpectedEntityRevisions.first(where: { $0.identity == recordIdentity })?.revision == 0,
              recordExpectedEntityRevisions.allSatisfy({ $0.revision < UInt64.max }) else {
            throw FieldDraftFailureV1.invalidValue
        }
        if let timeZone {
            guard timeZone.mutationID != recordMutationID,
                  timeZone.command.siteID == siteID,
                  timeZone.command.timeZoneID == resolvedSiteTimeZoneID,
                  timeZone.command.confirmedAt == command.observedAtUTC else {
                throw FieldDraftFailureV1.invalidValue
            }
        }
        try Self.validateTemporalShape(command)
        // Preserve canonical field bytes; recovery must never refreeze civil time.
        _ = try FieldDraftCanonicalCodecV1.encode(command)
    }

    private static func validateTemporalShape(_ command: CheckDraftMutationV1) throws {
        guard let projected = try ObservationAndTimeLegacyMigrationV1.temporalContext(
            observedAtUTC: command.observedAtUTC, recordedAtUTC: command.startedAt,
            timeZoneID: command.timeZoneID, utcOffsetMinutes: command.utcOffsetMinutes,
            localDate: command.localDate, localTime: command.localTime
        ) else { throw FieldDraftFailureV1.invalidValue }
        if let basis = command.observationBasis, let temporal = command.temporalContext {
            _ = try ObservationAndTimeCodecV1.encode(basis)
            _ = try ObservationAndTimeCodecV1.encode(temporal)
            guard temporal.occurredAtUTC == projected.occurredAtUTC,
                  temporal.localDate == projected.localDate,
                  temporal.localTime == projected.localTime,
                  temporal.ianaTimeZoneIdentifier == projected.ianaTimeZoneIdentifier,
                  temporal.utcOffsetSeconds == projected.utcOffsetSeconds else {
                throw FieldDraftFailureV1.invalidValue
            }
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let left = try? FieldDraftCanonicalCodecV1.encode(lhs),
              let right = try? FieldDraftCanonicalCodecV1.encode(rhs) else { return false }
        return left == right
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case source, sourceWorkspaceID, recordCommand, recordMutationID
        case recordExpectedEntityRevisions, recordCommittedAt, timeZone, siteID, resolvedSiteTimeZoneID
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let commandDecoder = try c.superDecoder(forKey: .recordCommand)
        try ClosedContractDecodingV1.rejectUnknownKeys(commandDecoder, allowed: [
            "recordID", "assetID", "issueID", "parentRecordID", "stage", "draftStepKey",
            "startedAt", "observedAtUTC", "timeZoneID", "utcOffsetMinutes", "localDate", "localTime",
            "afterDarkAcknowledgementKey", "afterDarkAcknowledgementCopy", "afterDarkAcknowledgementVersion",
            "afterDarkAcknowledgementAccepted", "safePositionAcknowledgementKey",
            "safePositionAcknowledgementCopy", "safePositionAcknowledgementVersion",
            "safePositionAcknowledgementAccepted", "packID", "packSchemaVersion", "packContentVersion",
            "pdfTemplateID", "pdfTemplateVersion", "observationBasis", "temporalContext"
        ])
        var revisionsDecoder = try c.nestedUnkeyedContainer(forKey: .recordExpectedEntityRevisions)
        var revisions: [WorkspaceEntityRevisionV1] = []
        while !revisionsDecoder.isAtEnd {
            guard revisions.count < 4 else { throw FieldDraftFailureV1.invalidValue }
            let row = try revisionsDecoder.superDecoder()
            try ClosedContractDecodingV1.rejectUnknownKeys(row, allowed: ["identity", "revision"])
            let fields = try row.container(keyedBy: RevisionKeys.self)
            let identity = try fields.superDecoder(forKey: .identity)
            try ClosedContractDecodingV1.rejectUnknownKeys(identity, allowed: ["kind", "id"])
            revisions.append(WorkspaceEntityRevisionV1(
                identity: try WorkspaceEntityIdentityV1(from: identity),
                revision: try fields.decode(UInt64.self, forKey: .revision)))
        }
        try self.init(source: c.decode(CheckRunnerRoundItemSourceV1.self, forKey: .source),
            sourceWorkspaceID: c.decode(WorkspaceID.self, forKey: .sourceWorkspaceID),
            recordCommand: CheckDraftMutationV1(from: commandDecoder),
            recordMutationID: c.decode(MutationIDV1.self, forKey: .recordMutationID),
            recordExpectedEntityRevisions: revisions,
            recordCommittedAt: c.decode(Date.self, forKey: .recordCommittedAt),
            timeZone: c.decodeIfPresent(CheckRunnerBeginTimeZoneAttemptV1.self, forKey: .timeZone),
            siteID: c.decode(UUID.self, forKey: .siteID),
            resolvedSiteTimeZoneID: c.decode(String.self, forKey: .resolvedSiteTimeZoneID))
    }

    private enum RevisionKeys: String, CodingKey { case identity, revision }
}
