import Foundation

enum FieldReferenceOrdinaryDeletionDispositionV1:Equatable,Sendable{case preserveBoundHistory(releaseIDs:Set<UUID>,bindingIDs:Set<UUID>);case discardUnboundRelease(releaseID:UUID);case blockedMissingRequiredBytes(releaseID:UUID,contentIDs:[String])}
enum AccessibleDocumentOrdinaryDeletionDispositionV1:Equatable,Sendable{case preserveSealedOutputAndAssessment(receiptIDs:Set<UUID>,outputSHA256:Set<String>);case removeAfterAuthorizedPrivacyExpiry(receiptID:UUID,tombstoneSHA256:String,redactionProofSHA256:String);case blockedMissingRetentionProof(receiptID:UUID)}
enum SurveyDefinitionOrdinaryDeletionDispositionV1:Equatable,Sendable{case preserveImmutableHistory(identityIDs:Set<UUID>,releaseIDs:Set<UUID>)}
enum SurveySessionOrdinaryDeletionDispositionV1:Equatable,Sendable{case preserveMutableHeadsAndImmutableHistory(sessionIDs:Set<UUID>,captureIDs:Set<UUID>,provisionalSubjectIDs:Set<UUID>,promotionReceiptIDs:Set<UUID>,publicationSnapshotIDs:Set<UUID>)}
/// Schedule releases and occurrence history are not asset-owned content. An
/// ordinary asset/site deletion therefore preserves the complete schedule
/// closure; only a workspace Erase removes these rows.
enum ScheduleOrdinaryDeletionDispositionV1: Equatable, Sendable {
    case preserveImmutableReleaseAndOccurrenceHistory(
        releaseIDs: Set<UUID>, occurrenceEventIDs: Set<UUID>
    )
}

enum ScheduleDeletionIntentBoundaryV1 {
    static let ordinaryAssetOrSiteDeletePreservesScheduleHistory = true
    static let workspaceEraseRemovesScheduleRows = true
    static let dueAndReminderProjectionsAreDerived = true
    static let notificationStateIsTruth = false
    static let cloneForkSourceScheduleAutomaticallyActive = false

    static func validate() -> Bool {
        ordinaryAssetOrSiteDeletePreservesScheduleHistory
            && workspaceEraseRemovesScheduleRows
            && dueAndReminderProjectionsAreDerived
            && !notificationStateIsTruth
            && !cloneForkSourceScheduleAutomaticallyActive
    }
}
enum AssetLocatorDeletionIntentBoundaryV1 {
    static let locatorRowsAreAssetOwned = true
    static let bindingReceiptRowsMustBeRemovedWithTheirReferences = true
    static let lifecycleEventsRemainInMutationHistory = true
    static let privateKeyMaterialExported = false

    static func validate() -> Bool {
        locatorRowsAreAssetOwned
            && bindingReceiptRowsMustBeRemovedWithTheirReferences
            && lifecycleEventsRemainInMutationHistory
            && !privateKeyMaterialExported
    }
}

enum DeletionPhaseV1: String, Codable, Equatable, Sendable {
    case prepared
    case databaseCommitted = "database_committed"
}

/// Exact published-output authority captured before an accepted label snapshot
/// row is removed. The canonical binding bytes make committed deletion cleanup
/// retryable after relaunch without reconstructing output ownership from a row
/// that no longer exists.
struct AssetLabelPublishedOutputCleanupV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let snapshotID: UUID
    let snapshotWorkspaceID: UUID
    let snapshotDisposition: AcceptedLabelSnapshotDispositionV1
    let snapshotSHA256: String
    let jobID: UUID
    let planSHA256: String
    let manifestSHA256: String
    let outputSHA256: String
    let planData: Data
    let manifestData: Data
    let bindingData: Data
    let cleanupSHA256: String

    init(snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
        let binding = snapshot.outputReceipt.publicationBinding
        let canonicalPlan = try AssetLabelCanonicalCodecV1.encode(snapshot.plan)
        let canonicalManifest = try AssetLabelCanonicalCodecV1.encode(snapshot.manifest)
        let canonical = try AssetLabelCanonicalCodecV1.encode(binding)
        let basis = Basis(
            schemaVersion: Self.schemaVersion,
            snapshotID: snapshot.snapshotID,
            snapshotWorkspaceID: snapshot.workspaceID.rawValue,
            snapshotDisposition: snapshot.disposition,
            snapshotSHA256: snapshot.snapshotSHA256,
            jobID: binding.jobID.rawValue,
            planSHA256: binding.planSHA256,
            manifestSHA256: binding.manifestSHA256,
            outputSHA256: binding.outputSHA256,
            planData: canonicalPlan,
            manifestData: canonicalManifest,
            bindingData: canonical
        )
        schemaVersion = Self.schemaVersion
        snapshotID = snapshot.snapshotID
        snapshotWorkspaceID = snapshot.workspaceID.rawValue
        snapshotDisposition = snapshot.disposition
        snapshotSHA256 = snapshot.snapshotSHA256
        jobID = binding.jobID.rawValue
        planSHA256 = binding.planSHA256
        manifestSHA256 = binding.manifestSHA256
        outputSHA256 = binding.outputSHA256
        planData = canonicalPlan
        manifestData = canonicalManifest
        bindingData = canonical
        cleanupSHA256 = try AssetLabelCanonicalCodecV1.sha256(basis)
        guard let firstAssetID = snapshot.plan.items.first?.assetID else {
            throw AssetLabelContractFailureV1.invalidValue
        }
        _ = try value(containingAssetID: firstAssetID)
    }

    func value(containingAssetID assetID: UUID) throws -> AssetLabelRenderPublicationBindingV1 {
        let plan = try AssetLabelCanonicalCodecV1.decode(
            AssetLabelGenerationPlanV1.self, from: planData
        )
        let manifest = try AssetLabelCanonicalCodecV1.decode(
            LabelArtifactManifestV1.self, from: manifestData
        )
        let binding = try AssetLabelCanonicalCodecV1.decode(
            AssetLabelRenderPublicationBindingV1.self, from: bindingData
        )
        let basis = Basis(
            schemaVersion: schemaVersion, snapshotID: snapshotID,
            snapshotWorkspaceID: snapshotWorkspaceID,
            snapshotDisposition: snapshotDisposition,
            snapshotSHA256: snapshotSHA256, jobID: jobID,
            planSHA256: planSHA256, manifestSHA256: manifestSHA256,
            outputSHA256: outputSHA256, planData: planData,
            manifestData: manifestData, bindingData: bindingData
        )
        guard schemaVersion == Self.schemaVersion,
              plan.items.contains(where: { $0.assetID == assetID }),
              ((snapshotDisposition == .activeSourceWorkspace
                    && snapshotWorkspaceID == plan.workspaceID.rawValue
                    && binding.workspaceID.rawValue == snapshotWorkspaceID)
                || (snapshotDisposition == .historicCloneOrFork
                    && snapshotWorkspaceID != plan.workspaceID.rawValue
                    && binding.workspaceID == plan.workspaceID)),
              plan.planSHA256 == planSHA256,
              manifest.planSHA256 == planSHA256,
              manifest.manifestSHA256 == manifestSHA256,
              jobID == binding.jobID.rawValue,
              planSHA256 == binding.planSHA256,
              manifestSHA256 == binding.manifestSHA256,
              outputSHA256 == binding.outputSHA256,
              planData == (try AssetLabelCanonicalCodecV1.encode(plan)),
              manifestData == (try AssetLabelCanonicalCodecV1.encode(manifest)),
              bindingData == (try AssetLabelCanonicalCodecV1.encode(binding)),
              KernelCanonicalHashV1.validSHA256(snapshotSHA256),
              cleanupSHA256 == (try AssetLabelCanonicalCodecV1.sha256(basis)) else {
            throw AssetLabelContractFailureV1.invalidReceipt
        }
        return binding
    }

    func requiresPublishedOutputRemoval(containingAssetID assetID: UUID) throws -> Bool {
        let binding = try value(containingAssetID: assetID)
        return snapshotDisposition == .activeSourceWorkspace
            && binding.workspaceID.rawValue == snapshotWorkspaceID
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let snapshotID: UUID
        let snapshotWorkspaceID: UUID
        let snapshotDisposition: AcceptedLabelSnapshotDispositionV1
        let snapshotSHA256: String
        let jobID: UUID
        let planSHA256: String
        let manifestSHA256: String
        let outputSHA256: String
        let planData: Data
        let manifestData: Data
        let bindingData: Data
    }
}

struct DeletionIntentV1: Codable, Equatable, Sendable {
    let acceptedLabelOutputCleanups: [AssetLabelPublishedOutputCleanupV1]
    let assetID: UUID
    let countedPacketTombstones: [PacketPayloadV1]
    let deletionID: UUID
    let generationID: UUID
    let ledgerEntries: [DeletionLedgerEntryV2]
    let phase: DeletionPhaseV1
    let relativePaths: [String]
    let schemaVersion: Int

    init(
        acceptedLabelOutputCleanups: [AssetLabelPublishedOutputCleanupV1] = [],
        assetID: UUID,
        countedPacketTombstones: [PacketPayloadV1],
        deletionID: UUID,
        generationID: UUID,
        ledgerEntries: [DeletionLedgerEntryV2],
        phase: DeletionPhaseV1,
        relativePaths: [String],
        schemaVersion: Int
    ) {
        self.acceptedLabelOutputCleanups = acceptedLabelOutputCleanups
        self.assetID = assetID
        self.countedPacketTombstones = countedPacketTombstones
        self.deletionID = deletionID
        self.generationID = generationID
        self.ledgerEntries = ledgerEntries
        self.phase = phase
        self.relativePaths = relativePaths
        self.schemaVersion = schemaVersion
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case acceptedLabelOutputCleanups, assetID, countedPacketTombstones,
             deletionID, generationID, ledgerEntries, phase, relativePaths,
             schemaVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        acceptedLabelOutputCleanups = try c.decodeIfPresent(
            [AssetLabelPublishedOutputCleanupV1].self,
            forKey: .acceptedLabelOutputCleanups
        ) ?? []
        assetID = try c.decode(UUID.self, forKey: .assetID)
        countedPacketTombstones = try c.decode(
            [PacketPayloadV1].self, forKey: .countedPacketTombstones
        )
        deletionID = try c.decode(UUID.self, forKey: .deletionID)
        generationID = try c.decode(UUID.self, forKey: .generationID)
        ledgerEntries = try c.decodeIfPresent(
            [DeletionLedgerEntryV2].self, forKey: .ledgerEntries
        ) ?? []
        phase = try c.decode(DeletionPhaseV1.self, forKey: .phase)
        relativePaths = try c.decode([String].self, forKey: .relativePaths)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
    }

    func withPhase(_ phase: DeletionPhaseV1) -> DeletionIntentV1 {
        DeletionIntentV1(
            acceptedLabelOutputCleanups: acceptedLabelOutputCleanups,
            assetID: assetID,
            countedPacketTombstones: countedPacketTombstones,
            deletionID: deletionID,
            generationID: generationID,
            ledgerEntries: ledgerEntries,
            phase: phase,
            relativePaths: relativePaths,
            schemaVersion: schemaVersion
        )
    }
}

struct EncodedDeletionIntentV1: Equatable, Sendable {
    let data: Data
    let sha256: String
}

enum DeletionIntentEncodingErrorV1: Error, Equatable {
    case invalidIntent
}

enum DeletionIntentDecodingErrorV1: Error, Equatable {
    case invalidCanonicalIntent
}

struct DeletionIntentEncoderV1 {
    func encode(_ intent: DeletionIntentV1) throws -> EncodedDeletionIntentV1 {
        guard Self.valid(intent) else {
            throw DeletionIntentEncodingErrorV1.invalidIntent
        }
        let tombstones = intent.countedPacketTombstones.map { packet in
            CanonicalJSONValueV1.object([
                "contentDeletedAt": CanonicalJSONV1.optionalDate(packet.contentDeletedAt),
                "createdAt": CanonicalJSONV1.date(packet.createdAt),
                "currentRecordID": CanonicalJSONV1.optionalUUID(packet.currentRecordID),
                "evaluationCounted": .bool(packet.evaluationCounted),
                "id": CanonicalJSONV1.uuid(packet.id),
                "schemaVersion": .integer(packet.schemaVersion),
                "stableRootID": CanonicalJSONV1.uuid(packet.stableRootID),
            ])
        }
        var fields: [String: CanonicalJSONValueV1] = [
            "assetID": CanonicalJSONV1.uuid(intent.assetID),
            "countedPacketTombstones": .array(tombstones),
            "deletionID": CanonicalJSONV1.uuid(intent.deletionID),
            "generationID": CanonicalJSONV1.uuid(intent.generationID),
            "phase": .string(intent.phase.rawValue),
            "relativePaths": .array(intent.relativePaths.map {
                CanonicalJSONValueV1.string($0)
            }),
            "schemaVersion": .integer(intent.schemaVersion),
        ]
        if intent.schemaVersion == 2 {
            fields["ledgerEntries"] = .array(intent.ledgerEntries.map { entry in
                CanonicalJSONValueV1.object([
                    "deletedAt": CanonicalJSONV1.date(entry.deletedAt),
                    "identity": .object([
                        "id": CanonicalJSONV1.uuid(entry.identity.id),
                        "kind": .string(entry.identity.kind.rawValue),
                    ]),
                    "schemaVersion": .integer(entry.schemaVersion),
                ])
            })
        }
        if intent.schemaVersion == 3 {
            fields["ledgerEntries"] = .array(intent.ledgerEntries.map { entry in
                CanonicalJSONValueV1.object([
                    "deletedAt": CanonicalJSONV1.date(entry.deletedAt),
                    "identity": .object([
                        "id": CanonicalJSONV1.uuid(entry.identity.id),
                        "kind": .string(entry.identity.kind.rawValue),
                    ]),
                    "schemaVersion": .integer(entry.schemaVersion),
                ])
            })
            fields["acceptedLabelOutputCleanups"] = .array(
                intent.acceptedLabelOutputCleanups.map { cleanup in
                    .object([
                        "bindingData": .string(cleanup.bindingData.base64EncodedString()),
                        "cleanupSHA256": .string(cleanup.cleanupSHA256),
                        "jobID": CanonicalJSONV1.uuid(cleanup.jobID),
                        "manifestSHA256": .string(cleanup.manifestSHA256),
                        "manifestData": .string(cleanup.manifestData.base64EncodedString()),
                        "outputSHA256": .string(cleanup.outputSHA256),
                        "planData": .string(cleanup.planData.base64EncodedString()),
                        "planSHA256": .string(cleanup.planSHA256),
                        "schemaVersion": .integer(cleanup.schemaVersion),
                        "snapshotID": CanonicalJSONV1.uuid(cleanup.snapshotID),
                        "snapshotDisposition": .string(
                            cleanup.snapshotDisposition.rawValue
                        ),
                        "snapshotSHA256": .string(cleanup.snapshotSHA256),
                        "snapshotWorkspaceID": CanonicalJSONV1.uuid(
                            cleanup.snapshotWorkspaceID
                        ),
                    ])
                }
            )
        }
        let value = CanonicalJSONValueV1.object(fields)
        let data = try CanonicalJSONV1.encode(value)
        return EncodedDeletionIntentV1(
            data: data,
            sha256: CanonicalJSONV1.sha256(data)
        )
    }

    static func valid(_ intent: DeletionIntentV1) -> Bool {
        guard AssetLocatorDeletionIntentBoundaryV1.validate(),
              (1...3).contains(intent.schemaVersion),
              unique(intent.countedPacketTombstones.map(\.id)),
              unique(intent.countedPacketTombstones.map(\.stableRootID)),
              Set(intent.countedPacketTombstones.compactMap(\.contentDeletedAt)).count <= 1,
              intent.countedPacketTombstones == intent.countedPacketTombstones.sorted(by: {
                  canonicalID($0.id) < canonicalID($1.id)
              }),
              unique(intent.relativePaths),
              intent.relativePaths == intent.relativePaths.sorted(),
              intent.relativePaths.allSatisfy(validRelativePath) else {
            return false
        }
        guard intent.countedPacketTombstones.allSatisfy({ packet in
            packet.schemaVersion == 1
                && packet.currentRecordID == nil
                && packet.evaluationCounted
                && packet.contentDeletedAt != nil
                && packet.contentDeletedAt.map({ $0 >= packet.createdAt }) == true
        }) else { return false }
        if intent.schemaVersion == 1 {
            return intent.ledgerEntries.isEmpty
                && intent.acceptedLabelOutputCleanups.isEmpty
        }
        let baseValid = (try? DeletionLedgerV2(entries: intent.ledgerEntries)) != nil
            && intent.ledgerEntries.map(\.identity)
                == intent.ledgerEntries.map(\.identity).sorted()
            && intent.ledgerEntries.allSatisfy({
                Optional($0.deletedAt) == deletionTimestamp(intent)
            })
            && intent.ledgerEntries.filter({ $0.identity.kind == .asset }).map({
                $0.identity.id
            }) == [intent.assetID]
            && !intent.ledgerEntries.contains(where: { $0.identity.kind == .site })
            && Set(intent.countedPacketTombstones.map(\.id)).isSubset(of:
                Set(intent.ledgerEntries.compactMap { entry in
                    entry.identity.kind == .packet ? entry.identity.id : nil
                })
            )
        guard baseValid else { return false }
        if intent.schemaVersion == 2 {
            return intent.acceptedLabelOutputCleanups.isEmpty
        }
        let cleanups = intent.acceptedLabelOutputCleanups
        let cleanupSnapshotIDs = cleanups.map(\.snapshotID)
        let cleanupGroups = Dictionary(grouping: cleanups, by: \.jobID)
        let ledgerSnapshotIDs = intent.ledgerEntries.compactMap { entry in
            entry.identity.kind == .acceptedLabelGenerationSnapshot
                ? entry.identity.id : nil
        }
        return !cleanups.isEmpty
            && cleanups.count <= 100_000
            && cleanupSnapshotIDs == cleanupSnapshotIDs.sorted {
                $0.uuidString < $1.uuidString
            }
            && Set(cleanupSnapshotIDs).count == cleanupSnapshotIDs.count
            && cleanupSnapshotIDs == ledgerSnapshotIDs.sorted {
                $0.uuidString < $1.uuidString
            }
            && cleanupGroups.values.allSatisfy {
                Set($0.map(\.bindingData)).count == 1
            }
            && cleanups.allSatisfy {
                (try? $0.value(containingAssetID: intent.assetID)) != nil
            }
    }

    private static func deletionTimestamp(_ intent: DeletionIntentV1) -> Date? {
        let dates = Set(intent.countedPacketTombstones.compactMap(\.contentDeletedAt))
        if let date = dates.first { return date }
        let ledgerDates = Set(intent.ledgerEntries.map(\.deletedAt))
        return ledgerDates.count == 1 ? ledgerDates.first : nil
    }

    static func validRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.hasPrefix("/"),
              !value.hasSuffix("/"),
              !value.contains("\\"),
              !value.contains(":") else {
            return false
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if components.count == 3,
           components[0] == "evidence",
           components[2] == "original.jpg" || components[2] == "thumbnail.jpg" {
            return canonicalUUID(components[1])
        }
        if components.count == 2, components[0] == "snapshots" {
            return canonicalUUIDFilename(components[1], pathExtension: "json")
        }
        if components.count == 2, components[0] == "pdfs" {
            return canonicalUUIDFilename(components[1], pathExtension: "pdf")
        }
        return false
    }

    private static func canonicalUUIDFilename(_ filename: String, pathExtension: String) -> Bool {
        let suffix = ".\(pathExtension)"
        guard filename.hasSuffix(suffix) else { return false }
        return canonicalUUID(String(filename.dropLast(suffix.count)))
    }

    private static func canonicalUUID(_ value: String) -> Bool {
        guard let identifier = UUID(uuidString: value) else { return false }
        return identifier.uuidString.lowercased() == value
    }

    private static func unique<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count == values.count
    }

    private static func canonicalID(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }
}

struct DeletionIntentDecoderV1 {
    func decode(_ data: Data) throws -> DeletionIntentV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard Self.isCanonicalTimestamp(string),
                  let date = Self.timestampFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected canonical RFC3339 UTC milliseconds"
                )
            }
            return date
        }
        do {
            let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
            let intent: DeletionIntentV1
            if version == 1 {
                let legacy = try decoder.decode(LegacyIntent.self, from: data)
                intent = DeletionIntentV1(
                    assetID: legacy.assetID,
                    countedPacketTombstones: legacy.countedPacketTombstones,
                    deletionID: legacy.deletionID,
                    generationID: legacy.generationID,
                    ledgerEntries: [],
                    phase: legacy.phase,
                    relativePaths: legacy.relativePaths,
                    schemaVersion: legacy.schemaVersion
                )
            } else {
                intent = try decoder.decode(DeletionIntentV1.self, from: data)
            }
            let canonical = try DeletionIntentEncoderV1().encode(intent).data
            guard canonical == data else {
                throw DeletionIntentDecodingErrorV1.invalidCanonicalIntent
            }
            return intent
        } catch {
            throw DeletionIntentDecodingErrorV1.invalidCanonicalIntent
        }
    }

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    private struct LegacyIntent: Decodable {
        let assetID: UUID
        let countedPacketTombstones: [PacketPayloadV1]
        let deletionID: UUID
        let generationID: UUID
        let phase: DeletionPhaseV1
        let relativePaths: [String]
        let schemaVersion: Int
    }

    private static func isCanonicalTimestamp(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 24 else { return false }
        let punctuation: [Int: UInt8] = [
            4: 0x2d, 7: 0x2d, 10: 0x54, 13: 0x3a,
            16: 0x3a, 19: 0x2e, 23: 0x5a,
        ]
        for (index, byte) in bytes.enumerated() {
            if let expected = punctuation[index] {
                guard byte == expected else { return false }
            } else if !(0x30...0x39).contains(byte) {
                return false
            }
        }
        return true
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Workflow_DeletionIntentV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Workflow_DeletionIntentV1_swift {
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

enum C30EvidenceContextDeletionIntentPolicyV1 {
    static let ordinaryAssetDeletionPreservesContextHistory = true
    static let ordinarySiteDeletionPreservesPairingHistory = true
    static let workspaceEraseOwnsContextRemoval = true
    static let deletionInfersCompliance = false

    static func validate(context: EvidenceContextV1,
                         pairedLink: PairedObservationLinkV1? = nil) throws {
        try context.validateIntrinsic()
        if let pairedLink {
            try pairedLink.validateIntrinsic()
            guard pairedLink.workspaceID == context.workspaceID else {
                throw EvidenceContextFailureV1.wrongWorkspace
            }
        }
        guard ordinaryAssetDeletionPreservesContextHistory,
              ordinarySiteDeletionPreservesPairingHistory,
              workspaceEraseOwnsContextRemoval, !deletionInfersCompliance else {
            throw EvidenceContextFailureV1.invalidValue
        }
    }
}

enum C31LightingDeletionIntentBoundaryV1 {
    static let ordinaryDeletionPreservesImmutableLightingHistory = true
    static let deletionDoesNotPromoteDerivedClaims = true
    static let projectionAndDiagnosticsAreRebuilt = true

    static func validate(
        records: [V31BackupLightingRecordV1],
        workspaceID: WorkspaceID
    ) throws {
        let roots = try LightingBackupRecordSetV1.decode(records)
        let workspaces = roots.systems.map(\.workspaceID)
            + roots.observations.map(\.workspaceID)
            + roots.issues.map(\.workspaceID)
            + roots.plans.map(\.workspaceID)
            + roots.claims.map(\.workspaceID)
        guard workspaces.allSatisfy({ $0 == workspaceID }),
              ordinaryDeletionPreservesImmutableLightingHistory,
              deletionDoesNotPromoteDerivedClaims,
              projectionAndDiagnosticsAreRebuilt else {
            throw LightingContractFailureV1.wrongWorkspace
        }
    }
}
// MARK: - C32 assistance deletion intent boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Workflow_DeletionIntentV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let terminalProposalRemovalPrecedesScratchDelete = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}


// MARK: - C33 temporal evidence deletion intent

enum TemporalEvidenceDeletionIntentBoundaryV1 {
    static let deleteIncludesAnchors = true
    static let deleteIncludesRegenerableDerivatives = true
    static let originalRemovedOnlyThroughCanonicalContentAuthority = true

    static func validate(_ event: TemporalEvidenceRetentionEventV1,
                         clip: TemporalEvidenceClipV1) throws {
        try event.validate(clip: clip)
        guard event.disposition == .deleteClip,
              deleteIncludesAnchors, deleteIncludesRegenerableDerivatives,
              originalRemovedOnlyThroughCanonicalContentAuthority else {
            throw TemporalEvidenceContractFailureV1.invalidTransition
        }
    }
}

enum C45AcceptedLabelDeletionIntentBoundaryV1 { static let ordinaryAssetDeletionRemovesWholeMatchingBatch=true;static let outputCleanupIsReceiptBoundAndRetryable=true }

enum C46OperationalContactBoundary_38{static let assetOrSiteCascadeDeletesPartyContacts=false;static let workspaceEraseOwnsRows=true}
