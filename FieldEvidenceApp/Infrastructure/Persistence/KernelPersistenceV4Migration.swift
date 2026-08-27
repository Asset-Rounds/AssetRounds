import Foundation

enum KernelPersistenceV4MigrationPhase: String, Codable, CaseIterable, Sendable {
    case staging = "STAGING"
    case staged = "STAGED"
    case validating = "VALIDATING"
    case validated = "VALIDATED"
    case active = "ACTIVE"
    case discarded = "DISCARDED"
    case forwardFixRequired = "FORWARD_FIX_REQUIRED"
}

enum KernelPersistenceV4ResumeDisposition: String, Codable, Sendable {
    case resumeStaging = "RESUME_STAGING"
    case resumeValidation = "RESUME_VALIDATION"
    case activateValidatedStaging = "ACTIVATE_VALIDATED_STAGING"
    case useActiveV4 = "USE_ACTIVE_V4"
    case remainDiscardedV3 = "REMAIN_DISCARDED_V3"
    case requireForwardFixReadExport = "REQUIRE_FORWARD_FIX_READ_EXPORT"
}

enum KernelPersistenceV4OpenDisposition: String, Codable, Sendable {
    case openV3ReadWrite = "OPEN_V3_READ_WRITE"
    case resumeV3ToV4 = "RESUME_V3_TO_V4"
    case openV4ReadWrite = "OPEN_V4_READ_WRITE"
    case refuseNewerStore = "REFUSE_NEWER_STORE"
    case forwardFixReadExportOnly = "FORWARD_FIX_READ_EXPORT_ONLY"
}

struct KernelPersistenceV4StagedRecordCount: Codable, Equatable, Comparable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable { case kind, sourceCount, stagedCount, batchDigest }
    let kind: KernelPersistenceV4RecordKind
    let sourceCount: Int
    let stagedCount: Int
    let batchDigest: String

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.kind < rhs.kind }

    init(kind: KernelPersistenceV4RecordKind, sourceCount: Int, stagedCount: Int, batchDigest: String) throws {
        self.kind = kind
        self.sourceCount = sourceCount
        self.stagedCount = stagedCount
        self.batchDigest = batchDigest
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(KernelPersistenceV4RecordKind.self, forKey: .kind)
        sourceCount = try values.decode(Int.self, forKey: .sourceCount)
        stagedCount = try values.decode(Int.self, forKey: .stagedCount)
        batchDigest = try values.decode(String.self, forKey: .batchDigest)
        try validate()
    }

    func validate() throws {
        guard sourceCount >= 0, stagedCount >= 0, sourceCount == stagedCount,
              KernelCanonicalHashV1.validSHA256(batchDigest) else {
            throw KernelPersistenceV4Failure.invalidValue
        }
    }
}

struct KernelPersistenceV4MigrationCheckpoint: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case checkpointID, migrationID, sourceSchemaVersion, targetSchemaVersion, sourceStoreDigest
        case phase, stagedRecords, stagedRelationshipKinds, stagingDigest, schemaDescriptorDigest
        case archiveManifestDigest, exportManifestDigest, published, canonicalV4WriteObserved
    }

    let checkpointID: String
    let migrationID: String
    let sourceSchemaVersion: Int
    let targetSchemaVersion: Int
    let sourceStoreDigest: String
    let phase: KernelPersistenceV4MigrationPhase
    let stagedRecords: [KernelPersistenceV4StagedRecordCount]
    let stagedRelationshipKinds: [KernelPersistenceV4RelationshipKind]
    let stagingDigest: String?
    let schemaDescriptorDigest: String?
    let archiveManifestDigest: String?
    let exportManifestDigest: String?
    let published: Bool
    let canonicalV4WriteObserved: Bool

    init(
        migrationID: String,
        sourceSchemaVersion: Int = KernelPersistenceV4Validation.predecessorSchemaVersion,
        sourceStoreDigest: String,
        phase: KernelPersistenceV4MigrationPhase,
        stagedRecords: [KernelPersistenceV4StagedRecordCount] = [],
        stagedRelationshipKinds: [KernelPersistenceV4RelationshipKind] = [],
        stagingDigest: String? = nil,
        schemaDescriptorDigest: String? = nil,
        archiveManifestDigest: String? = nil,
        exportManifestDigest: String? = nil,
        published: Bool = false,
        canonicalV4WriteObserved: Bool = false
    ) throws {
        self.migrationID = migrationID
        self.sourceSchemaVersion = sourceSchemaVersion
        targetSchemaVersion = KernelPersistenceV4Validation.schemaVersion
        self.sourceStoreDigest = sourceStoreDigest
        self.phase = phase
        self.stagedRecords = stagedRecords
        self.stagedRelationshipKinds = stagedRelationshipKinds
        self.stagingDigest = stagingDigest
        self.schemaDescriptorDigest = schemaDescriptorDigest
        self.archiveManifestDigest = archiveManifestDigest
        self.exportManifestDigest = exportManifestDigest
        self.published = published
        self.canonicalV4WriteObserved = canonicalV4WriteObserved
        checkpointID = try Self.makeCheckpointID(
            migrationID: migrationID, sourceStoreDigest: sourceStoreDigest, phase: phase,
            stagedRecords: stagedRecords, stagedRelationshipKinds: stagedRelationshipKinds,
            stagingDigest: stagingDigest, schemaDescriptorDigest: schemaDescriptorDigest,
            archiveManifestDigest: archiveManifestDigest, exportManifestDigest: exportManifestDigest,
            published: published, canonicalV4WriteObserved: canonicalV4WriteObserved
        )
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        checkpointID = try values.decode(String.self, forKey: .checkpointID)
        migrationID = try values.decode(String.self, forKey: .migrationID)
        sourceSchemaVersion = try values.decode(Int.self, forKey: .sourceSchemaVersion)
        targetSchemaVersion = try values.decode(Int.self, forKey: .targetSchemaVersion)
        sourceStoreDigest = try values.decode(String.self, forKey: .sourceStoreDigest)
        phase = try values.decode(KernelPersistenceV4MigrationPhase.self, forKey: .phase)
        stagedRecords = try values.decode([KernelPersistenceV4StagedRecordCount].self, forKey: .stagedRecords)
        stagedRelationshipKinds = try values.decode([KernelPersistenceV4RelationshipKind].self, forKey: .stagedRelationshipKinds)
        stagingDigest = try KernelPersistenceV4Validation.decodeAbsentOrValue(
            String.self, from: values, forKey: .stagingDigest
        )
        schemaDescriptorDigest = try KernelPersistenceV4Validation.decodeAbsentOrValue(
            String.self, from: values, forKey: .schemaDescriptorDigest
        )
        archiveManifestDigest = try KernelPersistenceV4Validation.decodeAbsentOrValue(
            String.self, from: values, forKey: .archiveManifestDigest
        )
        exportManifestDigest = try KernelPersistenceV4Validation.decodeAbsentOrValue(
            String.self, from: values, forKey: .exportManifestDigest
        )
        published = try values.decode(Bool.self, forKey: .published)
        canonicalV4WriteObserved = try values.decode(Bool.self, forKey: .canonicalV4WriteObserved)
        try validate()
    }

    func validate() throws {
        guard KernelPersistenceV4Validation.validID(migrationID),
              sourceSchemaVersion == KernelPersistenceV4Validation.predecessorSchemaVersion,
              targetSchemaVersion == KernelPersistenceV4Validation.schemaVersion,
              KernelCanonicalHashV1.validSHA256(sourceStoreDigest),
              stagedRecords == stagedRecords.sorted(), Set(stagedRecords.map(\.kind)).count == stagedRecords.count,
              stagedRelationshipKinds == stagedRelationshipKinds.sorted(),
              Set(stagedRelationshipKinds).count == stagedRelationshipKinds.count,
              [stagingDigest, schemaDescriptorDigest, archiveManifestDigest, exportManifestDigest]
                .compactMap({ $0 }).allSatisfy(KernelCanonicalHashV1.validSHA256) else {
            throw KernelPersistenceV4Failure.invalidValue
        }
        try stagedRecords.forEach { try $0.validate() }
        let schema = try KernelPersistenceV4Schema.descriptor()
        let completeRecords = Set(stagedRecords.map(\.kind)) == Set(schema.records.map(\.kind))
        let completeRelationships = Set(stagedRelationshipKinds) == Set(schema.relationships.map(\.kind))
        switch phase {
        case .staging:
            guard stagingDigest == nil, schemaDescriptorDigest == nil,
                  archiveManifestDigest == nil, exportManifestDigest == nil,
                  !published, !canonicalV4WriteObserved else { throw KernelPersistenceV4Failure.partialActivation }
        case .staged, .validating:
            guard completeRecords, completeRelationships, stagingDigest != nil,
                  schemaDescriptorDigest == nil, !published, !canonicalV4WriteObserved else {
                throw KernelPersistenceV4Failure.incompleteCoverage
            }
        case .validated:
            guard completeRecords, completeRelationships, stagingDigest != nil,
                  schemaDescriptorDigest != nil, archiveManifestDigest != nil, exportManifestDigest != nil,
                  !published, !canonicalV4WriteObserved else { throw KernelPersistenceV4Failure.partialActivation }
        case .active:
            guard completeRecords, completeRelationships, stagingDigest != nil,
                  schemaDescriptorDigest != nil, archiveManifestDigest != nil, exportManifestDigest != nil else {
                throw KernelPersistenceV4Failure.partialActivation
            }
        case .discarded:
            guard stagedRecords.isEmpty, stagedRelationshipKinds.isEmpty,
                  stagingDigest == nil, schemaDescriptorDigest == nil,
                  archiveManifestDigest == nil, exportManifestDigest == nil,
                  !published, !canonicalV4WriteObserved else {
                throw KernelPersistenceV4Failure.downgradeProhibited
            }
        case .forwardFixRequired:
            guard completeRecords, completeRelationships,
                  stagingDigest != nil, schemaDescriptorDigest != nil,
                  archiveManifestDigest != nil, exportManifestDigest != nil,
                  published || canonicalV4WriteObserved else {
                throw KernelPersistenceV4Failure.forwardFixRequired
            }
        }
        let expected = try Self.makeCheckpointID(
            migrationID: migrationID, sourceStoreDigest: sourceStoreDigest, phase: phase,
            stagedRecords: stagedRecords, stagedRelationshipKinds: stagedRelationshipKinds,
            stagingDigest: stagingDigest, schemaDescriptorDigest: schemaDescriptorDigest,
            archiveManifestDigest: archiveManifestDigest, exportManifestDigest: exportManifestDigest,
            published: published, canonicalV4WriteObserved: canonicalV4WriteObserved
        )
        guard checkpointID == expected else { throw KernelPersistenceV4Failure.digestMismatch }
    }

    private struct DigestMaterial: Encodable {
        let migrationID: String
        let sourceSchemaVersion: Int
        let targetSchemaVersion: Int
        let sourceStoreDigest: String
        let phase: KernelPersistenceV4MigrationPhase
        let stagedRecords: [KernelPersistenceV4StagedRecordCount]
        let stagedRelationshipKinds: [KernelPersistenceV4RelationshipKind]
        let stagingDigest: String?
        let schemaDescriptorDigest: String?
        let archiveManifestDigest: String?
        let exportManifestDigest: String?
        let published: Bool
        let canonicalV4WriteObserved: Bool
    }

    private static func makeCheckpointID(
        migrationID: String,
        sourceStoreDigest: String,
        phase: KernelPersistenceV4MigrationPhase,
        stagedRecords: [KernelPersistenceV4StagedRecordCount],
        stagedRelationshipKinds: [KernelPersistenceV4RelationshipKind],
        stagingDigest: String?,
        schemaDescriptorDigest: String?,
        archiveManifestDigest: String?,
        exportManifestDigest: String?,
        published: Bool,
        canonicalV4WriteObserved: Bool
    ) throws -> String {
        try KernelPersistenceV4Validation.canonicalDigest(DigestMaterial(
            migrationID: migrationID,
            sourceSchemaVersion: KernelPersistenceV4Validation.predecessorSchemaVersion,
            targetSchemaVersion: KernelPersistenceV4Validation.schemaVersion,
            sourceStoreDigest: sourceStoreDigest,
            phase: phase,
            stagedRecords: stagedRecords,
            stagedRelationshipKinds: stagedRelationshipKinds,
            stagingDigest: stagingDigest,
            schemaDescriptorDigest: schemaDescriptorDigest,
            archiveManifestDigest: archiveManifestDigest,
            exportManifestDigest: exportManifestDigest,
            published: published,
            canonicalV4WriteObserved: canonicalV4WriteObserved
        ))
    }
}

enum KernelPersistenceV4Migration {
    static func begin(migrationID: String, sourceStoreDigest: String) throws -> KernelPersistenceV4MigrationCheckpoint {
        try KernelPersistenceV4Schema.validate()
        return try KernelPersistenceV4MigrationCheckpoint(
            migrationID: migrationID, sourceStoreDigest: sourceStoreDigest, phase: .staging
        )
    }

    static func stage(
        _ checkpoint: KernelPersistenceV4MigrationCheckpoint,
        record: KernelPersistenceV4StagedRecordCount
    ) throws -> KernelPersistenceV4MigrationCheckpoint {
        try checkpoint.validate()
        guard checkpoint.phase == .staging,
              !checkpoint.stagedRecords.contains(where: { $0.kind == record.kind }) else {
            throw KernelPersistenceV4Failure.invalidTransition
        }
        return try replacing(checkpoint, phase: .staging, stagedRecords: (checkpoint.stagedRecords + [record]).sorted())
    }

    static func completeStaging(
        _ checkpoint: KernelPersistenceV4MigrationCheckpoint,
        schema: KernelPersistenceV4SchemaDescriptor,
        stagingDigest: String
    ) throws -> KernelPersistenceV4MigrationCheckpoint {
        try checkpoint.validate()
        try schema.validate()
        let schemaRecordKinds = Set(schema.records.map(\.kind))
        let schemaRelationshipKinds = schema.relationships.map(\.kind)
        guard checkpoint.phase == .staging,
              Set(checkpoint.stagedRecords.map(\.kind)) == schemaRecordKinds,
              KernelCanonicalHashV1.validSHA256(stagingDigest) else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        return try replacing(
            checkpoint, phase: .staged,
            stagedRelationshipKinds: schemaRelationshipKinds.sorted(), stagingDigest: stagingDigest
        )
    }

    static func beginValidation(
        _ checkpoint: KernelPersistenceV4MigrationCheckpoint
    ) throws -> KernelPersistenceV4MigrationCheckpoint {
        try checkpoint.validate()
        guard checkpoint.phase == .staged else { throw KernelPersistenceV4Failure.invalidTransition }
        return try replacing(checkpoint, phase: .validating)
    }

    static func acceptValidation(
        _ checkpoint: KernelPersistenceV4MigrationCheckpoint,
        schema: KernelPersistenceV4SchemaDescriptor,
        archiveManifestDigest: String,
        exportManifestDigest: String
    ) throws -> KernelPersistenceV4MigrationCheckpoint {
        try checkpoint.validate()
        try schema.validate()
        guard checkpoint.phase == .validating,
              KernelCanonicalHashV1.validSHA256(archiveManifestDigest),
              KernelCanonicalHashV1.validSHA256(exportManifestDigest) else {
            throw KernelPersistenceV4Failure.invalidTransition
        }
        return try replacing(
            checkpoint, phase: .validated, schemaDescriptorDigest: schema.descriptorDigest,
            archiveManifestDigest: archiveManifestDigest, exportManifestDigest: exportManifestDigest
        )
    }

    static func activateValidatedStaging(
        _ checkpoint: KernelPersistenceV4MigrationCheckpoint,
        s10_6IntegrationAccepted: Bool
    ) throws -> KernelPersistenceV4MigrationCheckpoint {
        try checkpoint.validate()
        guard checkpoint.phase == .validated, s10_6IntegrationAccepted else {
            throw KernelPersistenceV4Failure.invalidTransition
        }
        return try replacing(checkpoint, phase: .active)
    }

    static func observePublicationOrCanonicalWrite(
        _ checkpoint: KernelPersistenceV4MigrationCheckpoint,
        published: Bool,
        canonicalWrite: Bool
    ) throws -> KernelPersistenceV4MigrationCheckpoint {
        try checkpoint.validate()
        guard checkpoint.phase == .active, published || canonicalWrite else {
            throw KernelPersistenceV4Failure.invalidTransition
        }
        return try replacing(
            checkpoint, phase: .active,
            published: checkpoint.published || published,
            canonicalV4WriteObserved: checkpoint.canonicalV4WriteObserved || canonicalWrite
        )
    }

    static func discardBeforeActivation(
        _ checkpoint: KernelPersistenceV4MigrationCheckpoint
    ) throws -> KernelPersistenceV4MigrationCheckpoint {
        try checkpoint.validate()
        guard checkpoint.phase != .active, checkpoint.phase != .forwardFixRequired,
              !checkpoint.published, !checkpoint.canonicalV4WriteObserved else {
            throw KernelPersistenceV4Failure.downgradeProhibited
        }
        return try KernelPersistenceV4MigrationCheckpoint(
            migrationID: checkpoint.migrationID,
            sourceStoreDigest: checkpoint.sourceStoreDigest,
            phase: .discarded
        )
    }

    static func requireForwardFix(
        _ checkpoint: KernelPersistenceV4MigrationCheckpoint
    ) throws -> KernelPersistenceV4MigrationCheckpoint {
        try checkpoint.validate()
        guard checkpoint.phase == .active,
              checkpoint.published || checkpoint.canonicalV4WriteObserved else {
            throw KernelPersistenceV4Failure.invalidTransition
        }
        return try replacing(checkpoint, phase: .forwardFixRequired)
    }

    static func resumeDisposition(
        for checkpoint: KernelPersistenceV4MigrationCheckpoint
    ) throws -> KernelPersistenceV4ResumeDisposition {
        try checkpoint.validate()
        switch checkpoint.phase {
        case .staging: return .resumeStaging
        case .staged, .validating: return .resumeValidation
        case .validated: return .activateValidatedStaging
        case .active: return .useActiveV4
        case .discarded: return .remainDiscardedV3
        case .forwardFixRequired: return .requireForwardFixReadExport
        }
    }

    static func openDisposition(
        storeSchemaVersion: Int,
        binaryMaximumSchemaVersion: Int,
        checkpoint: KernelPersistenceV4MigrationCheckpoint?
    ) throws -> KernelPersistenceV4OpenDisposition {
        guard storeSchemaVersion > 0, binaryMaximumSchemaVersion > 0 else {
            throw KernelPersistenceV4Failure.invalidValue
        }
        if storeSchemaVersion > binaryMaximumSchemaVersion { return .refuseNewerStore }
        if storeSchemaVersion > KernelPersistenceV4Validation.schemaVersion { return .refuseNewerStore }

        if storeSchemaVersion == KernelPersistenceV4Validation.predecessorSchemaVersion {
            guard let checkpoint else { return .openV3ReadWrite }
            try checkpoint.validate()
            switch checkpoint.phase {
            case .staging, .staged, .validating, .validated:
                guard binaryMaximumSchemaVersion >= KernelPersistenceV4Validation.schemaVersion else {
                    return .refuseNewerStore
                }
                return .resumeV3ToV4
            case .discarded:
                return .openV3ReadWrite
            case .active, .forwardFixRequired:
                return .refuseNewerStore
            }
        }

        if storeSchemaVersion == KernelPersistenceV4Validation.schemaVersion {
            guard binaryMaximumSchemaVersion >= KernelPersistenceV4Validation.schemaVersion,
                  let checkpoint else { return .refuseNewerStore }
            do {
                try checkpoint.validate()
            } catch {
                return .refuseNewerStore
            }
            switch checkpoint.phase {
            case .active:
                return .openV4ReadWrite
            case .forwardFixRequired:
                return .forwardFixReadExportOnly
            case .staging, .staged, .validating, .validated, .discarded:
                return .refuseNewerStore
            }
        }
        throw KernelPersistenceV4Failure.incompatibleSourceVersion
    }

    private static func replacing(
        _ value: KernelPersistenceV4MigrationCheckpoint,
        phase: KernelPersistenceV4MigrationPhase,
        stagedRecords: [KernelPersistenceV4StagedRecordCount]? = nil,
        stagedRelationshipKinds: [KernelPersistenceV4RelationshipKind]? = nil,
        stagingDigest: String? = nil,
        schemaDescriptorDigest: String? = nil,
        archiveManifestDigest: String? = nil,
        exportManifestDigest: String? = nil,
        published: Bool? = nil,
        canonicalV4WriteObserved: Bool? = nil
    ) throws -> KernelPersistenceV4MigrationCheckpoint {
        try KernelPersistenceV4MigrationCheckpoint(
            migrationID: value.migrationID,
            sourceSchemaVersion: value.sourceSchemaVersion,
            sourceStoreDigest: value.sourceStoreDigest,
            phase: phase,
            stagedRecords: stagedRecords ?? value.stagedRecords,
            stagedRelationshipKinds: stagedRelationshipKinds ?? value.stagedRelationshipKinds,
            stagingDigest: stagingDigest ?? value.stagingDigest,
            schemaDescriptorDigest: schemaDescriptorDigest ?? value.schemaDescriptorDigest,
            archiveManifestDigest: archiveManifestDigest ?? value.archiveManifestDigest,
            exportManifestDigest: exportManifestDigest ?? value.exportManifestDigest,
            published: published ?? value.published,
            canonicalV4WriteObserved: canonicalV4WriteObserved ?? value.canonicalV4WriteObserved
        )
    }
}
