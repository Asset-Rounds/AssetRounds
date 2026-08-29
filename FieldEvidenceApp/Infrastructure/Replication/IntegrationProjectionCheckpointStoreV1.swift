import CryptoKit
import Foundation

/// Generation-scoped, disposable storage for a single consumer's derived
/// event page and checkpoint. Canonical mutation and provider state never
/// enter this store.
actor IntegrationProjectionCheckpointStoreV1: IntegrationProjectionOperationalStoreV1 {
    private static let maximumStoredBytes = ChangeJournalLimitsV1.productionMaximumBatchBytes * 4
    private struct StoredProjection: Codable, Equatable, Sendable {
        static let schemaVersion = 1
        let schemaVersion: Int
        let generationID: UUID
        let workspaceID: WorkspaceID
        let consumerID: String
        let events: [IntegrationEventV1]
        let checkpoint: ProjectionCheckpointV1
        let projectionSHA256: String

        init(generationID: UUID, workspaceID: WorkspaceID, consumerID: String,
             events: [IntegrationEventV1], checkpoint: ProjectionCheckpointV1) throws {
            schemaVersion = Self.schemaVersion
            self.generationID = generationID
            self.workspaceID = workspaceID
            self.consumerID = consumerID
            self.events = events
            self.checkpoint = checkpoint
            projectionSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
                schemaVersion: Self.schemaVersion, generationID: generationID,
                workspaceID: workspaceID, consumerID: consumerID,
                events: events, checkpoint: checkpoint
            ))
        }

        func validate(expectedGenerationID: UUID, expectedWorkspaceID: WorkspaceID,
                      expectedConsumerID: String, maximumStoredEvents: Int) throws {
            try checkpoint.validate()
            try IntegrationProjectionCheckpointStoreV1.validatePackagePromotionEventPage(events)
            try IntegrationProjectionCheckpointStoreV1.validateMeasurementIntegrityEventPage(events)
            try IntegrationProjectionCheckpointStoreV1.validatePrivacyTransformEventPage(events)
            try IntegrationProjectionCheckpointStoreV1.validateClientCapabilityEventPage(events)
            try IntegrationProjectionCheckpointStoreV1.validateFieldReferenceEventPage(events)
            try IntegrationProjectionCheckpointStoreV1.validateAccessibleDocumentAssessmentEventPage(events)
            try IntegrationProjectionCheckpointStoreV1.validateSurveyDefinitionEventPage(events)
            guard schemaVersion == Self.schemaVersion,
                  generationID == expectedGenerationID,
                  workspaceID == expectedWorkspaceID,
                  consumerID == expectedConsumerID,
                  checkpoint.workspaceID == workspaceID,
                  checkpoint.consumerID == consumerID,
                  events.count <= maximumStoredEvents,
                  events.allSatisfy({ $0.workspaceID == workspaceID }),
                  events == events.sorted(by: { $0.order < $1.order }),
                  Set(events.map(\.eventID)).count == events.count,
                  projectionSHA256 == (try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
                    schemaVersion: schemaVersion, generationID: generationID,
                    workspaceID: workspaceID, consumerID: consumerID,
                    events: events, checkpoint: checkpoint
                  ))) else {
                throw IntegrationEventFailureV1.invalidDigest
            }
            if let terminal = events.last {
                guard checkpoint.lastOrder == terminal.order,
                      checkpoint.lastEventID == terminal.eventID,
                      checkpoint.lastEventSHA256 == terminal.eventSHA256 else {
                    throw IntegrationEventFailureV1.staleCheckpoint
                }
            }
        }

        private struct DigestBasis: Codable {
            let schemaVersion: Int
            let generationID: UUID
            let workspaceID: WorkspaceID
            let consumerID: String
            let events: [IntegrationEventV1]
            let checkpoint: ProjectionCheckpointV1
        }
    }

    private struct DerivedEffect: Codable, Equatable, Sendable {
        let eventID: String
        let eventSHA256: String
        let order: IntegrationEventOrderV1
    }

    private struct StoredEffects: Codable, Equatable, Sendable {
        static let schemaVersion = 1
        let schemaVersion: Int
        let generationID: UUID
        let workspaceID: WorkspaceID
        let consumerID: String
        let effects: [DerivedEffect]
        let effectsSHA256: String

        init(generationID: UUID, workspaceID: WorkspaceID, consumerID: String,
             effects: [DerivedEffect]) throws {
            schemaVersion = Self.schemaVersion
            self.generationID = generationID
            self.workspaceID = workspaceID
            self.consumerID = consumerID
            self.effects = effects.sorted { $0.order < $1.order }
            effectsSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
                schemaVersion: Self.schemaVersion, generationID: generationID,
                workspaceID: workspaceID, consumerID: consumerID, effects: self.effects
            ))
        }

        func validate(expectedGenerationID: UUID, expectedWorkspaceID: WorkspaceID,
                      expectedConsumerID: String, maximumStoredEvents: Int) throws {
            guard schemaVersion == Self.schemaVersion,
                  generationID == expectedGenerationID,
                  workspaceID == expectedWorkspaceID,
                  consumerID == expectedConsumerID,
                  effects.count <= maximumStoredEvents,
                  effects == effects.sorted(by: { $0.order < $1.order }),
                  Set(effects.map(\.eventID)).count == effects.count,
                  Set(effects.map(\.order)).count == effects.count,
                  effects.allSatisfy({
                      IntegrationEventValidationV1.isSHA256($0.eventID)
                          && IntegrationEventValidationV1.isSHA256($0.eventSHA256)
                  }),
                  effectsSHA256 == (try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
                    schemaVersion: schemaVersion, generationID: generationID,
                    workspaceID: workspaceID, consumerID: consumerID, effects: effects
                  ))) else { throw IntegrationEventFailureV1.invalidDigest }
        }

        private struct DigestBasis: Codable {
            let schemaVersion: Int
            let generationID: UUID
            let workspaceID: WorkspaceID
            let consumerID: String
            let effects: [DerivedEffect]
        }
    }

    private let generationID: UUID
    private let workspaceID: WorkspaceID
    private let rootURL: URL
    private let fileManager: FileManager
    private let maximumStoredEvents: Int

    private static func validatePackagePromotionEventPage(_ events:[IntegrationEventV1])throws{let grouped=Dictionary(grouping:events,by:\.sourceReceiptID);for page in grouped.values{let kinds=Set(page.map{$0.subject.kind});let present=kinds.intersection(IntegrationEventProjectionV1.packagePromotionKinds);guard present.isEmpty || (page.count==4&&kinds==IntegrationEventProjectionV1.packagePromotionKinds)else{throw IntegrationEventFailureV1.divergentEvent}}}
    private static func validateMeasurementIntegrityEventPage(_ events:[IntegrationEventV1])throws{let grouped=Dictionary(grouping:events,by:\.sourceReceiptID);for page in grouped.values{let subjects=page.map(\.subject),present=Set(subjects.map(\.kind)).intersection(IntegrationEventProjectionV1.measurementIntegrityKinds);guard present.isEmpty || (page.count<=128&&Set(subjects).count==subjects.count&&subjects.allSatisfy{IntegrationEventProjectionV1.measurementIntegrityKinds.contains($0.kind)})else{throw IntegrationEventFailureV1.divergentEvent}}}
    private static func validatePrivacyTransformEventPage(_ events:[IntegrationEventV1])throws{let grouped=Dictionary(grouping:events,by:\.sourceReceiptID);for page in grouped.values{let subjects=page.map(\.subject),present=Set(subjects.map(\.kind)).intersection(IntegrationEventProjectionV1.privacyTransformKinds);guard present.isEmpty || (Set(subjects).count==subjects.count&&subjects.allSatisfy{IntegrationEventProjectionV1.privacyTransformKinds.contains($0.kind)})else{throw IntegrationEventFailureV1.divergentEvent}}}
    private static func validateClientCapabilityEventPage(_ events:[IntegrationEventV1])throws{let grouped=Dictionary(grouping:events,by:\.sourceReceiptID);for page in grouped.values{let subjects=page.map(\.subject),present=Set(subjects.map(\.kind)).intersection(IntegrationEventProjectionV1.clientCapabilityKinds);guard present.isEmpty || (page.count==1&&Set(subjects).count==1&&subjects.allSatisfy{IntegrationEventProjectionV1.clientCapabilityKinds.contains($0.kind)})else{throw IntegrationEventFailureV1.divergentEvent}}}
    private static func validateFieldReferenceEventPage(_ events:[IntegrationEventV1])throws{let grouped=Dictionary(grouping:events,by:\.sourceReceiptID);for page in grouped.values{let subjects=page.map(\.subject),present=Set(subjects.map(\.kind)).intersection(IntegrationEventProjectionV1.fieldReferenceKinds);guard present.isEmpty || (page.count==1&&Set(subjects).count==1&&subjects.allSatisfy{IntegrationEventProjectionV1.fieldReferenceKinds.contains($0.kind)})else{throw IntegrationEventFailureV1.divergentEvent}}}
    private static func validateAccessibleDocumentAssessmentEventPage(_ events:[IntegrationEventV1])throws{let grouped=Dictionary(grouping:events,by:\.sourceReceiptID);for page in grouped.values{let subjects=page.map(\.subject),present=Set(subjects.map(\.kind)).intersection(IntegrationEventProjectionV1.accessibleDocumentAssessmentKinds);guard present.isEmpty || (page.count==1&&Set(subjects).count==1&&subjects.allSatisfy{IntegrationEventProjectionV1.accessibleDocumentAssessmentKinds.contains($0.kind)})else{throw IntegrationEventFailureV1.divergentEvent}}}
    private static func validateSurveyDefinitionEventPage(_ events:[IntegrationEventV1])throws{let grouped=Dictionary(grouping:events,by:\.sourceReceiptID);for page in grouped.values{let subjects=page.map(\.subject),present=Set(subjects.map(\.kind)).intersection(IntegrationEventProjectionV1.surveyDefinitionKinds);guard present.isEmpty || ((page.count==1||page.count==2)&&Set(subjects).count==subjects.count&&subjects.contains(where:{$0.kind == .surveyDefinitionIdentity})&&subjects.allSatisfy{IntegrationEventProjectionV1.surveyDefinitionKinds.contains($0.kind)})else{throw IntegrationEventFailureV1.divergentEvent}}}

    init(generationRootURL: URL, generationID: UUID, workspaceID: WorkspaceID,
         limits: IntegrationEventLimitsV1 = try! IntegrationEventLimitsV1(),
         fileManager: FileManager = .default) throws {
        try limits.validate()
        guard generationID != UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
              workspaceID.rawValue != UUID(uuidString: "00000000-0000-0000-0000-000000000000")! else {
            throw IntegrationEventFailureV1.invalidValue
        }
        self.generationID = generationID
        self.workspaceID = workspaceID
        self.fileManager = fileManager
        maximumStoredEvents = limits.maximumEventsPerReplay
        rootURL = generationRootURL.standardizedFileURL
            .appendingPathComponent("replication/integration-projections-v1", isDirectory: true)
    }

    func checkpoint(consumerID: String, workspaceID: WorkspaceID) async throws -> ProjectionCheckpointV1? {
        try requireScope(consumerID: consumerID, workspaceID: workspaceID)
        let url = stateURL(consumerID: consumerID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try load(consumerID: consumerID).checkpoint
    }

    func replaceDerivedProjection(events: [IntegrationEventV1], checkpoint: ProjectionCheckpointV1,
                                  consumerID: String, workspaceID: WorkspaceID) async throws {
        try requireScope(consumerID: consumerID, workspaceID: workspaceID)
        try checkpoint.validate()
        guard checkpoint.consumerID == consumerID,
              checkpoint.workspaceID == workspaceID,
              events.count <= maximumStoredEvents else {
            throw IntegrationEventFailureV1.limitExceeded
        }
        let recordedEffects = try loadEffectsIfPresent(consumerID: consumerID)?.effects ?? []
        let recordedByID = Dictionary(uniqueKeysWithValues: recordedEffects.map {
            ($0.eventID, $0.eventSHA256)
        })
        guard events.allSatisfy({ recordedByID[$0.eventID] == $0.eventSHA256 }) else {
            throw IntegrationEventFailureV1.staleCheckpoint
        }
        let stored = try StoredProjection(
            generationID: generationID, workspaceID: workspaceID,
            consumerID: consumerID, events: events, checkpoint: checkpoint
        )
        try stored.validate(expectedGenerationID: generationID,
                            expectedWorkspaceID: workspaceID,
                            expectedConsumerID: consumerID,
                            maximumStoredEvents: maximumStoredEvents)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try WorkspaceMutationCanonicalV1.data(stored)
        guard data.count <= Self.maximumStoredBytes else { throw IntegrationEventFailureV1.limitExceeded }
        try data.write(to: stateURL(consumerID: consumerID), options: .atomic)
        _ = try load(consumerID: consumerID)
    }

    func recordDerivedConsumerEffects(events: [IntegrationEventV1], consumerID: String,
                                      workspaceID: WorkspaceID) async throws {
        try requireScope(consumerID: consumerID, workspaceID: workspaceID)
        guard events.count <= maximumStoredEvents,
              events.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw IntegrationEventFailureV1.limitExceeded
        }
        let existing = try loadEffectsIfPresent(consumerID: consumerID)?.effects ?? []
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.eventID, $0) })
        for event in events {
            if let recorded = byID[event.eventID] {
                guard recorded.eventSHA256 == event.eventSHA256,
                      recorded.order == event.order else {
                    throw IntegrationEventFailureV1.divergentEvent
                }
            } else {
                byID[event.eventID] = DerivedEffect(
                    eventID: event.eventID,
                    eventSHA256: event.eventSHA256,
                    order: event.order
                )
            }
        }
        guard byID.count <= maximumStoredEvents else {
            throw IntegrationEventFailureV1.limitExceeded
        }
        let value = try StoredEffects(
            generationID: generationID, workspaceID: workspaceID,
            consumerID: consumerID, effects: Array(byID.values)
        )
        try value.validate(expectedGenerationID: generationID,
                           expectedWorkspaceID: workspaceID,
                           expectedConsumerID: consumerID,
                           maximumStoredEvents: maximumStoredEvents)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try WorkspaceMutationCanonicalV1.data(value)
        guard data.count <= Self.maximumStoredBytes else {
            throw IntegrationEventFailureV1.limitExceeded
        }
        try data.write(to: effectsURL(consumerID: consumerID), options: .atomic)
        _ = try loadEffects(consumerID: consumerID)
    }

    func recordedDerivedEffectEventIDs(consumerID: String, workspaceID: WorkspaceID) async throws -> [String] {
        try requireScope(consumerID: consumerID, workspaceID: workspaceID)
        return try loadEffectsIfPresent(consumerID: consumerID)?.effects.map(\.eventID) ?? []
    }

    func dropDerivedProjection(consumerID: String?, workspaceID: WorkspaceID) async throws {
        guard workspaceID == self.workspaceID else { throw IntegrationEventFailureV1.wrongWorkspace }
        if let consumerID {
            try requireScope(consumerID: consumerID, workspaceID: workspaceID)
            for url in [stateURL(consumerID: consumerID), effectsURL(consumerID: consumerID)] {
                if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            }
            return
        }
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        let members = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        guard members.count <= IntegrationEventLimitsV1.productionMaximumDefinitions * 2,
              try members.allSatisfy({ member in
                let values = try member.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                let name = member.lastPathComponent
                let digestLength: Int
                if name.hasPrefix("consumer-") { digestLength = name.dropFirst(9).dropLast(5).count }
                else if name.hasPrefix("effects-") { digestLength = name.dropFirst(8).dropLast(5).count }
                else { digestLength = -1 }
                return member.deletingLastPathComponent().standardizedFileURL == rootURL
                    && values.isRegularFile == true && values.isSymbolicLink != true
                    && (name.hasPrefix("consumer-") || name.hasPrefix("effects-"))
                    && name.hasSuffix(".json")
                    && digestLength == 64
              }) else {
            throw IntegrationEventFailureV1.limitExceeded
        }
        for member in members { try fileManager.removeItem(at: member) }
    }

    private func load(consumerID: String) throws -> StoredProjection {
        let url = stateURL(consumerID: consumerID)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize,
              size > 0, size <= Self.maximumStoredBytes else {
            throw IntegrationEventFailureV1.limitExceeded
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(StoredProjection.self, from: data)
        guard try WorkspaceMutationCanonicalV1.data(value) == data else {
            throw IntegrationEventFailureV1.invalidDigest
        }
        try value.validate(expectedGenerationID: generationID,
                           expectedWorkspaceID: workspaceID,
                           expectedConsumerID: consumerID,
                           maximumStoredEvents: maximumStoredEvents)
        return value
    }

    private func loadEffectsIfPresent(consumerID: String) throws -> StoredEffects? {
        guard fileManager.fileExists(atPath: effectsURL(consumerID: consumerID).path) else { return nil }
        return try loadEffects(consumerID: consumerID)
    }

    private func loadEffects(consumerID: String) throws -> StoredEffects {
        let url = effectsURL(consumerID: consumerID)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize,
              size > 0, size <= Self.maximumStoredBytes else {
            throw IntegrationEventFailureV1.limitExceeded
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(StoredEffects.self, from: data)
        guard try WorkspaceMutationCanonicalV1.data(value) == data else {
            throw IntegrationEventFailureV1.invalidDigest
        }
        try value.validate(expectedGenerationID: generationID,
                           expectedWorkspaceID: workspaceID,
                           expectedConsumerID: consumerID,
                           maximumStoredEvents: maximumStoredEvents)
        return value
    }

    private func requireScope(consumerID: String, workspaceID: WorkspaceID) throws {
        guard workspaceID == self.workspaceID,
              !consumerID.isEmpty, consumerID.utf8.count <= 128 else {
            throw IntegrationEventFailureV1.wrongWorkspace
        }
    }

    private func stateURL(consumerID: String) -> URL {
        let digest = SHA256.hash(data: Data(consumerID.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return rootURL.appendingPathComponent("consumer-\(digest).json", isDirectory: false)
    }

    private func effectsURL(consumerID: String) -> URL {
        let digest = SHA256.hash(data: Data(consumerID.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return rootURL.appendingPathComponent("effects-\(digest).json", isDirectory: false)
    }
}
