import Foundation

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
        guard Self.valid(records) else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return try encoded(.object(Self.recordFields(records)))
    }

    /// Canonical business-state projection used only by replication checkpoints.
    /// Shipping backup transport continues to require its mutation history.
    func encodeSemanticRecords(
        _ records: V4BackupRecordsV1
    ) throws -> EncodedBackupJSONV1 {
        guard Self.validSemantic(records) else {
            throw BackupCanonicalEncodingErrorV1.invalidRecords
        }
        return try encoded(.object(Self.recordFields(records)))
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
        if records.recordsSchemaVersion >= 31 {
            fields["assistanceAcceptanceReceipts"] = .array(
                records.assistanceAcceptanceReceipts.map(Self.assistanceAcceptanceReceiptRecord)
            )
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
    static func validSemantic(_ records: V4BackupRecordsV1) -> Bool {
        guard (4...31).contains(records.recordsSchemaVersion),
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
             (20, let ledger?, let history?), (21, let ledger?, let history?), (22, let ledger?, let history?), (23, let ledger?, let history?), (24, let ledger?, let history?), (25, let ledger?, let history?), (26, let ledger?, let history?), (27, let ledger?, let history?), (28, let ledger?, let history?), (29, let ledger?, let history?), (30, let ledger?, let history?), (31, let ledger?, let history?):
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
        guard (4...31).contains(records.recordsSchemaVersion) else { return false }
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
        guard (6...31).contains(records.recordsSchemaVersion),
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
        guard (7...31).contains(records.recordsSchemaVersion),
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
        guard (8...31).contains(records.recordsSchemaVersion),
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
        guard (9...31).contains(records.recordsSchemaVersion) else { return false }
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
        guard (10...31).contains(records.recordsSchemaVersion) else { return false }
        let keys = records.authorityCriterion.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return keys == keys.sorted() && Set(keys).count == keys.count
            && records.authorityCriterion.allSatisfy {
                $0.id != zero && $0.workspaceID != zero && !$0.canonicalData.isEmpty
            }
    }

    static func validFunctionalRelationships(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 11 { return records.functionalRelationships.isEmpty }
        guard (11...31).contains(records.recordsSchemaVersion) else { return false }
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
        guard (12...31).contains(records.recordsSchemaVersion) else { return false }
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
        guard (13...31).contains(records.recordsSchemaVersion) else { return false }
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
        guard (14...31).contains(records.recordsSchemaVersion) else { return false }
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
        guard (15...31).contains(records.recordsSchemaVersion) else { return false }
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
        guard (16...31).contains(records.recordsSchemaVersion) else { return false }
        let keys = records.packageEvolution.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return records.packageEvolution.count <= 100_000 && Set(keys).count == keys.count
            && records.packageEvolution.allSatisfy {
                $0.id != zero && $0.workspaceID != zero && $0.revision > 0 && !$0.canonicalData.isEmpty
            }
    }

    static func validMeasurementIntegrity(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 17 { return records.measurementIntegrity.isEmpty }
        guard (17...31).contains(records.recordsSchemaVersion) else { return false }
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
        guard (18...31).contains(records.recordsSchemaVersion) else { return false }
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
        guard (19...31).contains(records.recordsSchemaVersion) else { return false }
        let keys=records.clientCapabilities.map{"\($0.kind.rawValue)\u{0}\($0.id.uuidString)"};let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        return records.clientCapabilities.count<=100_000 && keys==keys.sorted() && Set(keys).count==keys.count && records.clientCapabilities.allSatisfy{$0.id != zero && $0.workspaceID != zero && $0.revision>0 && $0.revision<=UInt64(Int.max) && !$0.canonicalData.isEmpty}
    }
    static func clientCapabilityRecord(_ value:V20BackupClientCapabilityRecordV1)throws->CanonicalJSONValueV1{guard let revision=Int(exactly:value.revision),!value.canonicalData.isEmpty else{throw BackupCanonicalEncodingErrorV1.invalidRecords};return .object(["canonicalData":.string(value.canonicalData.base64EncodedString()),"id":CanonicalJSONV1.uuid(value.id),"kind":.string(value.kind.rawValue),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)])}

    static func validRecoverabilityReceipts(_ records:V4BackupRecordsV1)->Bool{if records.recordsSchemaVersion<20{return records.recoverabilityReceipts.isEmpty};guard (20...31).contains(records.recordsSchemaVersion) else{return false};let keys=records.recoverabilityReceipts.map{$0.id.uuidString};let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0));return records.recoverabilityReceipts.count<=100_000 && keys==keys.sorted() && Set(keys).count==keys.count && records.recoverabilityReceipts.allSatisfy{$0.id != zero && $0.workspaceID != zero && $0.revision>0 && $0.revision<=UInt64(Int.max) && !$0.canonicalData.isEmpty}}
    static func recoverabilityReceiptRecord(_ value:V21BackupRecoverabilityReceiptRecordV1)throws->CanonicalJSONValueV1{guard let revision=Int(exactly:value.revision),!value.canonicalData.isEmpty else{throw BackupCanonicalEncodingErrorV1.invalidRecords};return .object(["canonicalData":.string(value.canonicalData.base64EncodedString()),"id":CanonicalJSONV1.uuid(value.id),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)])}
    static func validFieldReferences(_ records:V4BackupRecordsV1)->Bool{if records.recordsSchemaVersion<21{return records.fieldReferences.isEmpty};guard records.recordsSchemaVersion<=31 else{return false};let keys=records.fieldReferences.map{"\($0.kind.rawValue)|\($0.id.uuidString)"};let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0));return records.fieldReferences.count<=100_000 && keys==keys.sorted() && Set(keys).count==keys.count && records.fieldReferences.allSatisfy{$0.id != zero && $0.workspaceID != zero && $0.revision>0 && $0.revision<=UInt64(Int.max) && !$0.canonicalData.isEmpty}}
    static func fieldReferenceRecord(_ value:V22BackupFieldReferenceRecordV1)throws->CanonicalJSONValueV1{guard let revision=Int(exactly:value.revision),!value.canonicalData.isEmpty else{throw BackupCanonicalEncodingErrorV1.invalidRecords};return .object(["canonicalData":.string(value.canonicalData.base64EncodedString()),"id":CanonicalJSONV1.uuid(value.id),"kind":.string(value.kind.rawValue),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)])}
    static func validAccessibleDocumentAssessments(_ records:V4BackupRecordsV1)->Bool{if records.recordsSchemaVersion<22{return records.accessibleDocumentAssessments.isEmpty};let keys=records.accessibleDocumentAssessments.map{$0.id.uuidString};let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0));return records.accessibleDocumentAssessments.count<=100_000 && keys==keys.sorted() && Set(keys).count==keys.count && records.accessibleDocumentAssessments.allSatisfy{$0.id != zero && $0.workspaceID != zero && $0.revision>0 && $0.revision<=UInt64(Int.max) && !$0.canonicalData.isEmpty}}
    static func accessibleDocumentAssessmentRecord(_ value:V23BackupAccessibleDocumentAssessmentRecordV1)throws->CanonicalJSONValueV1{guard let revision=Int(exactly:value.revision),!value.canonicalData.isEmpty else{throw BackupCanonicalEncodingErrorV1.invalidRecords};return .object(["canonicalData":.string(value.canonicalData.base64EncodedString()),"id":CanonicalJSONV1.uuid(value.id),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)])}
    static func validSurveyDefinitions(_ records:V4BackupRecordsV1)->Bool{if records.recordsSchemaVersion<23{return records.surveyDefinitions.isEmpty};guard (23...31).contains(records.recordsSchemaVersion) else{return false};if records.mutationHistory==nil{return records.surveyDefinitions.isEmpty};let keys=records.surveyDefinitions.map{"\($0.kind.rawValue)|\($0.id.uuidString)"};let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0));return records.surveyDefinitions.count<=200_000&&keys==keys.sorted()&&Set(keys).count==keys.count&&records.surveyDefinitions.allSatisfy{$0.id != zero&&$0.workspaceID != zero&&$0.revision>0&&$0.revision<=UInt64(Int.max)&&!$0.canonicalData.isEmpty}}
    static func surveyDefinitionRecord(_ value:V24BackupSurveyDefinitionRecordV1)throws->CanonicalJSONValueV1{guard let revision=Int(exactly:value.revision),!value.canonicalData.isEmpty else{throw BackupCanonicalEncodingErrorV1.invalidRecords};return .object(["canonicalData":.string(value.canonicalData.base64EncodedString()),"id":CanonicalJSONV1.uuid(value.id),"kind":.string(value.kind.rawValue),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)])}
    static func validGuidedSurveys(_ records:V4BackupRecordsV1)->Bool{if records.recordsSchemaVersion<24{return records.guidedSurveys.isEmpty};guard (24...31).contains(records.recordsSchemaVersion) else{return false};if records.mutationHistory == nil{return records.guidedSurveys.isEmpty};let keys=records.guidedSurveys.map{"\($0.kind.rawValue)|\($0.id.uuidString)"};let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0));return records.guidedSurveys.count<=200_000&&keys==keys.sorted()&&Set(keys).count==keys.count&&records.guidedSurveys.allSatisfy{$0.id != zero&&$0.workspaceID != zero&&$0.revision>0&&$0.revision<=UInt64(Int.max)&&!$0.canonicalData.isEmpty}}
    static func guidedSurveyRecord(_ value:V25BackupGuidedSurveyRecordV1)throws->CanonicalJSONValueV1{guard let revision=Int(exactly:value.revision),!value.canonicalData.isEmpty else{throw BackupCanonicalEncodingErrorV1.invalidRecords};return .object(["canonicalData":.string(value.canonicalData.base64EncodedString()),"id":CanonicalJSONV1.uuid(value.id),"kind":.string(value.kind.rawValue),"revision":.integer(revision),"workspaceID":CanonicalJSONV1.uuid(value.workspaceID)])}
    static func validAssetLocators(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 25 { return records.assetLocators.isEmpty }
        guard records.recordsSchemaVersion <= 31 else { return false }
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
        guard (26...31).contains(records.recordsSchemaVersion),
              records.schedules.count <= 200_000 else { return false }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        let keys = records.schedules.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())" }
        return keys == keys.sorted()
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
        guard (27...31).contains(records.recordsSchemaVersion),
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
        guard (28...31).contains(records.recordsSchemaVersion),
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
        guard (29...31).contains(records.recordsSchemaVersion),
              records.evidenceContexts.allSatisfy({ $0.kind == .evidenceContext }),
              records.pairedObservationLinks.allSatisfy({ $0.kind == .pairedObservationLink }) else {
            return false
        }
        return (try? records.validateC30EvidenceContextClosure()) != nil
    }

    static func validC31Lighting(_ records: V4BackupRecordsV1) -> Bool {
        if records.recordsSchemaVersion < 30 { return records.lighting.isEmpty }
        guard records.recordsSchemaVersion == 30 || records.recordsSchemaVersion == 31,
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
        guard records.recordsSchemaVersion == 31,
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
             (4, 10, 9), (4, 11, 10), (4, 12, 11), (4, 13, 12), (4, 14, 13), (4, 15, 14), (4, 16, 15), (4, 17, 16), (4, 18, 17), (4, 19, 18), (4, 20, 19), (4, 21, 20), (4, 22, 21), (4, 23, 22), (4, 24, 23), (4, 25, 24), (4, 26, 25), (4, 27, 26), (4, 28, 27), (4, 29, 28), (4, 30, 29), (4, 31, 30), (4, 32, 31):
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
                <= MutationReceiptV1.maximumPostImageCount,
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
