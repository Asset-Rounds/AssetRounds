import CoreFoundation
import Foundation

enum C34SceneNavigationBackupEncoderBoundaryV1 {
    static func validate() throws {
        guard C34SceneNavigationDeviceLifecycleBoundaryV1.validate() else {
            throw SceneNavigationFailureV1.invalidSnapshot
        }
    }
}

enum C50IncumbentFileExchangeBackupEncoderBoundaryV1 {
    static let encodesProfileSelectionOrSession = false
    static let encodesSourceScratchOrQuarantine = false
    static let encodesSecurityScopedBookmark = false
    static let preservesExistingCanonicalFamilies = true
}

struct EncodedBackupJSONV1: Equatable, Sendable {
    let data: Data
    let sha256: String
}

enum BackupCanonicalEncodingErrorV1: Error, Equatable {
    case invalidRecords
    case invalidManifest
}

struct BackupCanonicalEncoderV1: Sendable {
    func encodeRecordsOffMain(
        _ records: V4BackupRecordsV1,
        context: ResumableLocalJobExecutionContextV1? = nil
    ) async throws -> EncodedBackupJSONV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let value = try await BackupOffMainWorkV1.run {
            try Self().encodeRecords(records)
        }
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        return value
    }

    func encodeManifestOffMain(
        _ manifest: V4BackupManifestV1,
        context: ResumableLocalJobExecutionContextV1? = nil
    ) async throws -> EncodedBackupJSONV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let value = try await BackupOffMainWorkV1.run {
            try Self().encodeManifest(manifest)
        }
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        return value
    }

    func encodeRecords(_ records: V4BackupRecordsV1) throws -> EncodedBackupJSONV1 {
        try C34SceneNavigationBackupEncoderBoundaryV1.validate()
        guard Self.valid(records) else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        let result = try encoded(.object(Self.recordFields(records)))
        try V30P01C05BackupEncoderCanonicalIdentityBoundaryV1.validateEncodedBytes(
            result.data,
            declaredSHA256: result.sha256
        )
        return result
    }

    /// Canonical business-state projection used by replication checkpoints and
    /// other read/export representations. Shipping backup transport continues
    /// to require its mutation history.
    func encodeSemanticRecords(
        _ records: V4BackupRecordsV1
    ) throws -> EncodedBackupJSONV1 {
        guard Self.validSemantic(records) else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        let result = try encoded(.object(Self.recordFields(records)))
        try V30P01C05BackupEncoderCanonicalIdentityBoundaryV1.validateEncodedBytes(
            result.data,
            declaredSHA256: result.sha256
        )
        return result
    }

    /// C13 package restore reuses the shipping encoder's one canonical field
    /// construction. Every non-C13 top-level records section is classified
    /// exactly once; a newly added or duplicated section fails closed here.
    func entityIdentityResolutionInventoryAtoms(
        _ records: V4BackupRecordsV1
    ) throws -> [EntityConsolidationInventoryFamilyV1: [EntityConsolidationInventoryAtomV1]] {
        var fields = try Self.recordFields(records)
        guard fields.removeValue(forKey: "entityIdentityResolution") != nil else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        if let history = records.mutationHistory {
            fields["mutationHistory"] = try Self.mutationHistory(
                Self.nonEntityIdentityResolutionHistory(history)
            )
        }
        let registry = try Self.entityIdentityResolutionSectionRegistry()
        guard Set(fields.keys).isSubset(of: Set(registry.keys)) else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        var result = Dictionary(
            uniqueKeysWithValues: EntityConsolidationInventoryFamilyV1.allCases.map { ($0, [EntityConsolidationInventoryAtomV1]()) }
        )
        for key in fields.keys.sorted() {
            guard let family = registry[key], let value = fields[key] else {
                throw BackupCanonicalEncodingErrorV1.invalidRecords
            }
            let bytes = try CanonicalJSONV1.encode(value)
            result[family, default: []].append(try EntityConsolidationInventoryAtomV1(
                kind: "V4_BACKUP_RECORD_SECTION",
                itemID: key,
                revision: UInt64(records.recordsSchemaVersion),
                itemSHA256: CanonicalJSONV1.sha256(bytes),
                associationRole: "WORKSPACE_CLOSURE_FOR_EXACT_PAIR"
            ))
        }
        return result
    }

    static let entityIdentityResolutionRegisteredSectionCount = 71

    private static func entityIdentityResolutionSectionRegistry() throws
        -> [String: EntityConsolidationInventoryFamilyV1] {
        let groups: [(EntityConsolidationInventoryFamilyV1, [String])] = [
            (.relationship, [
                "assetCompositionEdges", "assetCompositionEvents", "assetLocators",
                "assetPlacementEvents", "functionalRelationships", "locationHierarchyEvents",
                "locationMigrationReceipts", "locationNodes", "pairedObservationLinks",
            ]),
            (.evidence, [
                "authorityCriterion", "evidenceAssociationEvents", "evidenceAssurance",
                "evidenceContexts", "evidenceFiles", "evidenceSequenceRevisions",
                "inspectionReview", "lighting", "measurementIntegrity", "privacyTransforms",
                "requirementAssurance", "temporalEvidence",
            ]),
            (.content, [
                "assets", "assetSemantics", "issues", "packets", "reports", "sites",
                "workflowRecords", "fieldDrafts", "workPackets", "partsStockSnapshot",
            ]),
            (.tombstone, ["deletionLedger"]),
            (.mutationReceipt, [
                "assistanceAcceptanceReceipts", "bulkCommitReceipts", "mutationHistory",
                "myDayCarryoverReceipts", "recoverabilityReceipts",
                "serviceReliabilityReceipts",
            ]),
            (.history, [
                "acceptedLabelGenerationSnapshots", "accessibleDocumentAssessments",
                "activityContracts", "bulkSessions", "clientCapabilities", "fieldReferences",
                "guidedSurveys", "importMappingProfiles", "myDayPlans",
                "nonactivePlanReferences", "operationalContacts", "packageEvolution",
                "partyAccountability", "placementPoses", "plans", "qualifiedServiceExposures",
                "recordsSchemaVersion", "reinspectionExceptionQueue", "roundSessions",
                "savedSmartViews", "schedules", "serviceCauseAssertions",
                "serviceImpactSegments", "serviceReliabilityIncidents",
                "serviceRemedyAssertions", "serviceRepairIntervals",
                "serviceRequestDispositionEvents", "serviceRequests",
                "serviceRequestWorkLinkEvents", "serviceRestorationAssertions",
                "shopReportProfiles", "surveyDefinitions", "workResources",
            ]),
        ]
        var registry: [String: EntityConsolidationInventoryFamilyV1] = [:]
        for (family, keys) in groups {
            for key in keys where registry.updateValue(family, forKey: key) != nil {
                throw BackupCanonicalEncodingErrorV1.invalidRecords
            }
        }
        guard registry.count == entityIdentityResolutionRegisteredSectionCount else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return registry
    }

    private static func nonEntityIdentityResolutionHistory(
        _ history: MutationHistorySnapshotV1
    ) throws -> MutationHistorySnapshotV1 {
        var receipts: [MutationHistoryReceiptRecordV1] = []
        var removedMutationIDs = Set<UUID>()
        for record in history.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            if case let .applyEntityIdentityResolution(command) = envelope.command {
                removedMutationIDs.insert(command.mutationID.rawValue)
            } else {
                receipts.append(record)
            }
        }
        let accepted = try receipts.map {
            try MutationReceiptV1.decodeCanonical(from: $0.receiptData)
        }
        return MutationHistorySnapshotV1(
            workspaceRevision: accepted.map(\.resultingRevision.workspaceRevision).max() ?? 0,
            lastLocalSequence: accepted.map(\.identity.localSequence).max() ?? 0,
            receipts: receipts,
            quarantines: history.quarantines.filter { !removedMutationIDs.contains($0.mutationID) },
            entityRevisions: history.entityRevisions.filter {
                $0.identity.kind != .entityAliasLink && $0.identity.kind != .entityConsolidationReceipt
            }
        )
    }

    private static func recordFields(
        _ records: V4BackupRecordsV1
    ) throws -> [String: CanonicalJSONValueV1] {
        var fields: [String: CanonicalJSONValueV1] = [
            "assets": .array(records.assets.map(Self.asset)),
            "evidenceFiles": .array(records.evidenceFiles.map(Self.evidenceFile)),
            "issues": .array(records.issues.map(Self.issue)),
            "packets": .array(records.packets.map(Self.packet)),
            "recordsSchemaVersion": .integer(records.recordsSchemaVersion),
            "reports": .array(records.reports.map(Self.report)),
            "sites": .array(records.sites.map(Self.site)),
            "workflowRecords": .array(records.workflowRecords.map {
                Self.workflowRecord(
                    $0,
                    includeObservationAndTime: records.recordsSchemaVersion >= 4
                )
            }),
        ]
        if records.recordsSchemaVersion >= 5 {
            fields["assetCompositionEdges"] = .array(records.assetCompositionEdges.map(Self.locationRecord))
            fields["assetCompositionEvents"] = .array(records.assetCompositionEvents.map(Self.locationRecord))
            fields["assetPlacementEvents"] = .array(records.assetPlacementEvents.map(Self.locationRecord))
            fields["locationHierarchyEvents"] = .array(records.locationHierarchyEvents.map(Self.locationRecord))
            fields["locationMigrationReceipts"] = .array(records.locationMigrationReceipts.map(Self.locationRecord))
            fields["locationNodes"] = .array(records.locationNodes.map(Self.locationRecord))
        }
        if records.recordsSchemaVersion >= 6 {
            fields["savedSmartViews"] = .array(
                records.savedSmartViews.map(Self.savedSmartViewRecord)
            )
        }
        if records.recordsSchemaVersion >= 7 {
            fields["requirementAssurance"] = .array(
                records.requirementAssurance.map(Self.requirementAssuranceRecord)
            )
        }
        if records.recordsSchemaVersion >= 8 {
            fields["partyAccountability"] = .array(
                try records.partyAccountability.map(Self.partyAccountabilityRecord)
            )
        }
        if records.recordsSchemaVersion >= 9 {
            fields["assetSemantics"] = .array(
                try records.assetSemantics.map(Self.assetSemanticRecord)
            )
        }
        if records.recordsSchemaVersion >= 10 {
            fields["authorityCriterion"] = .array(
                try records.authorityCriterion.map(Self.authorityCriterionRecord)
            )
        }
        if records.recordsSchemaVersion >= 11 {
            fields["functionalRelationships"] = .array(
                try records.functionalRelationships.map(Self.functionalRelationshipRecord)
            )
        }
        if records.recordsSchemaVersion >= 12 {
            fields["evidenceAssurance"] = .array(
                try records.evidenceAssurance.map(Self.evidenceAssuranceRecord)
            )
        }
        if records.recordsSchemaVersion >= 13 {
            fields["inspectionReview"] = .array(
                try records.inspectionReview.map(Self.inspectionReviewRecord)
            )
        }
        if records.recordsSchemaVersion >= 14 {
            fields["workPackets"] = .array(try records.workPackets.map(Self.workPacketRecord))
        }
        if records.recordsSchemaVersion >= 15 {
            fields["fieldDrafts"] = .array(try records.fieldDrafts.map(Self.fieldDraftRecord))
        }
        if records.recordsSchemaVersion >= 16 {
            fields["packageEvolution"] = .array(try records.packageEvolution.map(Self.packageEvolutionRecord))
        }
        if records.recordsSchemaVersion >= 17 {
            fields["measurementIntegrity"] = .array(try records.measurementIntegrity.map(Self.measurementIntegrityRecord))
        }
        if records.recordsSchemaVersion >= 18 {
            fields["privacyTransforms"] = .array(try records.privacyTransforms.map(Self.privacyTransformRecord))
        }
        if records.recordsSchemaVersion >= 19 { fields["clientCapabilities"] = .array(try records.clientCapabilities.map(Self.clientCapabilityRecord)) }
        if records.recordsSchemaVersion >= 20 { fields["recoverabilityReceipts"] = .array(try records.recoverabilityReceipts.map(Self.recoverabilityReceiptRecord)) }
        if records.recordsSchemaVersion >= 21 { fields["fieldReferences"] = .array(try records.fieldReferences.map(Self.fieldReferenceRecord)) }
        if records.recordsSchemaVersion >= 22 { fields["accessibleDocumentAssessments"] = .array(try records.accessibleDocumentAssessments.map(Self.accessibleDocumentAssessmentRecord)) }
        if records.recordsSchemaVersion >= 23 { fields["surveyDefinitions"] = .array(try records.surveyDefinitions.map(Self.surveyDefinitionRecord)) }
        if records.recordsSchemaVersion >= 24 { fields["guidedSurveys"] = .array(try records.guidedSurveys.map(Self.guidedSurveyRecord)) }
        if records.recordsSchemaVersion >= 25 { fields["assetLocators"] = .array(try records.assetLocators.map(Self.assetLocatorRecord)) }
        if records.recordsSchemaVersion >= 26 { fields["schedules"] = .array(try records.schedules.map(Self.scheduleRecord)) }
        if records.recordsSchemaVersion >= 27 { fields["plans"] = .array(try records.plans.map(Self.planRecord)) }
        if records.recordsSchemaVersion >= 28 {
            fields["placementPoses"] = .array(try records.placementPoses.map(Self.placementPoseRecord))
        }
        if records.recordsSchemaVersion >= 29 {
            fields["evidenceContexts"] = .array(
                try records.evidenceContexts.map(Self.evidenceContextRecord)
            )
            fields["pairedObservationLinks"] = .array(
                try records.pairedObservationLinks.map(Self.evidenceContextRecord)
            )
        }
        if records.recordsSchemaVersion >= 30 {
            fields["lighting"] = .array(
                try records.lighting.map(Self.lightingRecord)
            )
        }
        if records.recordsSchemaVersion >= LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion {
            fields["lightingDayInventoryWorkflows"] = .array(
                try records.lightingDayInventoryWorkflows.map(Self.lightingDayInventoryRecord)
            )
        }
        if records.recordsSchemaVersion >= LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion {
            fields["lightingNightWorkflows"] = .array(
                try records.lightingNightWorkflows.map(Self.lightingNightWorkflowRecord)
            )
        }
        if records.recordsSchemaVersion >= 31 {
            fields["assistanceAcceptanceReceipts"] = .array(
                records.assistanceAcceptanceReceipts.map(Self.assistanceAcceptanceReceiptRecord)
            )
        }
        if records.recordsSchemaVersion >= 32 {
            fields["temporalEvidence"] = .array(
                try records.temporalEvidence.map(Self.temporalEvidenceRecord)
            )
        }
        if records.recordsSchemaVersion >= 33 {
            fields["acceptedLabelGenerationSnapshots"] = .array(
                records.acceptedLabelGenerationSnapshots.map(Self.acceptedLabelSnapshotRecord)
            )
        }
        if records.recordsSchemaVersion >= 34 {
            fields["operationalContacts"] = .array(
                records.operationalContacts.map(Self.operationalContactRecord)
            )
        }
        if records.recordsSchemaVersion >= 35 {
            fields["activityContracts"] = .array(
                records.activityContracts.map(Self.activityContractRecord)
            )
        }
        if records.recordsSchemaVersion >= C49BackupEnrollmentV1.recordsSchemaVersion {
            _ = try records.validateC49WorkResources()
            fields["workResources"] = .array(
                try records.workResources.map(Self.workResourceRecord)
            )
        }
        if records.recordsSchemaVersion >= C52ServiceRequestBackupEncodingBoundaryV1.recordsSchemaVersion
                && records.recordsSchemaVersion < C53ServiceReliabilityBackupEncodingBoundaryV1.recordsSchemaVersion {
            try C52ServiceRequestBackupDecodingBoundaryV1.validate(records)
            fields["serviceRequests"] = .array(try records.serviceRequests.map(Self.serviceRequestRecord))
            fields["serviceRequestDispositionEvents"] = .array(try records.serviceRequestDispositionEvents.map(Self.serviceRequestDispositionRecord))
            fields["serviceRequestWorkLinkEvents"] = .array(try records.serviceRequestWorkLinkEvents.map(Self.serviceRequestWorkLinkRecord))
        }
        if records.recordsSchemaVersion >= C53ServiceReliabilityBackupEnrollmentV1.recordsSchemaVersion {
            try C53ServiceReliabilityBackupEnrollmentV1.validate(records: records)
            fields["serviceReliabilityIncidents"] = .array(try records.serviceReliabilityIncidents.map(Self.serviceReliabilityRecord))
            fields["serviceImpactSegments"] = .array(try records.serviceImpactSegments.map(Self.serviceReliabilityRecord))
            fields["serviceCauseAssertions"] = .array(try records.serviceCauseAssertions.map(Self.serviceReliabilityRecord))
            fields["serviceRemedyAssertions"] = .array(try records.serviceRemedyAssertions.map(Self.serviceReliabilityRecord))
            fields["serviceRepairIntervals"] = .array(try records.serviceRepairIntervals.map(Self.serviceReliabilityRecord))
            fields["serviceRestorationAssertions"] = .array(try records.serviceRestorationAssertions.map(Self.serviceReliabilityRecord))
            fields["qualifiedServiceExposures"] = .array(try records.qualifiedServiceExposures.map(Self.serviceReliabilityRecord))
            fields["serviceReliabilityReceipts"] = .array(try records.serviceReliabilityReceipts.map(Self.serviceReliabilityReceiptRecord))
        }
        if records.recordsSchemaVersion >= C55PartsStockBackupEncodingBoundaryV1.recordsSchemaVersion {
            try C55PartsStockBackupEnrollmentV1.validate(records)
            guard let snapshot = records.partsStockSnapshot else {
                throw BackupCanonicalEncodingErrorV1.invalidRecords
            }
            fields["partsStockSnapshot"] = try Self.partsStockSnapshot(snapshot)
        }
        if records.recordsSchemaVersion >= C57MyDayBackupEnrollmentV1.recordsSchemaVersion {
            try C57MyDayBackupEnrollmentV1.validate(records)
            fields["myDayPlans"] = .array(try records.myDayPlans.map(Self.myDayCanonicalValue))
            fields["myDayCarryoverReceipts"] = .array(
                try records.myDayCarryoverReceipts.map(Self.myDayCanonicalValue)
            )
            fields["nonactivePlanReferences"] = .array(
                try records.nonactivePlanReferences.map(Self.myDayCanonicalValue)
            )
        }
        if records.recordsSchemaVersion >= C05EvidenceMetadataBackupEnrollmentV1.recordsSchemaVersion {
            try C05EvidenceMetadataBackupEnrollmentV1.validate(records)
            fields["evidenceAssociationEvents"] = .array(
                try records.evidenceAssociationEvents.map(Self.evidenceMetadataCanonicalValue)
            )
            fields["evidenceSequenceRevisions"] = .array(
                try records.evidenceSequenceRevisions.map(Self.evidenceMetadataCanonicalValue)
            )
        }
        if records.recordsSchemaVersion >= C04ShopReportProfileBackupEnrollmentV1.recordsSchemaVersion {
            try C04ShopReportProfileBackupEnrollmentV1.validate(records)
            fields["shopReportProfiles"] = .array(
                try records.shopReportProfiles.map(Self.shopReportProfileCanonicalValue)
            )
        }
        if records.recordsSchemaVersion >= C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion {
            try C05RoundSessionBackupEnrollmentV1.validate(records)
            fields["roundSessions"] = .array(
                try records.roundSessions.map(Self.roundSessionCanonicalValue)
            )
        }
        if records.recordsSchemaVersion >= C08ImportBulkBackupEnrollmentV1.recordsSchemaVersion {
            try C08ImportBulkBackupEnrollmentV1.validate(records)
            fields["importMappingProfiles"] = .array(try records.importMappingProfiles.map(Self.importBulkCanonicalValue))
            fields["bulkSessions"] = .array(try records.bulkSessions.map(Self.importBulkCanonicalValue))
            fields["bulkCommitReceipts"] = .array(try records.bulkCommitReceipts.map(Self.importBulkCanonicalValue))
        }
        if records.recordsSchemaVersion >= ReinspectionExceptionQueueBackupEnrollmentV1.recordsSchemaVersion {
            try ReinspectionExceptionQueueBackupEnrollmentV1.validate(records)
            guard let snapshot = records.reinspectionExceptionQueue else {
                throw BackupCanonicalEncodingErrorV1.invalidRecords
            }
            fields["reinspectionExceptionQueue"] = try Self.reinspectionExceptionQueueSnapshot(snapshot)
        }
        if records.recordsSchemaVersion >= EntityIdentityResolutionBackupEnrollmentV1.recordsSchemaVersion {
            try EntityIdentityResolutionBackupEnrollmentV1.validate(records)
            guard let snapshot = records.entityIdentityResolution else {
                throw BackupCanonicalEncodingErrorV1.invalidRecords
            }
            fields["entityIdentityResolution"] = try Self.entityIdentityResolutionSnapshot(snapshot)
        }
        if records.recordsSchemaVersion >= PracticeWorkspaceBackupEnrollmentV1.recordsSchemaVersion {
            try PracticeWorkspaceBackupEnrollmentV1.validate(records)
            guard let snapshot = records.practiceWorkspaceProvenance else {
                throw BackupCanonicalEncodingErrorV1.invalidRecords
            }
            fields["practiceWorkspaceProvenance"] = try Self.practiceWorkspaceSnapshot(snapshot)
        }
        if records.recordsSchemaVersion >= LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion {
            try LightingDayInventoryBackupEnrollmentV1.validate(records)
            try records.validateC17LightingDayInventoryClosure()
        }
        if let deletionLedger = records.deletionLedger {
            fields["deletionLedger"] = Self.deletionLedger(deletionLedger)
        }
        if let mutationHistory = records.mutationHistory {
            fields["mutationHistory"] = try Self.mutationHistory(mutationHistory)
        }
        return fields
    }

    func encodeManifest(_ manifest: V4BackupManifestV1) throws -> EncodedBackupJSONV1 {
        try C34SceneNavigationBackupEncoderBoundaryV1.validate()
        guard Self.valid(manifest) else {
            throw BackupCanonicalEncodingErrorV1.invalidManifest
        }
        return try encoded(.object([
            "backupSchemaVersion": .integer(manifest.backupSchemaVersion),
            "consumedEvaluationRootIDs": .array(
                manifest.consumedEvaluationRootIDs.map(CanonicalJSONV1.uuid)
            ),
            "declaredPayloadByteCount": .integer(manifest.declaredPayloadByteCount),
            "entries": .array(manifest.entries.map(Self.entry)),
            "exportedAt": CanonicalJSONV1.date(manifest.exportedAt),
            "packs": .array(manifest.packs.map(Self.pack)),
            "source": Self.source(manifest.source),
        ]))
    }

    private func encoded(_ value: CanonicalJSONValueV1) throws -> EncodedBackupJSONV1 {
        let data = try CanonicalJSONV1.encode(value)
        return EncodedBackupJSONV1(data: data, sha256: CanonicalJSONV1.sha256(data))
    }
}

enum C30EvidenceContextBackupEncoderV1 {
    static func encode(_ value: EvidenceContextV1) throws -> V30BackupEvidenceContextRecordV1 {
        try value.validateIntrinsic()
        return .init(kind: .evidenceContext, id: value.contextID,
                     workspaceID: value.workspaceID.rawValue, revision: value.revision,
                     canonicalData: try EvidenceContextCanonicalCodecV1.encode(value))
    }

    static func encode(_ value: PairedObservationLinkV1) throws -> V30BackupEvidenceContextRecordV1 {
        try value.validateIntrinsic()
        return .init(kind: .pairedObservationLink, id: value.linkID,
                     workspaceID: value.workspaceID.rawValue, revision: value.revision,
                     canonicalData: try EvidenceContextCanonicalCodecV1.encode(value))
    }

    static func encode(_ values: EvidenceContextBackupRecordSetV1) throws
        -> [V30BackupEvidenceContextRecordV1] {
        let rows = try values.contexts.map(encode) + values.pairedObservationLinks.map(encode)
        return rows.sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())" <
            "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
    }
}

private extension BackupCanonicalEncoderV1 {
    static func partsStockSnapshot(_ value: PartsStockBackupSnapshotV1) throws -> CanonicalJSONValueV1 {
        try value.validate()
        let data = try PartsStockCanonicalCodecV1.encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try canonicalPartsStockJSON(object)
    }

    static func myDayCanonicalValue<T: Encodable>(_ value: T) throws -> CanonicalJSONValueV1 {
        let data = try MyDayCanonicalCodecV1.data(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try canonicalPartsStockJSON(object)
    }

    static func evidenceMetadataCanonicalValue<T: Encodable>(_ value: T) throws -> CanonicalJSONValueV1 {
        let data = try EvidenceMetadataCanonicalCodecV1.data(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try canonicalPartsStockJSON(object)
    }

    static func shopReportProfileCanonicalValue(
        _ value: ShopReportProfileV1
    ) throws -> CanonicalJSONValueV1 {
        try value.validateIntrinsic()
        let data = try ShopReportProfileCanonicalCodecV1.encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try canonicalPartsStockJSON(object)
    }

    static func roundSessionCanonicalValue(
        _ value: RoundSessionV1
    ) throws -> CanonicalJSONValueV1 {
        try value.validateIntrinsic()
        let data = try RoundSessionCanonicalCodecV1.encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try canonicalPartsStockJSON(object)
    }

    static func importBulkCanonicalValue<T: Encodable>(_ value: T) throws -> CanonicalJSONValueV1 {
        let data = try ImportBulkCanonicalCodecV1.encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try canonicalPartsStockJSON(object)
    }

    static func reinspectionExceptionQueueSnapshot(
        _ value: ReinspectionExceptionQueueBackupSnapshotV1
    ) throws -> CanonicalJSONValueV1 {
        try value.validate()
        let data = try WorkspaceMutationCanonicalV1.data(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try canonicalPartsStockJSON(object)
    }

    static func entityIdentityResolutionSnapshot(
        _ value: EntityIdentityResolutionBackupSnapshotV1
    ) throws -> CanonicalJSONValueV1 {
        try value.validate()
        let data = try WorkspaceMutationCanonicalV1.data(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try canonicalPartsStockJSON(object)
    }

    static func practiceWorkspaceSnapshot(
        _ value: PracticeWorkspaceBackupSnapshotV1
    ) throws -> CanonicalJSONValueV1 {
        try value.validate()
        let data = try WorkspaceExperienceCanonicalCodecV1.data(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try canonicalPartsStockJSON(object)
    }

    static func canonicalPartsStockJSON(_ value: Any) throws -> CanonicalJSONValueV1 {
        if value is NSNull { return .null }
        if let value = value as? [String: Any] {
            return .object(try value.mapValues(canonicalPartsStockJSON))
        }
        if let value = value as? [Any] { return .array(try value.map(canonicalPartsStockJSON)) }
        if let value = value as? String { return .string(value) }
        if let value = value as? Bool { return .bool(value) }
        if let value = value as? NSNumber {
            guard CFGetTypeID(value) != CFBooleanGetTypeID() else {
                return .bool(value.boolValue)
            }
            let representation = value.stringValue
            guard !representation.contains("."),
                  !representation.contains("e"),
                  !representation.contains("E"),
                  let integer = Int(representation) else {
                throw BackupCanonicalEncodingErrorV1.invalidRecords
            }
            return .integer(integer)
        }
        throw BackupCanonicalEncodingErrorV1.invalidRecords
    }

    static func validSemantic(_ records: V4BackupRecordsV1) -> Bool {
        guard (4...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.mutationHistory == nil,
              let ledger = records.deletionLedger,
              (try? ledger.validate()) != nil else {
            return false
        }
        return validObservationAndTime(records)
            && validLocationRecords(records)
            && validSavedSmartViews(records)
            && validRequirementAssurance(records)
            && validPartyAccountability(records)
            && validAssetSemantics(records)
            && validAuthorityCriterion(records)
            && validFunctionalRelationships(records)
            && validEvidenceAssurance(records)
            && validInspectionReview(records)
            && validWorkPackets(records)
            && validFieldDrafts(records)
            && validPackageEvolution(records)
            && validMeasurementIntegrity(records)
            && validPrivacyTransforms(records)
            && validClientCapabilities(records)
            && validRecoverabilityReceipts(records)
            && validFieldReferences(records)
            && validAccessibleDocumentAssessments(records)
            && validSurveyDefinitions(records)
            && validGuidedSurveys(records)
            && validAssetLocators(records)
            && validSchedules(records)
            && validPlans(records)
            && validPlacementPoses(records)
            && validC30EvidenceContext(records)
            && validC31Lighting(records)
            && validC32AssistanceAcceptanceReceipts(records)
            && validC33TemporalEvidence(records)
            && validC45AcceptedLabelSemantic(records)
            && validC46OperationalContacts(records)
            && validC47ActivityContractSemantic(records)
            && validC49WorkResources(records)
            && validC04ShopReportProfiles(records)
            && validC05RoundSessions(records)
            && (try? ReinspectionExceptionQueueBackupEnrollmentV1.validate(records)) != nil
            && sortedUniqueIDs(records.assets.map(\.id))
            && records.assets.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.evidenceFiles.map(\.id))
            && records.evidenceFiles.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.issues.map(\.id))
            && records.issues.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.packets.map(\.id))
            && records.packets.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.reports.map(\.id))
            && records.reports.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.sites.map(\.id))
            && records.sites.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.workflowRecords.map(\.id))
            && records.workflowRecords.allSatisfy({ $0.schemaVersion == 1 })
    }

    static func valid(_ records: V4BackupRecordsV1) -> Bool {
        let ledgerIsValid: Bool
        switch (
            records.recordsSchemaVersion,
            records.deletionLedger,
            records.mutationHistory
        ) {
        case (1, nil, nil):
            ledgerIsValid = true
        case (2, let ledger?, nil):
            ledgerIsValid = (try? ledger.validate()) != nil
        case (3, let ledger?, let history?), (4, let ledger?, let history?),
            (5, let ledger?, let history?), (6, let ledger?, let history?),
            (7, let ledger?, let history?), (8, let ledger?, let history?),
             (9, let ledger?, let history?), (10, let ledger?, let history?),
             (11, let ledger?, let history?), (12, let ledger?, let history?),
             (13, let ledger?, let history?), (14, let ledger?, let history?),
             (15, let ledger?, let history?), (16, let ledger?, let history?),
             (17, let ledger?, let history?), (18, let ledger?, let history?), (19, let ledger?, let history?),
             (20, let ledger?, let history?), (21, let ledger?, let history?), (22, let ledger?, let history?), (23, let ledger?, let history?), (24, let ledger?, let history?), (25, let ledger?, let history?), (26, let ledger?, let history?), (27, let ledger?, let history?), (28, let ledger?, let history?), (29, let ledger?, let history?), (30, let ledger?, let history?), (31, let ledger?, let history?), (32, let ledger?, let history?), (33, let ledger?, let history?), (34, let ledger?, let history?), (35, let ledger?, let history?), (36, let ledger?, let history?), (37, let ledger?, let history?), (38, let ledger?, let history?), (39, let ledger?, let history?), (C55PartsStockBackupEnrollmentV1.recordsSchemaVersion, let ledger?, let history?), (C57MyDayBackupEnrollmentV1.recordsSchemaVersion, let ledger?, let history?), (C04ShopReportProfileBackupEnrollmentV1.recordsSchemaVersion, let ledger?, let history?), (C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion, let ledger?, let history?), (ReinspectionExceptionQueueBackupEnrollmentV1.recordsSchemaVersion, let ledger?, let history?), (EntityIdentityResolutionBackupEnrollmentV1.recordsSchemaVersion, let ledger?, let history?), (PracticeWorkspaceBackupEnrollmentV1.recordsSchemaVersion, let ledger?, let history?), (LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion, let ledger?, let history?):
            ledgerIsValid = (try? ledger.validate()) != nil
                && (try? MutationJournalStoreV1.validateImportedSnapshot(history)) != nil
                && validMutationHistoryOrder(history)
        default:
            ledgerIsValid = false
        }
        return ledgerIsValid
            && validObservationAndTime(records)
            && validLocationRecords(records)
            && validSavedSmartViews(records)
            && validRequirementAssurance(records)
            && validPartyAccountability(records)
            && validAssetSemantics(records)
            && validAuthorityCriterion(records)
            && validFunctionalRelationships(records)
            && validEvidenceAssurance(records)
            && validInspectionReview(records)
            && validWorkPackets(records)
            && validFieldDrafts(records)
            && validPackageEvolution(records)
            && validMeasurementIntegrity(records)
            && validPrivacyTransforms(records)
            && validClientCapabilities(records)
            && validRecoverabilityReceipts(records)
            && validFieldReferences(records)
            && validAccessibleDocumentAssessments(records)
            && validSurveyDefinitions(records)
            && validGuidedSurveys(records)
            && validAssetLocators(records)
            && validSchedules(records)
            && validPlans(records)
            && validC30EvidenceContext(records)
            && validC31Lighting(records)
            && validC32AssistanceAcceptanceReceipts(records)
            && validC33TemporalEvidence(records)
            && validC45AcceptedLabelSnapshots(records)
            && validC46OperationalContacts(records)
             && validC47ActivityContracts(records)
            && validC49WorkResources(records)
            && validC04ShopReportProfiles(records)
             && (try? C52ServiceRequestBackupDecodingBoundaryV1.validate(records)) != nil
             && validC53ServiceReliability(records)
             && validC55PartsStock(records)
             && (try? ReinspectionExceptionQueueBackupEnrollmentV1.validate(records)) != nil
            && sortedUniqueIDs(records.assets.map(\.id))
            && records.assets.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.evidenceFiles.map(\.id))
            && records.evidenceFiles.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.issues.map(\.id))
            && records.issues.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.packets.map(\.id))
            && records.packets.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.reports.map(\.id))
            && records.reports.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.sites.map(\.id))
            && records.sites.allSatisfy({ $0.schemaVersion == 1 })
            && sortedUniqueIDs(records.workflowRecords.map(\.id))
            && records.workflowRecords.allSatisfy({ $0.schemaVersion == 1 })
    }

    static func validObservationAndTime(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 4 {
            return records.workflowRecords.allSatisfy {
                $0.observationBasisV1Data == nil && $0.temporalContextV1Data == nil
            }
        }
        guard (4...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else { return false }
        return records.workflowRecords.allSatisfy { record in
            guard let basisData = record.observationBasisV1Data,
                  let temporalData = record.temporalContextV1Data else { return false }
            do {
                let basis = try ObservationAndTimeCodecV1.decodeObservationBasis(
                    basisData
                )
                let temporal = try ObservationAndTimeCodecV1.decodeTemporalContext(
                    temporalData
                )
                let projectedOffset: Int?
                if let minutes = record.utcOffsetMinutes {
                    let (seconds, overflow) = minutes.multipliedReportingOverflow(
                        by: 60
                    )
                    guard !overflow else { return false }
                    projectedOffset = seconds
                } else {
                    projectedOffset = nil
                }
                return try ObservationAndTimeCodecV1.encode(basis) == basisData
                    && ObservationAndTimeCodecV1.encode(temporal) == temporalData
                    && temporal.occurredAtUTC == record.observedAtUTC
                    && temporal.localDate == record.localDate
                    && temporal.localTime == record.localTime
                    && temporal.ianaTimeZoneIdentifier == record.timeZoneID
                    && temporal.utcOffsetSeconds == projectedOffset
            } catch {
                return false
            }
        }
    }

    static func validLocationRecords(_ records: V4BackupRecordsV1) -> Bool {
        let groups = [
            records.assetCompositionEdges, records.assetCompositionEvents,
            records.assetPlacementEvents, records.locationHierarchyEvents,
            records.locationMigrationReceipts, records.locationNodes,
        ]
        if records.recordsSchemaVersion < 5 {
            return groups.allSatisfy(\.isEmpty)
        }
        guard groups.allSatisfy({ values in
            values.map(\.id.uuidString) == values.map(\.id.uuidString).sorted()
                && Set(values.map(\.id)).count == values.count
                && values.allSatisfy {
                    !$0.canonicalData.isEmpty
                        && $0.canonicalData.count
                            <= SnapshotProjectionLimitsV1.maximumProjectionBytes
                        && ($0.secondaryCanonicalData?.count ?? 0)
                            <= SnapshotProjectionLimitsV1.maximumProjectionBytes
                }
        })
            && records.locationHierarchyEvents.allSatisfy {
                !($0.secondaryCanonicalData?.isEmpty ?? true)
            }
            && (records.assetCompositionEdges
                + records.assetCompositionEvents
                + records.assetPlacementEvents
                + records.locationMigrationReceipts
                + records.locationNodes).allSatisfy {
                    $0.secondaryCanonicalData == nil
                } else {
            return false
        }
        do {
            let placements = try records.assetPlacementEvents.map { record in
                let value = try LocationPersistenceCodecV1.decode(
                    AssetPlacementEventV1.self,
                    from: record.canonicalData
                )
                guard value.id == record.id else { throw LocationContractFailureV1.invalidValue }
                return value
            }
            for history in Dictionary(grouping: placements, by: \.assetID).values {
                try AssetPlacementHistoryV1.validate(history)
            }
            let edges = try records.assetCompositionEdges.map { record in
                let value = try LocationPersistenceCodecV1.decode(
                    AssetCompositionEdgeV1.self,
                    from: record.canonicalData
                )
                guard value.id == record.id else { throw LocationContractFailureV1.invalidValue }
                return value
            }
            let events = try records.assetCompositionEvents.map { record in
                let value = try LocationPersistenceCodecV1.decode(
                    AssetCompositionEventV1.self,
                    from: record.canonicalData
                )
                guard value.id == record.id else { throw LocationContractFailureV1.invalidValue }
                return value
            }
            let currentEdges = Dictionary(uniqueKeysWithValues: edges.map { ($0.id, $0) })
            let historyByEdge = Dictionary(grouping: events, by: { $0.edge.id })
            guard Set(currentEdges.keys) == Set(historyByEdge.keys) else { return false }
            for (edgeID, history) in historyByEdge {
                guard let current = currentEdges[edgeID] else { return false }
                try AssetCompositionHistoryV1.validate(history, currentEdge: current)
            }
            for record in records.locationNodes {
                let value = try LocationPersistenceCodecV1.decode(
                    LocationNodeV1.self,
                    from: record.canonicalData
                )
                guard value.id == record.id else { return false }
            }
            for record in records.locationHierarchyEvents {
                guard let receiptData = record.secondaryCanonicalData else { return false }
                let plan = try LocationPersistenceCodecV1.decode(
                    LocationHierarchyChangePlanV1.self,
                    from: record.canonicalData
                )
                let receipt = try LocationPersistenceCodecV1.decode(
                    LocationHierarchyChangeReceiptV1.self,
                    from: receiptData
                )
                guard plan.operationID == record.id,
                      receipt.planSHA256 == plan.planSHA256 else { return false }
            }
            for record in records.locationMigrationReceipts {
                let receipt = try LocationPersistenceCodecV1.decode(
                    LocationMigrationReceiptV1.self,
                    from: record.canonicalData
                )
                guard receipt.candidateGenerationID == record.id else { return false }
            }
            return true
        } catch {
            return false
        }
    }

    static func validSavedSmartViews(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 6 { return records.savedSmartViews.isEmpty }
        guard (6...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.savedSmartViews.map(\.id.uuidString)
                == records.savedSmartViews.map(\.id.uuidString).sorted(),
              Set(records.savedSmartViews.map(\.id)).count == records.savedSmartViews.count else {
            return false
        }
        do {
            let descriptors = try records.savedSmartViews.map { try $0.descriptor() }
            return Set(descriptors.map {
                SavedSmartViewRowV1.key(workspaceID: $0.workspaceID, stableID: $0.stableID)
            }).count == descriptors.count
        } catch {
            return false
        }
    }

    static func validRequirementAssurance(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 7 { return records.requirementAssurance.isEmpty }
        guard (7...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.requirementAssurance.map(\.workflowRecordID.uuidString)
                == records.requirementAssurance.map(\.workflowRecordID.uuidString).sorted(),
              Set(records.requirementAssurance.map(\.workflowRecordID)).count
                == records.requirementAssurance.count,
              Set(records.requirementAssurance.map(\.workflowRecordID))
                == Set(records.workflowRecords.map(\.id)) else { return false }
        return records.requirementAssurance.allSatisfy {
            (try? $0.validate()) != nil
        }
    }

    static func validPartyAccountability(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 8 { return records.partyAccountability.isEmpty }
        guard (8...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.partyAccountability.map({ "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" })
                == records.partyAccountability.map({ "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }).sorted(),
              Set(records.partyAccountability.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }).count
                == records.partyAccountability.count else { return false }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return records.partyAccountability.allSatisfy {
            $0.id != zero && $0.workspaceID != zero
                && ($0.revision.map { $0 > 0 && $0 <= UInt64(Int.max) } ?? true)
                && !$0.canonicalData.isEmpty
        }
    }

    static func validAssetSemantics(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 9 { return records.assetSemantics.isEmpty }
        guard (9...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else { return false }
        let keys = records.assetSemantics.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return keys == keys.sorted() && Set(keys).count == keys.count
            && records.assetSemantics.allSatisfy {
                $0.id != zero && $0.workspaceID != zero && $0.revision > 0
                    && $0.revision <= UInt64(Int.max) && !$0.canonicalData.isEmpty
            }
    }

    static func validAuthorityCriterion(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 10 { return records.authorityCriterion.isEmpty }
        guard (10...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else { return false }
        let keys = records.authorityCriterion.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return keys == keys.sorted() && Set(keys).count == keys.count
            && records.authorityCriterion.allSatisfy {
                $0.id != zero && $0.workspaceID != zero && !$0.canonicalData.isEmpty
            }
    }

    static func validFunctionalRelationships(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 11 { return records.functionalRelationships.isEmpty }
        guard (11...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else { return false }
        let keys = records.functionalRelationships.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return keys == keys.sorted() && Set(keys).count == keys.count
            && records.functionalRelationships.allSatisfy {
                $0.id != zero && $0.workspaceID != zero && $0.revision > 0
                    && $0.revision <= UInt64(Int.max) && !$0.canonicalData.isEmpty
            }
    }

    static func validEvidenceAssurance(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 12 { return records.evidenceAssurance.isEmpty }
        guard (12...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else { return false }
        let keys = records.evidenceAssurance.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return keys == keys.sorted() && Set(keys).count == keys.count
            && records.evidenceAssurance.allSatisfy {
                $0.id != zero && $0.workspaceID != zero && $0.revision > 0
                    && $0.revision <= UInt64(Int.max) && !$0.canonicalData.isEmpty
            }
    }

    static func validInspectionReview(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 13 { return records.inspectionReview.isEmpty }
        guard (13...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else { return false }
        let keys = records.inspectionReview.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return records.inspectionReview.count <= InspectionReviewLimitsV1.maximumHistory
            && keys == keys.sorted() && Set(keys).count == keys.count
            && records.inspectionReview.allSatisfy {
                $0.id != zero && $0.workspaceID != zero && $0.revision > 0
                    && $0.revision <= UInt64(Int.max) && !$0.canonicalData.isEmpty
            }
    }

    static func validWorkPackets(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 14 { return records.workPackets.isEmpty }
        guard (14...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else { return false }
        let keys = records.workPackets.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return records.workPackets.count <= WorkPacketLimitsV1.maximumHistory
            && keys == keys.sorted() && Set(keys).count == keys.count
            && records.workPackets.allSatisfy {
                $0.id != zero && $0.workspaceID != zero && $0.revision > 0
                    && $0.revision <= UInt64(Int.max) && !$0.canonicalData.isEmpty
            }
    }

    static func validFieldDrafts(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 15 { return records.fieldDrafts.isEmpty }
        guard (15...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else { return false }
        let keys = records.fieldDrafts.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return records.fieldDrafts.count <= 100_000
            && keys == keys.sorted() && Set(keys).count == keys.count
            && records.fieldDrafts.allSatisfy {
                $0.id != zero && $0.workspaceID != zero && $0.revision > 0
                    && $0.revision <= UInt64(Int.max) && !$0.canonicalData.isEmpty
            }
    }

    static func validPackageEvolution(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 16 { return records.packageEvolution.isEmpty }
        guard (16...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else { return false }
        let keys = records.packageEvolution.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return records.packageEvolution.count <= 100_000 && Set(keys).count == keys.count
            && records.packageEvolution.allSatisfy {
                $0.id != zero && $0.workspaceID != zero && $0.revision > 0 && !$0.canonicalData.isEmpty
            }
    }

    static func validMeasurementIntegrity(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 17 { return records.measurementIntegrity.isEmpty }
        guard (17...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else { return false }
        let keys = records.measurementIntegrity.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return records.measurementIntegrity.count <= 100_000 && keys == keys.sorted()
            && Set(keys).count == keys.count
            && records.measurementIntegrity.allSatisfy {
                $0.id != zero && $0.workspaceID != zero && $0.revision > 0
                    && $0.revision <= UInt64(Int.max) && !$0.canonicalData.isEmpty
            }
    }

    static func validPrivacyTransforms(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 18 { return records.privacyTransforms.isEmpty }
        guard (18...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else { return false }
        let keys = records.privacyTransforms.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return records.privacyTransforms.count <= 100_000 && keys == keys.sorted()
            && Set(keys).count == keys.count
            && records.privacyTransforms.allSatisfy {
                $0.id != zero && $0.workspaceID != zero && $0.revision > 0
                    && $0.revision <= UInt64(Int.max) && !$0.canonicalData.isEmpty
            }
    }

    static func validClientCapabilities(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 19 { return records.clientCapabilities.isEmpty }
        guard (19...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else { return false }
        let keys=records.clientCapabilities.map{"\($0.kind.rawValue)\u{0}\($0.id.uuidString)"};let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return records.clientCapabilities.count<=100_000 && keys==keys.sorted() && Set(keys).count==keys.count && records.clientCapabilities.allSatisfy{$0.id != zero && $0.workspaceID != zero && $0.revision>0 && $0.revision<=UInt64(Int.max) && !$0.canonicalData.isEmpty}
    }
    static func clientCapabilityRecord(_ value:V20BackupClientCapabilityRecordV1)throws->CanonicalJSONValueV1{guard let revision=Int(exactly:value.revision),!value.canonicalData.isEmpty else{throw BackupCanonicalEncodingErrorV1.invalidRecords};return .object(["canonicalData":.string(value.canonicalData.base64EncodedString()),"id":CanonicalJSONV1.uuid(value.id),"kind":.string(value.kind.rawValue),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)])}

 static func validRecoverabilityReceipts(_ records:V4BackupRecordsV1)->Bool{if records.recordsSchemaVersion<20{return records.recoverabilityReceipts.isEmpty};guard (20...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else{return false};let keys=records.recoverabilityReceipts.map{$0.id.uuidString};let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0));return records.recoverabilityReceipts.count<=100_000 && keys==keys.sorted() && Set(keys).count==keys.count && records.recoverabilityReceipts.allSatisfy{$0.id != zero && $0.workspaceID != zero && $0.revision>0 && $0.revision<=UInt64(Int.max) && !$0.canonicalData.isEmpty}}
    static func recoverabilityReceiptRecord(_ value:V21BackupRecoverabilityReceiptRecordV1)throws->CanonicalJSONValueV1{guard let revision=Int(exactly:value.revision),!value.canonicalData.isEmpty else{throw BackupCanonicalEncodingErrorV1.invalidRecords};return .object(["canonicalData":.string(value.canonicalData.base64EncodedString()),"id":CanonicalJSONV1.uuid(value.id),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)])}
 static func validFieldReferences(_ records:V4BackupRecordsV1)->Bool{if records.recordsSchemaVersion<21{return records.fieldReferences.isEmpty};guard records.recordsSchemaVersion<=LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion else{return false};let keys=records.fieldReferences.map{"\($0.kind.rawValue)|\($0.id.uuidString)"};let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0));return records.fieldReferences.count<=100_000 && keys==keys.sorted() && Set(keys).count==keys.count && records.fieldReferences.allSatisfy{$0.id != zero && $0.workspaceID != zero && $0.revision>0 && $0.revision<=UInt64(Int.max) && !$0.canonicalData.isEmpty}}
    static func fieldReferenceRecord(_ value:V22BackupFieldReferenceRecordV1)throws->CanonicalJSONValueV1{guard let revision=Int(exactly:value.revision),!value.canonicalData.isEmpty else{throw BackupCanonicalEncodingErrorV1.invalidRecords};return .object(["canonicalData":.string(value.canonicalData.base64EncodedString()),"id":CanonicalJSONV1.uuid(value.id),"kind":.string(value.kind.rawValue),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)])}
    static func validAccessibleDocumentAssessments(_ records:V4BackupRecordsV1)->Bool{if records.recordsSchemaVersion<22{return records.accessibleDocumentAssessments.isEmpty};let keys=records.accessibleDocumentAssessments.map{$0.id.uuidString};let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0));return records.accessibleDocumentAssessments.count<=100_000 && keys==keys.sorted() && Set(keys).count==keys.count && records.accessibleDocumentAssessments.allSatisfy{$0.id != zero && $0.workspaceID != zero && $0.revision>0 && $0.revision<=UInt64(Int.max) && !$0.canonicalData.isEmpty}}
    static func accessibleDocumentAssessmentRecord(_ value:V23BackupAccessibleDocumentAssessmentRecordV1)throws->CanonicalJSONValueV1{guard let revision=Int(exactly:value.revision),!value.canonicalData.isEmpty else{throw BackupCanonicalEncodingErrorV1.invalidRecords};return .object(["canonicalData":.string(value.canonicalData.base64EncodedString()),"id":CanonicalJSONV1.uuid(value.id),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)])}
 static func validSurveyDefinitions(_ records:V4BackupRecordsV1)->Bool{if records.recordsSchemaVersion<23{return records.surveyDefinitions.isEmpty};guard (23...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else{return false};if records.mutationHistory==nil{return records.surveyDefinitions.isEmpty};let keys=records.surveyDefinitions.map{"\($0.kind.rawValue)|\($0.id.uuidString)"};let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0));return records.surveyDefinitions.count<=200_000&&keys==keys.sorted()&&Set(keys).count==keys.count&&records.surveyDefinitions.allSatisfy{$0.id != zero&&$0.workspaceID != zero&&$0.revision>0&&$0.revision<=UInt64(Int.max)&&!$0.canonicalData.isEmpty}}
    static func surveyDefinitionRecord(_ value:V24BackupSurveyDefinitionRecordV1)throws->CanonicalJSONValueV1{guard let revision=Int(exactly:value.revision),!value.canonicalData.isEmpty else{throw BackupCanonicalEncodingErrorV1.invalidRecords};return .object(["canonicalData":.string(value.canonicalData.base64EncodedString()),"id":CanonicalJSONV1.uuid(value.id),"kind":.string(value.kind.rawValue),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)])}
 static func validGuidedSurveys(_ records:V4BackupRecordsV1)->Bool{if records.recordsSchemaVersion<24{return records.guidedSurveys.isEmpty};guard (24...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion) else{return false};if records.mutationHistory == nil{return records.guidedSurveys.isEmpty};let keys=records.guidedSurveys.map{"\($0.kind.rawValue)|\($0.id.uuidString)"};let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0));return records.guidedSurveys.count<=200_000&&keys==keys.sorted()&&Set(keys).count==keys.count&&records.guidedSurveys.allSatisfy{$0.id != zero&&$0.workspaceID != zero&&$0.revision>0&&$0.revision<=UInt64(Int.max)&&!$0.canonicalData.isEmpty}}
    static func guidedSurveyRecord(_ value:V25BackupGuidedSurveyRecordV1)throws->CanonicalJSONValueV1{guard let revision=Int(exactly:value.revision),!value.canonicalData.isEmpty else{throw BackupCanonicalEncodingErrorV1.invalidRecords};return .object(["canonicalData":.string(value.canonicalData.base64EncodedString()),"id":CanonicalJSONV1.uuid(value.id),"kind":.string(value.kind.rawValue),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)])}
    static func validAssetLocators(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 25 { return records.assetLocators.isEmpty }
        guard records.recordsSchemaVersion <= LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion else { return false }
        let keys = records.assetLocators.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return records.assetLocators.count <= 200_000
            && keys == keys.sorted()
            && Set(keys).count == keys.count
            && records.assetLocators.allSatisfy {
                $0.id != zero && $0.workspaceID != zero && $0.revision > 0
                    && $0.revision <= UInt64(Int.max) && !$0.canonicalData.isEmpty
            }
    }
    static func assetLocatorRecord(_ value: V26BackupAssetLocatorRecordV1) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision), !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
            "kind": .string(value.kind.rawValue),
            "revision": .integer(revision),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func validSchedules(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 26 { return records.schedules.isEmpty }
        guard (26...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.schedules.count <= 200_000 else { return false }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        let keys = records.schedules.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())" }
        let definitionRecords = records.schedules.filter { $0.kind == .scheduleRelease }
        let calendarRecords = records.schedules.filter { $0.kind == .exceptionCalendarRelease }
        let definitions = definitionRecords.compactMap {
            try? ScheduleCanonicalCodecV1.decode(
                ScheduleDefinitionReleaseV1.self, from: $0.canonicalData
            )
        }
        let calendars = calendarRecords.compactMap {
            try? ScheduleCanonicalCodecV1.decode(
                ExceptionCalendarReleaseV1.self, from: $0.canonicalData
            )
        }
        return C51ScheduleBackupClosureV1.validatesEnvelope(records.schedules)
            && definitions.count == definitionRecords.count
            && calendars.count == calendarRecords.count
            && C51ScheduleBackupClosureV1.validatesAdvancedCalendarReferences(
                definitions: definitions, calendars: calendars
            )
            && keys == keys.sorted()
            && Set(keys).count == keys.count
            && records.schedules.allSatisfy {
                $0.id != zero && $0.workspaceID != zero
                    && $0.revision > 0 && $0.revision <= UInt64(Int.max)
                    && !$0.canonicalData.isEmpty
            }
    }

    static func scheduleRecord(_ value: V27BackupScheduleRecordV1) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision), !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
            "kind": .string(value.kind.rawValue),
            "revision": .integer(revision),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func validPlans(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 27 { return records.plans.isEmpty }
        guard (27...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.plans.count <= PlanLimitsV1.maximumPlacements * 5,
              (try? PlanBackupRecordSetV1.decode(records.plans)) != nil else { return false }
        let keys = records.plans.map {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
        }
        return keys == keys.sorted() && Set(keys).count == keys.count
    }

    static func planRecord(_ value: V28BackupPlanRecordV1) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision),
              !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
            "kind": .string(value.kind.rawValue),
            "revision": .integer(revision),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func validPlacementPoses(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 28 { return records.placementPoses.isEmpty }
        guard (28...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.placementPoses.count <= PlacementPoseLimitsV1.maximumEventsPerClosure * 2,
              (try? PlacementPoseBackupRecordSetV1.decode(records.placementPoses)) != nil else {
            return false
        }
        let keys = records.placementPoses.map {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
        }
        return keys == keys.sorted() && Set(keys).count == keys.count
    }

    static func placementPoseRecord(
        _ value: V29BackupPlacementPoseRecordV1
    ) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision),
              !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
            "kind": .string(value.kind.rawValue),
            "revision": .integer(revision),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func validC30EvidenceContext(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 29 {
            return records.evidenceContexts.isEmpty && records.pairedObservationLinks.isEmpty
        }
        guard (29...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.evidenceContexts.allSatisfy({ $0.kind == .evidenceContext }),
              records.pairedObservationLinks.allSatisfy({ $0.kind == .pairedObservationLink }) else {
            return false
        }
        return (try? records.validateC30EvidenceContextClosure()) != nil
    }

    static func validC31Lighting(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 30 { return records.lighting.isEmpty }
        guard (30...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.lighting.count <= 100_000,
              records.lighting.allSatisfy({
                  $0.id != LightingLimitsV1.zero && $0.workspaceID != LightingLimitsV1.zero
                      && $0.revision > 0 && !$0.canonicalData.isEmpty
              }),
              (try? records.validateC31LightingClosure()) != nil else {
            return false
        }
        let keys = records.lighting.map {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
        }
        return keys == keys.sorted() && Set(keys).count == keys.count
    }

    static func validC32AssistanceAcceptanceReceipts(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 31 {
            return records.assistanceAcceptanceReceipts.isEmpty
        }
        guard (31...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.assistanceAcceptanceReceipts.count <= 100_000 else { return false }
        let keys = records.assistanceAcceptanceReceipts.map { $0.receiptID.uuidString.lowercased() }
        return keys == keys.sorted()
            && Set(keys).count == keys.count
            && (try? records.validateC32AssistanceAcceptanceReceipts()) != nil
    }

    static func assistanceAcceptanceReceiptRecord(
        _ value: V32BackupAssistanceAcceptanceRecordV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "mutationID": CanonicalJSONV1.uuid(value.mutationID),
            "proposalID": CanonicalJSONV1.uuid(value.proposalID),
            "receiptID": CanonicalJSONV1.uuid(value.receiptID),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func validC33TemporalEvidence(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 32 { return records.temporalEvidence.isEmpty }
        guard (32...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.temporalEvidence.count <= 200_000 else { return false }
        let keys = records.temporalEvidence.map {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
        }
        return keys == keys.sorted()
            && Set(keys).count == keys.count
            && (try? records.validateC33TemporalEvidence()) != nil
    }

    static func validC45AcceptedLabelSnapshots(_ records:V4BackupRecordsV1)->Bool {
        if records.recordsSchemaVersion < 33 { return records.acceptedLabelGenerationSnapshots.isEmpty }
        guard (33...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.acceptedLabelGenerationSnapshots.count <= 100_000 else { return false }
        let keys=records.acceptedLabelGenerationSnapshots.map{"\($0.workspaceID.uuidString.lowercased())|\($0.snapshotID.uuidString.lowercased())"}
        return keys==keys.sorted() && Set(keys).count==keys.count
            && (try? records.validateC45AcceptedLabelSnapshots()) != nil
    }


    static func validC45AcceptedLabelSemantic(_ records:V4BackupRecordsV1)->Bool {
        if records.recordsSchemaVersion < 33 { return records.acceptedLabelGenerationSnapshots.isEmpty }
        guard (33...LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.acceptedLabelGenerationSnapshots.count <= 100_000 else { return false }
        let keys=records.acceptedLabelGenerationSnapshots.map{"\($0.workspaceID.uuidString.lowercased())|\($0.snapshotID.uuidString.lowercased())"}
        let deleted=Set((records.deletionLedger?.entries ?? []).compactMap {
            $0.identity.kind == .acceptedLabelGenerationSnapshot ? $0.identity.id:nil
        })
        return keys==keys.sorted() && Set(keys).count==keys.count
            && Set(records.acceptedLabelGenerationSnapshots.map(\.snapshotID)).isDisjoint(with:deleted)
            && records.acceptedLabelGenerationSnapshots.allSatisfy{(try? $0.value()) != nil}
    }

    static func acceptedLabelSnapshotRecord(_ value:V34BackupAcceptedLabelSnapshotRecordV1)->CanonicalJSONValueV1 {
        .object(["canonicalData":.string(value.canonicalData.base64EncodedString()),"mutationID":CanonicalJSONV1.uuid(value.mutationID),"snapshotID":CanonicalJSONV1.uuid(value.snapshotID),"snapshotSHA256":.string(value.snapshotSHA256),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)])
    }

    static func operationalContactRecord(_ value: V35BackupOperationalContactRecordV1) -> CanonicalJSONValueV1 {
        .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
            "kind": .string(value.kind.rawValue),
            "mutationID": CanonicalJSONV1.uuid(value.mutationID),
            "revision": .number(String(value.revision)),
            "semanticSHA256": .string(value.semanticSHA256),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func validC46OperationalContacts(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < OperationalContactPersistenceEnrollmentV1.recordsSchemaVersion {
            return records.operationalContacts.isEmpty
        }
        guard (OperationalContactPersistenceEnrollmentV1.recordsSchemaVersion...
            LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.operationalContacts.count <= 200_000 else { return false }
        let keys = records.operationalContacts.map {
            "\($0.kind.rawValue)|\($0.workspaceID.uuidString.lowercased())|\($0.id.uuidString.lowercased())"
        }
        return keys == keys.sorted() && Set(keys).count == keys.count
            && (try? records.validateC46OperationalContacts()) != nil
    }

    static func activityContractRecord(_ value: V36BackupActivityContractRecordV2) -> CanonicalJSONValueV1 {
        // Keep the canonical payload and digest opaque here. In particular,
        // an unknown ActivityKindV2 is preserved inside canonicalData rather
        // than normalized through a closed writable-kind switch.
        .object([
            "activityID": CanonicalJSONV1.uuid(value.activityID),
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id), "kind": .string(value.kind.rawValue),
            "mutationID": CanonicalJSONV1.uuid(value.mutationID),
            "revision": .number(String(value.revision)),
            "semanticSHA256": .string(value.semanticSHA256),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func workResourceRecord(_ value: V37BackupWorkResourceRecordV1) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision) else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "entryID": CanonicalJSONV1.uuid(value.entryID),
            "entrySHA256": .string(value.entrySHA256),
            "mutationID": CanonicalJSONV1.uuid(value.mutationID),
            "revision": .integer(revision),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func serviceRequestRecord(_ value: V38BackupServiceRequestRecordV1) throws -> CanonicalJSONValueV1 {
        guard let revision=Int(exactly:value.revision) else{throw BackupCanonicalEncodingErrorV1.invalidRecords}
        var fields:[String:CanonicalJSONValueV1]=[
            "canonicalData":.string(value.canonicalData.base64EncodedString()),"mutationID":CanonicalJSONV1.uuid(value.mutationID),"recordID":CanonicalJSONV1.uuid(value.recordID),"recordSHA256":.string(value.recordSHA256),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)
        ]
        if let digest=value.acceptedSourceSHA256{fields["acceptedSourceSHA256"]=.string(digest)}
        return .object(fields)
    }

    static func serviceRequestDispositionRecord(_ value: V38BackupServiceRequestDispositionEventV1) throws -> CanonicalJSONValueV1 {
        guard let requestRevision=Int(exactly:value.requestRevision),let revision=Int(exactly:value.revision) else{throw BackupCanonicalEncodingErrorV1.invalidRecords}
        var fields:[String:CanonicalJSONValueV1]=[
            "canonicalData":.string(value.canonicalData.base64EncodedString()),"eventID":CanonicalJSONV1.uuid(value.eventID),"eventSHA256":.string(value.eventSHA256),"mutationID":CanonicalJSONV1.uuid(value.mutationID),"requestRecordID":CanonicalJSONV1.uuid(value.requestRecordID),"requestRevision":.integer(requestRevision),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)
        ]
        if let id=value.predecessorEventID{fields["predecessorEventID"]=CanonicalJSONV1.uuid(id)}
        if let digest=value.predecessorEventSHA256{fields["predecessorEventSHA256"]=.string(digest)}
        return .object(fields)
    }

    static func serviceRequestWorkLinkRecord(_ value: V38BackupServiceRequestWorkLinkEventV1) throws -> CanonicalJSONValueV1 {
        guard let requestRevision=Int(exactly:value.requestRevision),let workRevision=Int(exactly:value.canonicalWorkRevision),let revision=Int(exactly:value.revision) else{throw BackupCanonicalEncodingErrorV1.invalidRecords}
        var fields:[String:CanonicalJSONValueV1]=[
            "canonicalData":.string(value.canonicalData.base64EncodedString()),"canonicalWorkID":CanonicalJSONV1.uuid(value.canonicalWorkID),"canonicalWorkRevision":.integer(workRevision),"canonicalWorkSHA256":.string(value.canonicalWorkSHA256),"eventID":CanonicalJSONV1.uuid(value.eventID),"eventSHA256":.string(value.eventSHA256),"kind":.string(value.kind.rawValue),"mutationID":CanonicalJSONV1.uuid(value.mutationID),"requestRecordID":CanonicalJSONV1.uuid(value.requestRecordID),"requestRevision":.integer(requestRevision),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)
        ]
        if let id=value.reversesEventID{fields["reversesEventID"]=CanonicalJSONV1.uuid(id)}
        if let id=value.predecessorEventID{fields["predecessorEventID"]=CanonicalJSONV1.uuid(id)}
        if let digest=value.predecessorEventSHA256{fields["predecessorEventSHA256"]=.string(digest)}
        return .object(fields)
    }

    static func serviceReliabilityRecord(_ value: V39BackupServiceReliabilityRecordV1) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision) else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "eventID": CanonicalJSONV1.uuid(value.eventID),
            "eventSHA256": .string(value.eventSHA256),
            "incidentID": value.incidentID.map(CanonicalJSONV1.uuid) ?? .null,
            "kind": .string(value.kind.rawValue),
            "lineageID": CanonicalJSONV1.uuid(value.lineageID),
            "mutationID": CanonicalJSONV1.uuid(value.mutationID),
            "revision": .integer(revision),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func serviceReliabilityReceiptRecord(_ value: V39BackupServiceReliabilityReceiptRecordV1) throws -> CanonicalJSONValueV1 {
        .object([
            "bundleSHA256": .string(value.bundleSHA256),
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "mutationID": CanonicalJSONV1.uuid(value.mutationID),
        ])
    }

    static func validC53ServiceReliability(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < C53ServiceReliabilityBackupEncodingBoundaryV1.recordsSchemaVersion {
            return records.serviceReliabilityIncidents.isEmpty
                && records.serviceImpactSegments.isEmpty
                && records.serviceCauseAssertions.isEmpty
                && records.serviceRemedyAssertions.isEmpty
                && records.serviceRepairIntervals.isEmpty
                && records.serviceRestorationAssertions.isEmpty
                && records.qualifiedServiceExposures.isEmpty
                && records.serviceReliabilityReceipts.isEmpty
        }
        guard (C53ServiceReliabilityBackupEnrollmentV1.recordsSchemaVersion...
                ReinspectionExceptionQueueBackupEnrollmentV1.recordsSchemaVersion)
            .contains(records.recordsSchemaVersion) else {
            return false
        }
        return (try? C53ServiceReliabilityBackupEnrollmentV1.validate(records: records)) != nil
    }

    static func validC55PartsStock(_ records: V4BackupRecordsV1) -> Bool {
        (try? C55PartsStockBackupEnrollmentV1.validate(records)) != nil
    }

    static func validC04ShopReportProfiles(_ records: V4BackupRecordsV1) -> Bool {
        (try? C04ShopReportProfileBackupEnrollmentV1.validate(records)) != nil
    }

    static func validC05RoundSessions(_ records: V4BackupRecordsV1) -> Bool {
        (try? C05RoundSessionBackupEnrollmentV1.validate(records)) != nil
    }

    /// Semantic checkpoints carry the C47 current-state row families directly.
    /// Their journal-bound mutation history is intentionally absent, so this
    /// projection validates each canonical row and its transport identity.
    /// An unknown activity kind is an opaque read/export row: its canonical
    /// bytes and digest remain transportable, but it cannot infer a C47 family
    /// or enter the current-state graph. Full backup transport continues
    /// through `validC47ActivityContracts`, which retains the
    /// journal/reference closure and known-kind writable gate.
    static func validC47ActivityContractSemantic(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < C47ActivityContractPersistenceBoundaryV2.recordsSchemaVersion {
            return records.activityContracts.isEmpty
        }
        guard (C47ActivityContractPersistenceBoundaryV2.recordsSchemaVersion...
                LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.activityContracts.count <= 400_000 else { return false }
        let keys = records.activityContracts.map {
            "\($0.kind.rawValue)|\($0.workspaceID.uuidString.lowercased())|\($0.id.uuidString.lowercased())"
        }
        guard keys == keys.sorted() && Set(keys).count == keys.count else { return false }

        let envelopes: [ActivitySessionEnvelopeV2]
        let transitions: [ActivityStateTransitionV2]
        let taskResults: [InstallationTaskResultV1]
        let asBuiltSnapshots: [InstallationAsBuiltSnapshotV1]
        let punchBasisSnapshots: [PunchReviewBasisSnapshotV1]
        do {
            envelopes = try records.activityContracts
                .filter { $0.kind == .sessionEnvelope }
                .map { try $0.envelopeValue() }
            transitions = try records.activityContracts
                .filter { $0.kind == .stateTransition }
                .map { try $0.transitionValue() }
            taskResults = try records.activityContracts
                .filter { $0.kind == .installationTaskResult }
                .map { try $0.installationTaskResultValue() }
            asBuiltSnapshots = try records.activityContracts
                .filter { $0.kind == .installationAsBuiltSnapshot }
                .map { try $0.installationAsBuiltSnapshotValue() }
            punchBasisSnapshots = try records.activityContracts
                .filter { $0.kind == .punchReviewBasisSnapshot }
                .map { try $0.punchReviewBasisSnapshotValue() }
        } catch {
            return false
        }

        func activityKey(_ workspaceID: WorkspaceID, _ activityID: UUID) -> String {
            "\(workspaceID.rawValue.uuidString.lowercased())|\(activityID.uuidString.lowercased())"
        }

        guard envelopes.allSatisfy({
                  if case .unknown = $0.kind { return true }
                  return C47ActivityContractPersistenceBoundaryV2
                      .acceptsCanonicalRow(kind: $0.kind)
              }),
              Set(envelopes.map { activityKey($0.workspaceID, $0.activityID) }).count == envelopes.count,
              Set(envelopes.map(\.envelopeSHA256)).count == envelopes.count else {
            return false
        }
        let envelopeByActivity = Dictionary(uniqueKeysWithValues: envelopes.map {
            (activityKey($0.workspaceID, $0.activityID), $0)
        })

        // Every transition is historical state-change evidence for one current
        // envelope. The semantic projection has no predecessor envelope rows,
        // so it checks the available upper-bound/current-revision identity and
        // lets the full journal validator prove the complete transition chain.
        var transitionRevisionKeys = Set<String>()
        for transition in transitions {
            let key = activityKey(transition.workspaceID, transition.activityID)
            guard let envelope = envelopeByActivity[key],
                  envelope.kind == transition.kind,
                  transition.revision <= envelope.revision else {
                return false
            }
            if transition.revision == envelope.revision {
                guard transition.mutationID == envelope.mutationID else { return false }
            }
            guard transitionRevisionKeys.insert("\(key)|\(transition.revision)").inserted else {
                return false
            }
        }

        let taskResultsByActivity = Dictionary(grouping: taskResults) {
            activityKey($0.workspaceID, $0.activityID)
        }
        let transitionsByActivity = Dictionary(grouping: transitions) {
            activityKey($0.workspaceID, $0.activityID)
        }
        let asBuiltByActivity = Dictionary(grouping: asBuiltSnapshots) {
            activityKey($0.workspaceID, $0.activityID)
        }
        let punchBasisByActivity = Dictionary(grouping: punchBasisSnapshots) {
            activityKey($0.workspaceID, $0.activityID)
        }

        // Row families are intentionally disjoint. This catches an otherwise
        // validly encoded row that is attached to an envelope of the wrong
        // workflow family or to an absent envelope.
        guard taskResults.allSatisfy({
                  envelopeByActivity[activityKey($0.workspaceID, $0.activityID)]?.kind == .installation
              }),
              asBuiltSnapshots.allSatisfy({
                  envelopeByActivity[activityKey($0.workspaceID, $0.activityID)]?.kind == .installation
              }),
              punchBasisSnapshots.allSatisfy({
                  envelopeByActivity[activityKey($0.workspaceID, $0.activityID)]?.kind == .punchReview
              }) else {
            return false
        }

        // Task rows are a persisted lineage, not a journal sidecar. Rebuild
        // each activity's current task heads so as-built references can be
        // resolved without requiring mutation history.
        var taskHeadsByActivity: [String: [String: InstallationTaskResultV1]] = [:]
        for (key, values) in taskResultsByActivity {
            guard let heads = try? InstallationTaskResultLineageV1
                .validateAndCurrentHeads(values) else {
                return false
            }
            taskHeadsByActivity[key] = heads
        }

        // Punch basis rows carry their own predecessor references, so their
        // current head can be proved directly from the semantic projection.
        var punchHeadsByActivity: [String: PunchReviewBasisSnapshotV1] = [:]
        for (key, values) in punchBasisByActivity {
            let ordered = values.sorted {
                if $0.revision != $1.revision { return $0.revision < $1.revision }
                return $0.basisID.uuidString.lowercased() < $1.basisID.uuidString.lowercased()
            }
            guard Set(ordered.map(\.basisID)).count == ordered.count,
                  Set(ordered.map(\.basisSHA256)).count == ordered.count else {
                return false
            }
            for (index, value) in ordered.enumerated() {
                guard (try? value.validate()) != nil else { return false }
                if index == 0 {
                    guard value.revision == 1,
                          value.predecessorBasisID == nil,
                          value.predecessorBasisSHA256 == nil else {
                        return false
                    }
                } else {
                    guard (try? value.validateSuccessor(of: ordered[index - 1])) != nil else {
                        return false
                    }
                }
            }
            guard let head = ordered.last else { return false }
            punchHeadsByActivity[key] = head
        }

        // Resolve the current-state graph against the one envelope per
        // workspace/activity. Installation basis snapshots are journal-owned
        // and are not in the C47 records envelope; when an as-built row is
        // present, its basis reference is the available installation basis
        // head and must match the envelope's current reference.
        for envelope in envelopes {
            let key = activityKey(envelope.workspaceID, envelope.activityID)
            let activityTasks = taskResultsByActivity[key] ?? []
            let activityTaskHeads = taskHeadsByActivity[key] ?? [:]
            let activityTransitions = transitionsByActivity[key] ?? []
            let activityAsBuilt = asBuiltByActivity[key] ?? []
            let activityPunchHead = punchHeadsByActivity[key]

            switch envelope.kind {
            case .installation:
                guard activityPunchHead == nil,
                      punchBasisByActivity[key] == nil,
                      activityAsBuilt.count <= 1,
                      activityAsBuilt.allSatisfy({
                          $0.workspaceID == envelope.workspaceID
                              && $0.activityID == envelope.activityID
                      }) else {
                    return false
                }
                if let asBuilt = activityAsBuilt.first {
                    guard case let .installation(reference)? = envelope.currentBasisReference,
                          reference == asBuilt.basisReference,
                          let closeout = envelope.installationCloseout,
                          closeout.asBuiltSnapshotSHA256 == asBuilt.snapshotSHA256,
                          closeout.completion == asBuilt.completion,
                          Set(asBuilt.taskResultSHA256s)
                              == Set(activityTaskHeads.values.map(\.resultSHA256)) else {
                        return false
                    }
                } else {
                    guard envelope.installationCloseout == nil else { return false }
                }
                if envelope.currentBasisReference == nil {
                    guard activityTasks.isEmpty,
                          envelope.state == .draft || envelope.state == .preflightRequired else {
                        return false
                    }
                } else {
                    guard let currentBasisReference = envelope.currentBasisReference,
                          case .installation = currentBasisReference else { return false }
                }

            case .punchReview:
                guard activityTasks.isEmpty,
                      activityTaskHeads.isEmpty,
                      activityAsBuilt.isEmpty,
                      envelope.installationCloseout == nil else {
                    return false
                }
                if let punchHead = activityPunchHead {
                    guard case let .punchReview(reference)? = envelope.currentBasisReference,
                          reference.workspaceID == punchHead.workspaceID,
                          reference.activityID == punchHead.activityID,
                          reference.basisID == punchHead.basisID,
                          reference.revision == punchHead.revision,
                          reference.basisSHA256 == punchHead.basisSHA256 else {
                        return false
                    }
                    if let closeout = envelope.punchReviewCloseout {
                        guard closeout.basisSHA256 == punchHead.basisSHA256 else { return false }
                    }
                } else {
                    guard envelope.currentBasisReference == nil,
                          envelope.punchReviewCloseout == nil,
                          envelope.state == .draft || envelope.state == .preflightRequired else {
                        return false
                    }
                }

            case .unknown:
                // Unknown kinds are read/export-only. They must remain an
                // opaque envelope and may not acquire a known-family row,
                // transition, basis, or closeout through inference.
                guard activityTransitions.isEmpty,
                      activityTasks.isEmpty,
                      activityAsBuilt.isEmpty,
                      activityPunchHead == nil,
                      punchBasisByActivity[key] == nil,
                      envelope.readinessPolicy == nil,
                      envelope.currentBasisReference == nil,
                      envelope.installationCloseout == nil,
                      envelope.punchReviewCloseout == nil else {
                    return false
                }

            case .inspection, .survey, .preventiveMaintenance, .repair,
                 .operationalRecheck:
                return false
            }
        }
        return true
    }

    static func validC47ActivityContracts(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < C47ActivityContractPersistenceBoundaryV2.recordsSchemaVersion {
            return records.activityContracts.isEmpty
        }
        guard (C47ActivityContractPersistenceBoundaryV2.recordsSchemaVersion...
                LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion).contains(records.recordsSchemaVersion),
              records.activityContracts.count <= 400_000 else { return false }
        let keys = records.activityContracts.map {
            "\($0.kind.rawValue)|\($0.workspaceID.uuidString.lowercased())|\($0.id.uuidString.lowercased())"
        }
        return keys == keys.sorted() && Set(keys).count == keys.count
            && (try? records.validateC47ActivityContracts()) != nil
    }

    static func validC49WorkResources(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < C49BackupEnrollmentV1.recordsSchemaVersion {
            return records.workResources.isEmpty
        }
        return records.recordsSchemaVersion <= LightingDayInventoryBackupEnrollmentV1.recordsSchemaVersion
            && records.workResources.count <= WorkResourcePersistenceLimitsV1.maximumSnapshotRows
            && (try? records.validateC49WorkResources()) != nil
    }

    static func temporalEvidenceRecord(
        _ value: V33BackupTemporalEvidenceRecordV1
    ) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision), revision > 0,
              !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
            "kind": .string(value.kind.rawValue),
            "mutationID": CanonicalJSONV1.uuid(value.mutationID),
            "revision": .integer(revision),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func evidenceContextRecord(
        _ value: V30BackupEvidenceContextRecordV1
    ) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision),
              !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
            "kind": .string(value.kind.rawValue),
            "revision": .integer(revision),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func lightingRecord(
        _ value: V31BackupLightingRecordV1
    ) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision),
              value.id != LightingLimitsV1.zero,
              value.workspaceID != LightingLimitsV1.zero,
              !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
            "kind": .string(value.kind.rawValue),
            "revision": .integer(revision),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func lightingDayInventoryRecord(
        _ value: V52BackupLightingDayInventoryRecordV1
    ) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision), revision > 0,
              !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
            "kind": .string(value.kind.rawValue),
            "revision": .integer(revision),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func lightingNightWorkflowRecord(
        _ value: V53BackupLightingNightWorkflowRecordV1
    ) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision), revision > 0,
              !value.canonicalData.isEmpty else { throw BackupCanonicalEncodingErrorV1.invalidRecords }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id), "kind": .string(value.kind.rawValue),
            "revision": .integer(revision), "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func privacyTransformRecord(_ value: V19BackupPrivacyTransformRecordV1) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision), !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id), "kind": .string(value.kind.rawValue),
            "revision": .integer(revision), "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func measurementIntegrityRecord(_ value: V18BackupMeasurementIntegrityRecordV1) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision), !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id), "kind": .string(value.kind.rawValue),
            "revision": .integer(revision), "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func fieldDraftRecord(_ value: V16BackupFieldDraftRecordV1) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision), !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id), "kind": .string(value.kind.rawValue),
            "revision": .integer(revision), "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func packageEvolutionRecord(_ value: V17BackupPackageEvolutionRecordV1) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision), !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": .string(value.id.uuidString.lowercased()),
            "kind": .string(value.kind.rawValue),
            "revision": .integer(revision),
            "workspaceID": .string(value.workspaceID.uuidString.lowercased())
        ])
    }

    static func workPacketRecord(_ value: V15BackupWorkPacketRecordV1) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision), !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id), "kind": .string(value.kind.rawValue),
            "revision": .integer(revision), "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func inspectionReviewRecord(
        _ value: V14BackupInspectionReviewRecordV1
    ) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision), !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id), "kind": .string(value.kind.rawValue),
            "revision": .integer(revision), "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func evidenceAssuranceRecord(
        _ value: V13BackupEvidenceAssuranceRecordV1
    ) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision), !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id), "kind": .string(value.kind.rawValue),
            "revision": .integer(revision), "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func functionalRelationshipRecord(
        _ value: V12BackupFunctionalRelationshipRecordV1
    ) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision), !value.canonicalData.isEmpty else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
            "kind": .string(value.kind.rawValue),
            "revision": .integer(revision),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func authorityCriterionRecord(
        _ value: V11BackupAuthorityCriterionRecordV1
    ) throws -> CanonicalJSONValueV1 {
        guard !value.canonicalData.isEmpty else { throw BackupCanonicalEncodingErrorV1.invalidRecords }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
            "kind": .string(value.kind.rawValue),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func assetSemanticRecord(
        _ value: V10BackupAssetSemanticRecordV1
    ) throws -> CanonicalJSONValueV1 {
        guard let revision = Int(exactly: value.revision) else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
            "kind": .string(value.kind.rawValue),
            "revision": .integer(revision),
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func partyAccountabilityRecord(
        _ value: V9BackupPartyAccountabilityRecordV1
    ) throws -> CanonicalJSONValueV1 {
        let revision: CanonicalJSONValueV1
        if let rawRevision = value.revision {
            guard let exactRevision = Int(exactly: rawRevision) else {
                throw BackupCanonicalEncodingErrorV1.invalidRecords
            }
            revision = .integer(exactRevision)
        } else {
            revision = .null
        }
        return .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
            "kind": .string(value.kind.rawValue),
            "revision": revision,
            "workspaceID": CanonicalJSONV1.uuid(value.workspaceID),
        ])
    }

    static func requirementAssuranceRecord(
        _ value: V8BackupRequirementAssuranceRecordV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "createdAt": CanonicalJSONV1.date(value.createdAt),
            "mutationID": CanonicalJSONV1.uuid(value.mutationID),
            "snapshotSHA256": .string(value.snapshotSHA256),
            "updatedAt": CanonicalJSONV1.date(value.updatedAt),
            "workflowRecordID": CanonicalJSONV1.uuid(value.workflowRecordID),
        ])
    }

    static func locationRecord(_ value: V5BackupLocationRecordV1) -> CanonicalJSONValueV1 {
        var fields: [String: CanonicalJSONValueV1] = [
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
        ]
        if let secondary = value.secondaryCanonicalData {
            fields["secondaryCanonicalData"] = .string(secondary.base64EncodedString())
        }
        return .object(fields)
    }

    static func savedSmartViewRecord(
        _ value: V7BackupSavedSmartViewRecordV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "canonicalData": .string(value.canonicalData.base64EncodedString()),
            "id": CanonicalJSONV1.uuid(value.id),
        ])
    }

    static func valid(_ manifest: V4BackupManifestV1) -> Bool {
        let zero = UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        ))
        let sourceIdentityIsValid: Bool
        switch (
            manifest.backupSchemaVersion,
            manifest.source.workspaceID,
            manifest.source.replicaID
        ) {
        case (1, nil, nil):
            sourceIdentityIsValid = true
        case (2, let workspaceID?, let replicaID?),
             (3, let workspaceID?, let replicaID?),
             (4, let workspaceID?, let replicaID?):
            sourceIdentityIsValid = workspaceID != zero
                && replicaID != zero
                && workspaceID != replicaID
        default:
            sourceIdentityIsValid = false
        }
        let sourceGenerationIsValid: Bool
        if manifest.source.recordsSchemaVersion >= 5 {
            sourceGenerationIsValid = manifest.source.sourceGenerationID.map {
                $0 != zero && $0 != manifest.source.workspaceID
                    && $0 != manifest.source.replicaID
            } ?? false
        } else {
            sourceGenerationIsValid = manifest.source.sourceGenerationID == nil
        }
        let schemaPairIsValid: Bool
        switch (
            manifest.backupSchemaVersion,
            manifest.source.persistentSchemaVersion,
            manifest.source.recordsSchemaVersion
        ) {
        case (1, 1, 1), (2, 1, 1), (2, 3, 2), (3, 4, 3),
             (4, 5, 4), (4, 6, 5), (4, 7, 6), (4, 8, 7), (4, 9, 8),
             (4, 10, 9), (4, 11, 10), (4, 12, 11), (4, 13, 12), (4, 14, 13), (4, 15, 14), (4, 16, 15), (4, 17, 16), (4, 18, 17), (4, 19, 18), (4, 20, 19), (4, 21, 20), (4, 22, 21), (4, 23, 22), (4, 24, 23), (4, 25, 24), (4, 26, 25), (4, 27, 26), (4, 28, 27), (4, 29, 28), (4, 30, 29), (4, 31, 30), (4, 32, 31), (4, 33, 32), (4, 34, 33), (4, 35, 34), (4, 36, 35):
            schemaPairIsValid = true
        default:
            schemaPairIsValid = false
        }
        guard sourceIdentityIsValid, sourceGenerationIsValid,
              schemaPairIsValid,
              manifest.declaredPayloadByteCount >= 0,
              !manifest.source.appBuild.isEmpty,
              !manifest.source.appVersion.isEmpty,
              sortedUniqueIDs(manifest.consumedEvaluationRootIDs),
              manifest.entries == manifest.entries.sorted(by: { $0.path < $1.path }),
              Set(manifest.entries.map(\.path)).count == manifest.entries.count,
              manifest.entries.allSatisfy(validEntry),
              manifest.entries.filter({ $0.path == "records.json" }).count == 1,
              manifest.packs == manifest.packs.sorted(by: packOrder),
              manifest.packs.allSatisfy({
                  !$0.packID.isEmpty && $0.schemaVersion > 0 && $0.contentVersion > 0
              }),
              Set(manifest.packs.map(packIdentity)).count == manifest.packs.count else {
            return false
        }
        var total = 0
        for value in manifest.entries.map(\.byteCount) {
            let (next, overflow) = total.addingReportingOverflow(value)
            guard !overflow else { return false }
            total = next
        }
        return total == manifest.declaredPayloadByteCount
    }

    static func sortedUniqueIDs(_ values: [UUID]) -> Bool {
        let strings = values.map { $0.uuidString.lowercased() }
        return Set(values).count == values.count && strings == strings.sorted()
    }

    static func validEntry(_ value: V4BackupEntryV1) -> Bool {
        guard value.byteCount >= 0,
              isLowercaseSHA256(value.sha256),
              value.path == value.path.precomposedStringWithCanonicalMapping else {
            return false
        }
        switch pathKind(value.path) {
        case .records:
            return value.mimeType == "application/json"
        case .media, .thumbnail:
            return value.mimeType == "image/jpeg"
        case .snapshot:
            return value.mimeType == "application/json"
        case .pdf:
            return value.mimeType == "application/pdf"
        case nil:
            return false
        }
    }

    enum PathKind { case records, media, thumbnail, snapshot, pdf }

    static func pathKind(_ path: String) -> PathKind? {
        if path == "records.json" { return .records }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 2 else { return nil }
        switch components[0] {
        case "media":
            return canonicalUUIDFilename(components[1], pathExtension: "jpg") ? .media : nil
        case "thumbnails":
            return canonicalUUIDFilename(components[1], pathExtension: "jpg") ? .thumbnail : nil
        case "snapshots":
            return canonicalUUIDFilename(components[1], pathExtension: "json") ? .snapshot : nil
        case "pdfs":
            return canonicalUUIDFilename(components[1], pathExtension: "pdf") ? .pdf : nil
        default:
            return nil
        }
    }

    static func canonicalUUIDFilename(_ filename: String, pathExtension value: String) -> Bool {
        let suffix = ".\(value)"
        guard filename.hasSuffix(suffix),
              let id = UUID(uuidString: String(filename.dropLast(suffix.count))) else {
            return false
        }
        return id.uuidString.lowercased() + suffix == filename
    }

    static func packOrder(_ lhs: V4BackupPackV1, _ rhs: V4BackupPackV1) -> Bool {
        if lhs.packID != rhs.packID { return lhs.packID < rhs.packID }
        if lhs.schemaVersion != rhs.schemaVersion {
            return lhs.schemaVersion < rhs.schemaVersion
        }
        return lhs.contentVersion < rhs.contentVersion
    }

    static func packIdentity(_ value: V4BackupPackV1) -> String {
        "\(value.packID)\u{0}\(value.schemaVersion)\u{0}\(value.contentVersion)"
    }

    static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    static func site(_ value: V4BackupSiteDTO) -> CanonicalJSONValueV1 {
        .object([
            "address": CanonicalJSONV1.optionalString(value.address),
            "createdAt": CanonicalJSONV1.date(value.createdAt),
            "id": CanonicalJSONV1.uuid(value.id),
            "label": .string(value.label),
            "schemaVersion": .integer(value.schemaVersion),
            "timeZoneID": CanonicalJSONV1.optionalString(value.timeZoneID),
            "updatedAt": CanonicalJSONV1.date(value.updatedAt),
        ])
    }

    static func asset(_ value: V4BackupAssetDTO) -> CanonicalJSONValueV1 {
        .object([
            "createdAt": CanonicalJSONV1.date(value.createdAt),
            "id": CanonicalJSONV1.uuid(value.id),
            "label": .string(value.label),
            "packContentVersion": .integer(value.packContentVersion),
            "packID": .string(value.packID),
            "packSchemaVersion": .integer(value.packSchemaVersion),
            "schemaVersion": .integer(value.schemaVersion),
            "siteID": CanonicalJSONV1.uuid(value.siteID),
            "updatedAt": CanonicalJSONV1.date(value.updatedAt),
        ])
    }

    static func workflowRecord(
        _ value: V4BackupWorkflowRecordDTO,
        includeObservationAndTime: Bool
    ) -> CanonicalJSONValueV1 {
        var fields: [String: CanonicalJSONValueV1] = [
            "afterDarkAcknowledgementAccepted": CanonicalJSONV1.optionalBool(value.afterDarkAcknowledgementAccepted),
            "afterDarkAcknowledgementCopy": CanonicalJSONV1.optionalString(value.afterDarkAcknowledgementCopy),
            "afterDarkAcknowledgementKey": CanonicalJSONV1.optionalString(value.afterDarkAcknowledgementKey),
            "afterDarkAcknowledgementVersion": CanonicalJSONV1.optionalString(value.afterDarkAcknowledgementVersion),
            "assetID": CanonicalJSONV1.uuid(value.assetID),
            "completedAt": CanonicalJSONV1.optionalDate(value.completedAt),
            "couldNotVerifyDisplaySnapshot": CanonicalJSONV1.optionalString(value.couldNotVerifyDisplaySnapshot),
            "couldNotVerifyKey": CanonicalJSONV1.optionalString(value.couldNotVerifyKey),
            "couldNotVerifyRegistryVersion": CanonicalJSONV1.optionalString(value.couldNotVerifyRegistryVersion),
            "draftStepKey": CanonicalJSONV1.optionalString(value.draftStepKey),
            "evidenceSourceRecordID": CanonicalJSONV1.optionalUUID(value.evidenceSourceRecordID),
            "finalizationMutationID": CanonicalJSONV1.optionalUUID(value.finalizationMutationID),
            "id": CanonicalJSONV1.uuid(value.id),
            "issueID": CanonicalJSONV1.optionalUUID(value.issueID),
            "localDate": CanonicalJSONV1.optionalString(value.localDate),
            "localTime": CanonicalJSONV1.optionalString(value.localTime),
            "note": CanonicalJSONV1.optionalString(value.note),
            "observedAtUTC": CanonicalJSONV1.optionalDate(value.observedAtUTC),
            "outcomeKey": CanonicalJSONV1.optionalString(value.outcomeKey),
            "packContentVersion": .integer(value.packContentVersion),
            "packID": .string(value.packID),
            "packSchemaVersion": .integer(value.packSchemaVersion),
            "packetID": CanonicalJSONV1.optionalUUID(value.packetID),
            "parentRecordID": CanonicalJSONV1.optionalUUID(value.parentRecordID),
            "pdfTemplateID": .string(value.pdfTemplateID),
            "pdfTemplateVersion": .integer(value.pdfTemplateVersion),
            "recordRevisionRootID": CanonicalJSONV1.uuid(value.recordRevisionRootID),
            "revisesRecordID": CanonicalJSONV1.optionalUUID(value.revisesRecordID),
            "revisionKind": .string(value.revisionKind),
            "safePositionAcknowledgementAccepted": CanonicalJSONV1.optionalBool(value.safePositionAcknowledgementAccepted),
            "safePositionAcknowledgementCopy": CanonicalJSONV1.optionalString(value.safePositionAcknowledgementCopy),
            "safePositionAcknowledgementKey": CanonicalJSONV1.optionalString(value.safePositionAcknowledgementKey),
            "safePositionAcknowledgementVersion": CanonicalJSONV1.optionalString(value.safePositionAcknowledgementVersion),
            "schemaVersion": .integer(value.schemaVersion),
            "stage": .string(value.stage),
            "startedAt": CanonicalJSONV1.date(value.startedAt),
            "state": .string(value.state),
            "timeZoneID": CanonicalJSONV1.optionalString(value.timeZoneID),
            "utcOffsetMinutes": CanonicalJSONV1.optionalInteger(value.utcOffsetMinutes),
            "workDescription": CanonicalJSONV1.optionalString(value.workDescription),
            "workPerformedLocalDate": CanonicalJSONV1.optionalString(value.workPerformedLocalDate),
        ]
        if includeObservationAndTime {
            fields["observationBasisV1Data"] = value.observationBasisV1Data
                .map { .string($0.base64EncodedString()) } ?? .null
            fields["temporalContextV1Data"] = value.temporalContextV1Data
                .map { .string($0.base64EncodedString()) } ?? .null
        }
        return .object(fields)
    }

    static func evidenceFile(_ value: V4BackupEvidenceFileDTO) -> CanonicalJSONValueV1 {
        .object([
            "byteCount": .integer(value.byteCount),
            "createdAt": CanonicalJSONV1.date(value.createdAt),
            "id": CanonicalJSONV1.uuid(value.id),
            "mimeType": .string(value.mimeType),
            "purposeKey": .string(value.purposeKey),
            "recordID": CanonicalJSONV1.uuid(value.recordID),
            "relativePath": .string(value.relativePath),
            "schemaVersion": .integer(value.schemaVersion),
            "sha256": .string(value.sha256),
            "thumbnailByteCount": .integer(value.thumbnailByteCount),
            "thumbnailRelativePath": .string(value.thumbnailRelativePath),
            "thumbnailSHA256": .string(value.thumbnailSHA256),
        ])
    }

    static func issue(_ value: V4BackupIssueDTO) -> CanonicalJSONValueV1 {
        .object([
            "assetID": CanonicalJSONV1.uuid(value.assetID),
            "createdAt": CanonicalJSONV1.date(value.createdAt),
            "id": CanonicalJSONV1.uuid(value.id),
            "labelDisplaySnapshot": .string(value.labelDisplaySnapshot),
            "labelKey": .string(value.labelKey),
            "openedByRecordID": CanonicalJSONV1.uuid(value.openedByRecordID),
            "resolvedByRecordID": CanonicalJSONV1.optionalUUID(value.resolvedByRecordID),
            "schemaVersion": .integer(value.schemaVersion),
            "status": .string(value.status),
            "updatedAt": CanonicalJSONV1.date(value.updatedAt),
        ])
    }

    static func packet(_ value: V4BackupPacketDTO) -> CanonicalJSONValueV1 {
        .object([
            "contentDeletedAt": CanonicalJSONV1.optionalDate(value.contentDeletedAt),
            "createdAt": CanonicalJSONV1.date(value.createdAt),
            "currentRecordID": CanonicalJSONV1.optionalUUID(value.currentRecordID),
            "evaluationCounted": .bool(value.evaluationCounted),
            "id": CanonicalJSONV1.uuid(value.id),
            "schemaVersion": .integer(value.schemaVersion),
            "stableRootID": CanonicalJSONV1.uuid(value.stableRootID),
        ])
    }

    static func report(_ value: V4BackupReportDTO) -> CanonicalJSONValueV1 {
        .object([
            "createdAt": CanonicalJSONV1.date(value.createdAt),
            "id": CanonicalJSONV1.uuid(value.id),
            "packetID": CanonicalJSONV1.uuid(value.packetID),
            "pdfRelativePath": CanonicalJSONV1.optionalString(value.pdfRelativePath),
            "pdfSHA256": CanonicalJSONV1.optionalString(value.pdfSHA256),
            "pdfState": .string(value.pdfState),
            "replacesReportID": CanonicalJSONV1.optionalUUID(value.replacesReportID),
            "schemaVersion": .integer(value.schemaVersion),
            "snapshotRelativePath": .string(value.snapshotRelativePath),
            "snapshotSHA256": .string(value.snapshotSHA256),
            "snapshotSchemaVersion": .integer(value.snapshotSchemaVersion),
            "sourceRecordID": CanonicalJSONV1.uuid(value.sourceRecordID),
        ])
    }

    static func entry(_ value: V4BackupEntryV1) -> CanonicalJSONValueV1 {
        .object([
            "byteCount": .integer(value.byteCount),
            "mimeType": .string(value.mimeType),
            "path": .string(value.path),
            "sha256": .string(value.sha256),
        ])
    }

    static func pack(_ value: V4BackupPackV1) -> CanonicalJSONValueV1 {
        .object([
            "contentVersion": .integer(value.contentVersion),
            "packID": .string(value.packID),
            "schemaVersion": .integer(value.schemaVersion),
        ])
    }

    static func deletionLedger(_ value: DeletionLedgerV2) -> CanonicalJSONValueV1 {
        .object([
            "entries": .array(value.entries.map(deletionLedgerEntry)),
            "schemaVersion": .integer(value.schemaVersion),
        ])
    }

    static func deletionLedgerEntry(
        _ value: DeletionLedgerEntryV2
    ) -> CanonicalJSONValueV1 {
        .object([
            "deletedAt": CanonicalJSONV1.date(value.deletedAt),
            "identity": .object([
                "id": CanonicalJSONV1.uuid(value.identity.id),
                "kind": .string(value.identity.kind.rawValue),
            ]),
            "schemaVersion": .integer(value.schemaVersion),
        ])
    }

    static func mutationHistory(
        _ value: MutationHistorySnapshotV1
    ) throws -> CanonicalJSONValueV1 {
        guard validMutationHistoryOrder(value),
              value.workspaceRevision <= UInt64(Int.max),
              value.lastLocalSequence <= UInt64(Int.max) else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return .object([
            "entityRevisions": .array(value.entityRevisions.map {
                var fields: [String: CanonicalJSONValueV1] = [
                    "identity": .object([
                        "id": CanonicalJSONV1.uuid($0.identity.id),
                        "kind": .string($0.identity.kind.rawValue),
                    ]),
                    "revision": .integer(Int($0.revision)),
                ]
                if let digest = $0.externalProjectionSHA256 {
                    fields["externalProjectionSHA256"] = .string(digest)
                }
                return .object(fields)
            }),
            "lastLocalSequence": .integer(Int(value.lastLocalSequence)),
            "quarantines": .array(value.quarantines.map {
                .object([
                    "acceptedIdentitySHA256": .string(
                        $0.acceptedIdentitySHA256
                    ),
                    "conflictingIdentitySHA256": .string(
                        $0.conflictingIdentitySHA256
                    ),
                    "detectedAt": CanonicalJSONV1.date($0.detectedAt),
                    "identityDomain": .string($0.identityDomain.rawValue),
                    "mutationID": CanonicalJSONV1.uuid($0.mutationID),
                    "workspaceID": CanonicalJSONV1.uuid(
                        $0.workspaceID.rawValue
                    ),
                ])
            }),
            "receipts": .array(value.receipts.map(mutationReceiptRecord)),
            "schemaVersion": .integer(value.schemaVersion),
            "workspaceRevision": .integer(Int(value.workspaceRevision)),
        ])
    }

    static func mutationReceiptRecord(
        _ value: MutationHistoryReceiptRecordV1
    ) -> CanonicalJSONValueV1 {
        var fields: [String: CanonicalJSONValueV1] = [
            "envelopeData": .string(value.envelopeData.base64EncodedString()),
            "receiptData": .string(value.receiptData.base64EncodedString()),
        ]
        if let reversalBasisData = value.reversalBasisData {
            fields["reversalBasisData"] = .string(
                reversalBasisData.base64EncodedString()
            )
        }
        if let semanticReversalData = value.semanticReversalData {
            fields["semanticReversalData"] = .string(
                semanticReversalData.base64EncodedString()
            )
        }
        return .object(fields)
    }

    static func validMutationHistoryOrder(
        _ value: MutationHistorySnapshotV1
    ) -> Bool {
        guard value.schemaVersion == MutationHistorySnapshotV1.schemaVersion,
              value.receipts.count
                <= MutationJournalStoreV1.maximumReceiptValidationCount,
              value.quarantines.count
                <= MutationJournalStoreV1.maximumReceiptValidationCount,
              value.entityRevisions.count
                <= MutationJournalStoreV1.maximumImportedEntityRevisionValidationCount,
              value.workspaceRevision <= UInt64(Int.max),
              value.lastLocalSequence <= UInt64(Int.max),
              value.entityRevisions.allSatisfy({
                  $0.revision > 0
                    && $0.revision <= UInt64(Int.max)
                    && $0.externalProjectionSHA256.map {
                        validSHA256($0)
                    } != false
              }),
              value.quarantines.allSatisfy({
                  validSHA256($0.acceptedIdentitySHA256)
                    && validSHA256($0.conflictingIdentitySHA256)
                    && $0.acceptedIdentitySHA256
                        != $0.conflictingIdentitySHA256
                    && validDate($0.detectedAt)
              }) else {
            return false
        }
        let receiptKeys: [String]
        do {
            receiptKeys = try value.receipts.map {
                try MutationReceiptV1.decodeCanonical(from: $0.receiptData)
                    .identity.stableKey
            }
        } catch {
            return false
        }
        let quarantineKeys = value.quarantines.map {
            "\($0.workspaceID.rawValue.uuidString.lowercased()):\($0.mutationID.uuidString.lowercased())"
        }
        let revisionKeys = value.entityRevisions.map(\.identity.stableKey)
        return receiptKeys == receiptKeys.sorted()
            && Set(receiptKeys).count == receiptKeys.count
            && quarantineKeys == quarantineKeys.sorted()
            && Set(quarantineKeys).count == quarantineKeys.count
            && revisionKeys == revisionKeys.sorted()
            && Set(revisionKeys).count == revisionKeys.count
    }

    static func validSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains(Int($0.value))
                || (97...102).contains(Int($0.value))
        }
    }

    static func validDate(_ value: Date) -> Bool {
        value.timeIntervalSinceReferenceDate.isFinite
    }

    static func source(_ value: V4BackupSourceV1) -> CanonicalJSONValueV1 {
        var fields: [String: CanonicalJSONValueV1] = [
            "appBuild": .string(value.appBuild),
            "appVersion": .string(value.appVersion),
            "persistentSchemaVersion": .integer(value.persistentSchemaVersion),
            "recordsSchemaVersion": .integer(value.recordsSchemaVersion),
        ]
        if let replicaID = value.replicaID,
           let workspaceID = value.workspaceID {
            fields["replicaID"] = CanonicalJSONV1.uuid(replicaID)
            fields["workspaceID"] = CanonicalJSONV1.uuid(workspaceID)
        }
        if let sourceGenerationID = value.sourceGenerationID {
            fields["sourceGenerationID"] = CanonicalJSONV1.uuid(sourceGenerationID)
        }
        return .object(fields)
    }
}

enum C45AcceptedLabelBackupEncoderBoundaryV1 { static let encodesCanonicalSnapshotBytes=true;static let encodesProjectionBytes=false }
// C52_BOUNDARY_ANCHOR: canonical-service-request-backup
enum C52ServiceRequestBackupEncodingBoundaryV1 {
    static let recordsSchemaVersion = 38
    static let families = ServiceRequestPersistenceEnrollmentV1.durableFamilies
    static let canonicalOrdering = ["workspaceID", "recordOrEventID", "revision"]
    static let rawCapabilityEncoded = false
    static let duplicateProjectionEncoded = false
}

enum C53ServiceReliabilityBackupEncodingBoundaryV1 {
    /// C53 rows remain canonical in the active C12 envelope; this upper
    /// boundary advances with the current records schema, not their origin.
    static let recordsSchemaVersion = ReinspectionExceptionQueueBackupEnrollmentV1.recordsSchemaVersion
    static let persistentSchemaVersion = AssetServiceReliabilityPersistenceEnrollmentV1.targetPersistentSchemaVersion
    static let durableFamilyCount = AssetServiceReliabilityPersistenceEnrollmentV1.durableFamilies.count
    static let canonicalOrdering = ["kind", "workspaceID", "lineageID", "revision", "eventID"]
    static let rawCapabilityEncoded = false
    static let derivedProjectionEncoded = false
    static let sourceHistoryIsAppendOnly = true
}

enum C55PartsStockBackupEncodingBoundaryV1 {
    static let recordsSchemaVersion = C55PartsStockBackupEnrollmentV1.recordsSchemaVersion
    static let persistentSchemaVersion = C55PartsStockBackupEnrollmentV1.persistentSchemaVersion
    static let durableFamilyCount = C55PartsStockBackupEnrollmentV1.durableFamilyCount
    static let canonicalSnapshotIsEmbedded = true
    static let parallelEnvelopeIsForbidden = true
}
// C05_BOUNDARY_ANCHOR: canonical-identity-backup-encoder
enum V30P01C05BackupEncoderCanonicalIdentityBoundaryV1 {
    static let encoderUsesCanonicalRecordOrder = true
    static let encoderBytesIgnorePresentationLocale = true
    static let translatedLabelsAreExcluded = true
    static let historicalEnUSIdentityIsEncodedVerbatim = true

    static func validate() -> Bool {
        encoderUsesCanonicalRecordOrder
            && encoderBytesIgnorePresentationLocale
            && translatedLabelsAreExcluded
            && historicalEnUSIdentityIsEncodedVerbatim
    }
}
