import Foundation

private struct PrivacyTransformCanonicalManifestEnvelopeV1: Decodable {
    let policyID: UUID; let policyRevision: UInt64; let policySHA256: String
}
private struct PrivacyTransformCanonicalReviewEnvelopeV1: Decodable {
    let manifestID: UUID; let manifestRevision: UInt64; let manifestSHA256: String
    let policyID: UUID; let policyRevision: UInt64; let policySHA256: String
}

enum SurveyDefinitionBackupGraphClosureV1 {
    enum Failure: Error { case invalid }

    static func validate(
        identities: [SurveyDefinitionIdentityV1],
        releases: [SurveyDefinitionReleaseV1],
        history: MutationHistorySnapshotV1,
        expectedWorkspaceID: WorkspaceID?
    ) throws {
        guard Set(identities.map(\.definitionID)).count == identities.count,
              Set(releases.map(\.releaseID)).count == releases.count else {
            throw Failure.invalid
        }
        let identityByID = Dictionary(uniqueKeysWithValues: identities.map { ($0.definitionID, $0) })
        let releaseByID = Dictionary(uniqueKeysWithValues: releases.map { ($0.releaseID, $0) })
        let workspaceIDs = Set(identities.map(\.workspaceID) + releases.map(\.workspaceID))
        guard workspaceIDs.count <= 1,
              expectedWorkspaceID.map({ workspaceIDs.isEmpty || workspaceIDs == Set([$0]) }) ?? true else {
            throw Failure.invalid
        }

        var mutations: [SurveyDefinitionMutationV1] = []
        for record in history.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            guard case let .applySurveyDefinition(mutation) = envelope.command else { continue }
            try mutation.validate()
            guard envelope.workspaceID == mutation.workspaceID,
                  envelope.mutationID == mutation.mutationID,
                  expectedWorkspaceID.map({ envelope.workspaceID == $0 }) ?? true,
                  let storedIdentity = identityByID[mutation.identity.definitionID],
                  let storedRelease = releaseByID[mutation.release.releaseID],
                  storedRelease == mutation.release,
                  mutation.identity.workspaceID == storedIdentity.workspaceID,
                  mutation.identity.activityKind == storedIdentity.activityKind,
                  mutation.identity.createdBy == storedIdentity.createdBy,
                  mutation.identity.createdAt == storedIdentity.createdAt,
                  mutation.event.workspaceID == mutation.workspaceID,
                  mutation.event.definitionID == mutation.identity.definitionID,
                  mutation.event.mutationID == mutation.mutationID,
                  mutation.event.release == (try SurveyDefinitionReleaseReferenceV1(storedRelease)) else {
                throw Failure.invalid
            }
            mutations.append(mutation)
        }
        let events = mutations.map(\.event)
        guard Set(events.map(\.eventID)).count == events.count,
              Set(events.map { $0.mutationID.rawValue }).count == events.count else {
            throw Failure.invalid
        }
        let eventByID = Dictionary(uniqueKeysWithValues: events.map { ($0.eventID, $0) })
        let mutationByEventID = Dictionary(uniqueKeysWithValues: mutations.map { ($0.event.eventID, $0) })

        var releaseChildCount: [UUID: Int] = [:]
        for release in releases {
            guard let identity = identityByID[release.definitionID],
                  identity.workspaceID == release.workspaceID else { throw Failure.invalid }
            if let predecessorID = release.supersedesReleaseID {
                guard let predecessor = releaseByID[predecessorID] else { throw Failure.invalid }
                try release.validateSuccessor(of: predecessor)
                releaseChildCount[predecessorID, default: 0] += 1
                guard releaseChildCount[predecessorID] == 1 else { throw Failure.invalid }
            }
        }

        var eventChildCount: [UUID: Int] = [:]
        for event in events {
            guard let identity = identityByID[event.definitionID],
                  identity.workspaceID == event.workspaceID,
                  let release = releaseByID[event.release.releaseID] else { throw Failure.invalid }
            try event.validate(release: release)
            if let predecessorID = event.predecessorEventID {
                guard let predecessor = eventByID[predecessorID] else { throw Failure.invalid }
                try event.validateSuccessor(of: predecessor, release: release)
                eventChildCount[predecessorID, default: 0] += 1
                guard eventChildCount[predecessorID] == 1 else { throw Failure.invalid }
            }
        }

        for identity in identities {
            guard let release = releaseByID[identity.currentRelease.releaseID],
                  let event = eventByID[identity.latestLifecycleEventID],
                  let latestMutation = mutationByEventID[event.eventID],
                  latestMutation.identity == identity,
                  identity.latestLifecycleEventSHA256 == event.eventSHA256 else {
                throw Failure.invalid
            }
            try identity.validate(currentRelease: release, event: event)
            let definitionEvents = events.filter { $0.definitionID == identity.definitionID }
            let roots = definitionEvents.filter { $0.predecessorEventID == nil }
            let heads = definitionEvents.filter { eventChildCount[$0.eventID, default: 0] == 0 }
            guard roots.count == 1, heads.count == 1,
                  heads[0].eventID == identity.latestLifecycleEventID else { throw Failure.invalid }
            var visitedEvents = Set<UUID>()
            var eventCursor: SurveyDefinitionLifecycleEventV1? = event
            while let current = eventCursor {
                guard visitedEvents.insert(current.eventID).inserted else { throw Failure.invalid }
                eventCursor = current.predecessorEventID.flatMap { eventByID[$0] }
            }
            guard visitedEvents.count == definitionEvents.count else { throw Failure.invalid }

            let definitionReleases = releases.filter { $0.definitionID == identity.definitionID }
            let releaseRoots = definitionReleases.filter { $0.supersedesReleaseID == nil }
            let releaseHeads = definitionReleases.filter { releaseChildCount[$0.releaseID, default: 0] == 0 }
            guard releaseRoots.count == 1, releaseHeads.count == 1,
                  releaseHeads[0].releaseID == identity.currentRelease.releaseID else { throw Failure.invalid }
            var visitedReleases = Set<UUID>()
            var releaseCursor: SurveyDefinitionReleaseV1? = release
            while let current = releaseCursor {
                guard visitedReleases.insert(current.releaseID).inserted else { throw Failure.invalid }
                releaseCursor = current.supersedesReleaseID.flatMap { releaseByID[$0] }
            }
            guard visitedReleases.count == definitionReleases.count else { throw Failure.invalid }
        }

        guard events.allSatisfy({ identityByID[$0.definitionID] != nil }),
              releases.allSatisfy({ identityByID[$0.definitionID] != nil }),
              Set(events.map(\.release.releaseID)) == Set(releases.map(\.releaseID)),
              identities.isEmpty == releases.isEmpty,
              identities.isEmpty == events.isEmpty else { throw Failure.invalid }

        var expectedRevisions: [String: UInt64] = [:]
        for identity in identities {
            let key = try WorkspaceEntityIdentityV1(kind: .surveyDefinitionIdentity, id: identity.definitionID).stableKey
            guard expectedRevisions.updateValue(identity.revision, forKey: key) == nil else { throw Failure.invalid }
        }
        for release in releases {
            let key = try WorkspaceEntityIdentityV1(kind: .surveyDefinitionRelease, id: release.releaseID).stableKey
            guard expectedRevisions.updateValue(release.revision, forKey: key) == nil else { throw Failure.invalid }
        }
        var actualRevisions: [String: UInt64] = [:]
        for value in history.entityRevisions where value.identity.kind == .surveyDefinitionIdentity || value.identity.kind == .surveyDefinitionRelease {
            guard actualRevisions.updateValue(value.revision, forKey: value.identity.stableKey) == nil else { throw Failure.invalid }
        }
        guard actualRevisions == expectedRevisions else { throw Failure.invalid }
    }
}

enum C30EvidenceContextBackupDecoderV1 {
    static func decode(_ record: V30BackupEvidenceContextRecordV1)
        throws -> EvidenceContextBackupRecordSetV1 {
        try EvidenceContextBackupRecordSetV1.decode([record])
    }

    static func decode(_ records: [V30BackupEvidenceContextRecordV1])
        throws -> EvidenceContextBackupRecordSetV1 {
        try EvidenceContextBackupRecordSetV1.decode(records)
    }
}

struct BackupCanonicalDecoderV1: Sendable {
    func decodeManifestOffMain(
        _ data: Data,
        context: ResumableLocalJobExecutionContextV1? = nil
    ) async throws -> V4BackupManifestV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let value = try await BackupOffMainWorkV1.run {
            try Self().decodeManifest(data)
        }
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        return value
    }

    func decodeRecordsOffMain(
        _ data: Data,
        context: ResumableLocalJobExecutionContextV1? = nil
    ) async throws -> V4BackupRecordsV1 {
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        let value = try await BackupOffMainWorkV1.run {
            try Self().decodeRecords(data)
        }
        try await context?.cancellationBoundary()
        try context?.validateGenerationLease()
        return value
    }

    func decodeManifest(_ data: Data) throws -> V4BackupManifestV1 {
        do {
            let value = try decoder().decode(V4BackupManifestV1.self, from: data)
            let canonical = try BackupCanonicalEncoderV1().encodeManifest(value).data
            guard canonical == data else {
                throw BackupCanonicalDecodingErrorV1.invalidManifest
            }
            return value
        } catch {
            throw BackupCanonicalDecodingErrorV1.invalidManifest
        }
    }

    func decodeRecords(_ data: Data) throws -> V4BackupRecordsV1 {
        do {
            let value = try decoder().decode(V4BackupRecordsV1.self, from: data)
            try Self.validatePartyAccountability(value)
            try Self.validateAssetSemantics(value)
            try Self.validateAuthorityCriterion(value)
            try Self.validateFunctionalRelationships(value)
            try Self.validateEvidenceAssurance(value)
            try Self.validateInspectionReview(value)
            try Self.validateWorkPackets(value)
            try Self.validateFieldDrafts(value)
            try Self.validatePackageEvolution(value)
            try Self.validateMeasurementIntegrity(value)
            try Self.validatePrivacyTransforms(value)
            try Self.validateClientCapabilities(value)
            try Self.validateRecoverabilityReceipts(value)
            try Self.validateFieldReferences(value)
            try Self.validateAccessibleDocumentAssessments(value)
            try Self.validateSurveyDefinitions(value)
            try Self.validateGuidedSurveys(value)
            try Self.validateAssetLocators(value)
            try Self.validateSchedules(value)
            try Self.validatePlans(value)
            try Self.validatePlacementPoses(value)
            try Self.validateC30EvidenceContext(value)
            try Self.validateC31Lighting(value)
            let canonical = try BackupCanonicalEncoderV1().encodeRecords(value).data
            guard canonical == data else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            return value
        } catch {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }
}

private extension BackupCanonicalDecoderV1 {
    static func validateC30EvidenceContext(_ records: V4BackupRecordsV1) throws {
        do {
            try records.validateC30EvidenceContextClosure()
        } catch {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }

    static func validateC31Lighting(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 30 else {
            guard records.lighting.isEmpty else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            return
        }
        guard records.recordsSchemaVersion == 30 else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        do {
            try records.validateC31LightingClosure()
        } catch {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }

    static func validateGuidedSurveys(_ records:V4BackupRecordsV1)throws{
        guard records.recordsSchemaVersion>=24 else{guard records.guidedSurveys.isEmpty else{throw BackupCanonicalDecodingErrorV1.invalidRecords};return}
        guard (24...30).contains(records.recordsSchemaVersion) else{throw BackupCanonicalDecodingErrorV1.invalidRecords}
        if records.mutationHistory == nil {
            guard records.guidedSurveys.isEmpty else{throw BackupCanonicalDecodingErrorV1.invalidRecords}
            return
        }
        var keys=Set<String>(),sessions:[UUID:SurveySessionV1]=[:],captures:[UUID:FactCaptureV1]=[:],subjects:[UUID:ProvisionalSubjectV1]=[:],receipts:[UUID:SubjectPromotionReceiptV1]=[:],publications:[UUID:SurveyPublicationSnapshotV1]=[:]
        for record in records.guidedSurveys{
            guard keys.insert("\(record.kind.rawValue)|\(record.id.uuidString)").inserted else{throw BackupCanonicalDecodingErrorV1.invalidRecords}
            switch record.kind{
            case .session:
                let value=try SurveySessionCanonicalCodecV1.decode(SurveySessionV1.self,from:record.canonicalData);try value.validateIntrinsic();guard record.id==value.sessionID,record.workspaceID==value.workspaceID.rawValue,record.revision==value.revision,sessions.updateValue(value,forKey:value.sessionID)==nil else{throw BackupCanonicalDecodingErrorV1.invalidRecords}
            case .factCapture:
                let value=try SurveySessionCanonicalCodecV1.decode(FactCaptureV1.self,from:record.canonicalData);try value.validateIntrinsic();guard record.id==value.captureID,record.workspaceID==value.workspaceID.rawValue,record.revision==value.revision,captures.updateValue(value,forKey:value.captureID)==nil else{throw BackupCanonicalDecodingErrorV1.invalidRecords}
            case .provisionalSubject:
                let value=try SurveySessionCanonicalCodecV1.decode(ProvisionalSubjectV1.self,from:record.canonicalData);try value.validate();guard record.id==value.provisionalSubjectID,record.workspaceID==value.workspaceID.rawValue,record.revision==value.revision,subjects.updateValue(value,forKey:value.provisionalSubjectID)==nil else{throw BackupCanonicalDecodingErrorV1.invalidRecords}
            case .subjectPromotionReceipt:
                let value=try SurveySessionCanonicalCodecV1.decode(SubjectPromotionReceiptV1.self,from:record.canonicalData);try value.validateIntrinsic();guard record.id==value.receiptID,record.workspaceID==value.workspaceID.rawValue,record.revision==value.revision,receipts.updateValue(value,forKey:value.receiptID)==nil else{throw BackupCanonicalDecodingErrorV1.invalidRecords}
            case .publicationSnapshot:
                let value=try SurveySessionCanonicalCodecV1.decode(SurveyPublicationSnapshotV1.self,from:record.canonicalData);try value.validateIntrinsic();guard record.id==value.snapshotID,record.workspaceID==value.workspaceID.rawValue,record.revision==value.revision,publications.updateValue(value,forKey:value.snapshotID)==nil else{throw BackupCanonicalDecodingErrorV1.invalidRecords}
            }
        }
        let definitions=try records.surveyDefinitions.filter{$0.kind == .release}.map{try SurveyDefinitionCanonicalCodecV1.decode(SurveyDefinitionReleaseV1.self,from:$0.canonicalData)}
        let packageReleases=try records.packageEvolution.filter{$0.kind == .promotedRelease}.map{try PackageEvolutionCanonicalCodecV1.decode(PromotedPackageReleaseV1.self,from:$0.canonicalData).packageRelease}
        for session in sessions.values{guard let definition=definitions.first(where:{$0.releaseID==session.authority.definitionRelease.releaseID&&$0.releaseSHA256==session.authority.definitionRelease.releaseSHA256}),let packageRelease=packageReleases.first(where:{$0.packageReleaseID==session.authority.packageRelease.packageReleaseID})else{throw BackupCanonicalDecodingErrorV1.invalidRecords};try session.authority.validate(definition:definition,packageRelease:packageRelease);try session.validate(definition:definition);let ownCaptures=captures.values.filter{$0.sessionID==session.sessionID};try ownCaptures.forEach{try $0.validate(session:session,definition:definition)};for publication in publications.values where publication.sessionID==session.sessionID && publication.sessionRevision==session.revision{try publication.validate(session:session,definition:definition,captures:Array(ownCaptures))}}
        guard captures.values.allSatisfy({sessions[$0.sessionID] != nil}),publications.values.allSatisfy({sessions[$0.sessionID] != nil}),receipts.values.allSatisfy({Set($0.affectedSessionIDs).isSubset(of:Set(sessions.keys))}),sessions.values.allSatisfy({session in if case .provisional(let ref)=session.subject{return subjects[ref.provisionalSubjectID]?.reference==ref};return true})else{throw BackupCanonicalDecodingErrorV1.invalidRecords}
        var publicationChildren:[UUID:Int]=[:],receiptChildren:[UUID:Int]=[:]
        for value in publications.values{if let id=value.supersedesSnapshotID{guard let prior=publications[id],prior.sessionID==value.sessionID,prior.revision<UInt64.max,value.revision==prior.revision+1 else{throw BackupCanonicalDecodingErrorV1.invalidRecords};publicationChildren[id,default:0]+=1;guard publicationChildren[id]==1 else{throw BackupCanonicalDecodingErrorV1.invalidRecords}}}
        for value in receipts.values{if let id=value.predecessorReceiptID{guard let prior=receipts[id]else{throw BackupCanonicalDecodingErrorV1.invalidRecords};try value.validate(preview:value.reconstructedPreview,predecessor:prior);receiptChildren[id,default:0]+=1;guard receiptChildren[id]==1 else{throw BackupCanonicalDecodingErrorV1.invalidRecords}}}
        guard let history=records.mutationHistory else{throw BackupCanonicalDecodingErrorV1.invalidRecords}
        var historySessions:[UUID:SurveySessionV1]=[:],historyCaptures:[UUID:FactCaptureV1]=[:],historySubjects:[UUID:ProvisionalSubjectV1]=[:],historyReceipts:[UUID:SubjectPromotionReceiptV1]=[:],historyPublications:[UUID:SurveyPublicationSnapshotV1]=[:]
        func keepSession(_ value:SurveySessionV1)throws{if let existing=historySessions[value.sessionID],existing.revision==value.revision,existing != value{throw BackupCanonicalDecodingErrorV1.invalidRecords};if historySessions[value.sessionID].map({$0.revision<value.revision}) ?? true{historySessions[value.sessionID]=value}}
        func keepSubject(_ value:ProvisionalSubjectV1)throws{if let existing=historySubjects[value.provisionalSubjectID],existing.revision==value.revision,existing != value{throw BackupCanonicalDecodingErrorV1.invalidRecords};if historySubjects[value.provisionalSubjectID].map({$0.revision<value.revision}) ?? true{historySubjects[value.provisionalSubjectID]=value}}
        for record in history.receipts {
            let envelope=try MutationEnvelopeV1.decodeCanonical(from:record.envelopeData)
            guard case let .applySurveySession(mutation)=envelope.command else{continue}
            switch mutation.payload {
            case .applySession(let value,_,_): try keepSession(value)
            case .captureFact(let value,_,_,_):
                if let existing=historyCaptures[value.captureID],existing != value{throw BackupCanonicalDecodingErrorV1.invalidRecords}
                historyCaptures[value.captureID]=value
            case .applyProvisionalSubject(let value): try keepSubject(value)
            case .promoteSubject(let subject,let receipt,_,_):
                try keepSubject(subject)
                if let existing=historyReceipts[receipt.receiptID],existing != receipt{throw BackupCanonicalDecodingErrorV1.invalidRecords}
                historyReceipts[receipt.receiptID]=receipt
            case .publish(let session,let snapshot,_,_):
                try keepSession(session)
                if let existing=historyPublications[snapshot.snapshotID],existing != snapshot{throw BackupCanonicalDecodingErrorV1.invalidRecords}
                historyPublications[snapshot.snapshotID]=snapshot
            }
        }
        guard historySessions==sessions,historyCaptures==captures,historySubjects==subjects,
              historyReceipts==receipts,historyPublications==publications else{throw BackupCanonicalDecodingErrorV1.invalidRecords}
    }

    static func validateAssetLocators(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 25 else {
            guard records.assetLocators.isEmpty else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            return
        }
        guard records.recordsSchemaVersion <= 30 else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        var locators: [UUID: AssetLocatorV1] = [:]
        var receipts: [UUID: LocatorBindingReceiptV1] = [:]
        var keys = Set<String>()
        for record in records.assetLocators {
            guard record.id != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)),
                  record.workspaceID != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)),
                  record.revision > 0,
                  !record.canonicalData.isEmpty,
                  keys.insert("\(record.kind.rawValue)|\(record.id.uuidString.lowercased())").inserted else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            switch record.kind {
            case .locator:
                let value = try AssetLocatorCanonicalCodecV1.decode(
                    AssetLocatorV1.self, from: record.canonicalData
                )
                try value.validate()
                guard value.locatorID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision,
                      locators.updateValue(value, forKey: value.locatorID) == nil else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
            case .bindingReceipt:
                let value = try AssetLocatorCanonicalCodecV1.decode(
                    LocatorBindingReceiptV1.self, from: record.canonicalData
                )
                try value.validateIntrinsic()
                guard value.receiptID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision,
                      receipts.updateValue(value, forKey: value.receiptID) == nil else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
            }
        }
        guard records.assetLocators == records.assetLocators.sorted(by: {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }) else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        do {
            try AssetLocatorLifecycleClosureV1(
                locators: Array(locators.values), receipts: Array(receipts.values)
            ).validate()
        } catch {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }

    static func validateSchedules(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 26 else {
            guard records.schedules.isEmpty else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            return
        }
        guard (26...30).contains(records.recordsSchemaVersion) else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        guard records.schedules.count <= 200_000 else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        if !records.schedules.isEmpty {
            guard records.mutationHistory != nil else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        let ordered = records.schedules.sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        guard ordered == records.schedules else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        var rowKeys = Set<String>()
        var definitions: [UUID: ScheduleDefinitionReleaseV1] = [:]
        var history: [UUID: OccurrenceHistoryEventV1] = [:]
        for record in records.schedules {
            guard record.id != zero, record.workspaceID != zero,
                  record.revision > 0, record.revision <= UInt64(Int.max),
                  !record.canonicalData.isEmpty,
                  rowKeys.insert("\(record.kind.rawValue)|\(record.id.uuidString.lowercased())").inserted else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            do {
                switch record.kind {
                case .scheduleRelease:
                    let value = try ScheduleCanonicalCodecV1.decode(
                        ScheduleDefinitionReleaseV1.self, from: record.canonicalData
                    )
                    try value.validate()
                    guard value.releaseID == record.id,
                          value.workspaceID.rawValue == record.workspaceID,
                          value.revision == record.revision,
                          definitions.updateValue(value, forKey: value.releaseID) == nil else {
                        throw BackupCanonicalDecodingErrorV1.invalidRecords
                    }
                case .occurrenceHistory:
                    let value = try ScheduleCanonicalCodecV1.decode(
                        OccurrenceHistoryEventV1.self, from: record.canonicalData
                    )
                    try value.validateIntrinsic()
                    guard value.eventID == record.id,
                          value.workspaceID.rawValue == record.workspaceID,
                          value.revision == record.revision,
                          history.updateValue(value, forKey: value.eventID) == nil else {
                        throw BackupCanonicalDecodingErrorV1.invalidRecords
                    }
                }
            } catch let error as BackupCanonicalDecodingErrorV1 {
                throw error
            } catch {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
        for group in Dictionary(grouping: definitions.values, by: \.scheduleDefinitionID).values {
            let ordered = group.sorted { $0.revision < $1.revision }
            guard let first = ordered.first, first.revision == 1,
                  ordered.filter({ $0.supersedesReleaseID == nil }).count == 1 else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            var children = Set<UUID>()
            if ordered.count > 1 {
                for index in 1..<ordered.count {
                    let predecessor = ordered[index - 1]
                    let successor = ordered[index]
                    guard children.insert(predecessor.releaseID).inserted else {
                        throw BackupCanonicalDecodingErrorV1.invalidRecords
                    }
                    try successor.validateSuccessor(of: predecessor)
                }
            }
        }
        for event in history.values {
            guard let release = definitions[event.scheduleRelease.releaseID],
                  release.workspaceID == event.workspaceID,
                  release.releaseSHA256 == event.scheduleRelease.releaseSHA256,
                  release.revision == event.scheduleRelease.revision else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
        for group in Dictionary(grouping: history.values, by: \.occurrenceID).values {
            let ordered = group.sorted { $0.revision < $1.revision }
            guard let first = ordered.first, first.revision == 1,
                  first.predecessorEventID == nil,
                  first.predecessorEventSHA256 == nil else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            if ordered.count > 1 {
                for index in 1..<ordered.count {
                    let predecessor = ordered[index - 1]
                    let successor = ordered[index]
                    guard successor.predecessorEventID == predecessor.eventID,
                          successor.predecessorEventSHA256 == predecessor.eventSHA256 else {
                        throw BackupCanonicalDecodingErrorV1.invalidRecords
                    }
                    try successor.validate(predecessor: predecessor)
                }
            }
            guard Set(ordered.map(\.eventID)).count == ordered.count else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
    }

    static func validatePlans(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 27 else {
            guard records.plans.isEmpty else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            return
        }
        guard (27...30).contains(records.recordsSchemaVersion),
              records.mutationHistory != nil else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        do {
            try V28PlanImportBoundaryV1.validate(persistent: 28, records: 27)
            _ = try PlanBackupRecordSetV1.decode(records.plans)
        } catch {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }

    static func validatePlacementPoses(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 28 else {
            guard records.placementPoses.isEmpty else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            return
        }
        guard (28...30).contains(records.recordsSchemaVersion),
              records.mutationHistory != nil else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        do {
            try V29PlacementPoseImportBoundaryV1.validate(persistent: 29, records: 28)
            _ = try PlacementPoseBackupRecordSetV1.decode(records.placementPoses)
        } catch {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }

    static func validateSurveyDefinitions(_ records:V4BackupRecordsV1)throws{
        guard records.recordsSchemaVersion>=23 else{guard records.surveyDefinitions.isEmpty else{throw BackupCanonicalDecodingErrorV1.invalidRecords};return}
        guard (23...30).contains(records.recordsSchemaVersion),let history=records.mutationHistory else{throw BackupCanonicalDecodingErrorV1.invalidRecords}
        var releases:[UUID:SurveyDefinitionReleaseV1]=[:],identities:[UUID:SurveyDefinitionIdentityV1]=[:],keys=Set<String>()
        for record in records.surveyDefinitions where record.kind == .release{let value=try SurveyDefinitionCanonicalCodecV1.decode(SurveyDefinitionReleaseV1.self,from:record.canonicalData);try value.validate();guard record.id==value.releaseID,record.workspaceID==value.workspaceID.rawValue,record.revision==value.revision,keys.insert("release|\(record.id.uuidString)").inserted,releases.updateValue(value,forKey:value.releaseID)==nil else{throw BackupCanonicalDecodingErrorV1.invalidRecords}}
        for record in records.surveyDefinitions where record.kind == .identity {
            let value=try SurveyDefinitionCanonicalCodecV1.decode(SurveyDefinitionIdentityV1.self,from:record.canonicalData)
            guard record.id==value.definitionID,record.workspaceID==value.workspaceID.rawValue,
                  record.revision==value.revision,keys.insert("identity|\(record.id.uuidString)").inserted,
                  identities.updateValue(value,forKey:value.definitionID)==nil else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
        do {
            try SurveyDefinitionBackupGraphClosureV1.validate(
                identities:Array(identities.values),releases:Array(releases.values),
                history:history,expectedWorkspaceID:nil
            )
        } catch { throw BackupCanonicalDecodingErrorV1.invalidRecords }
    }
    static func validateAccessibleDocumentAssessments(_ records:V4BackupRecordsV1)throws{
        guard records.recordsSchemaVersion>=22 else{guard records.accessibleDocumentAssessments.isEmpty else{throw BackupCanonicalDecodingErrorV1.invalidRecords};return}
        guard (22...30).contains(records.recordsSchemaVersion) else{throw BackupCanonicalDecodingErrorV1.invalidRecords}
        var values:[UUID:AccessibleDocumentAssessmentReceiptV1]=[:],children:[UUID:Int]=[:]
        for record in records.accessibleDocumentAssessments{let value=try AccessibleDocumentCanonicalCodecV1.decode(AccessibleDocumentAssessmentReceiptV1.self,from:record.canonicalData);try value.validateIntrinsic();guard record.id==value.receiptID,record.workspaceID==value.workspaceID.rawValue,record.revision==value.revision,values.updateValue(value,forKey:value.receiptID)==nil else{throw BackupCanonicalDecodingErrorV1.invalidRecords}}
        for value in values.values{if let predecessorID=value.supersedesReceiptID{guard let predecessor=values[predecessorID],predecessor.workspaceID==value.workspaceID,predecessor.treeSHA256==value.treeSHA256,predecessor.outputSHA256==value.outputSHA256,predecessor.revision<UInt64.max,value.revision==predecessor.revision+1 else{throw BackupCanonicalDecodingErrorV1.invalidRecords};children[predecessorID,default:0]+=1;guard children[predecessorID]==1 else{throw BackupCanonicalDecodingErrorV1.invalidRecords}}else if value.revision != 1{throw BackupCanonicalDecodingErrorV1.invalidRecords}}
        for start in values.keys{var seen=Set<UUID>(),cursor:UUID?=start;while let id=cursor{guard seen.insert(id).inserted else{throw BackupCanonicalDecodingErrorV1.invalidRecords};cursor=values[id]?.supersedesReceiptID}}
    }
    static func validateFieldReferences(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 21 else {
            guard records.fieldReferences.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        var releases: [UUID: FieldReferenceReleaseV1] = [:]
        var bindings: [UUID: FieldReferenceBindingV1] = [:]
        var keys = Set<String>()
        for row in records.fieldReferences where row.kind == .release {
            let value = try FieldReferenceReleaseRow(
                FieldReferencePackCanonicalCodecV1.decode(FieldReferenceReleaseV1.self, from: row.canonicalData)
            ).value()
            guard row.id == value.releaseID, row.workspaceID == value.workspaceID.rawValue,
                  row.revision == value.revision, keys.insert("release|\(row.id)").inserted,
                  releases.updateValue(value, forKey: value.releaseID) == nil else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
        for row in records.fieldReferences where row.kind == .binding {
            let seed = try FieldReferencePackCanonicalCodecV1.decode(
                FieldReferenceBindingV1.self, from: row.canonicalData
            )
            guard let release = releases[seed.releaseID] else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            let value = try FieldReferenceBindingRow(seed, release: release).value(release: release)
            guard row.id == value.bindingID, row.workspaceID == value.workspaceID.rawValue,
                  row.revision == value.revision, keys.insert("binding|\(row.id)").inserted,
                  bindings.updateValue(value, forKey: value.bindingID) == nil else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }

        var releaseChildren: [UUID: Int] = [:]
        for value in releases.values {
            if let predecessorID = value.supersedesReleaseID {
                guard let predecessor = releases[predecessorID] else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
                try value.validateSuccessor(of: predecessor)
                releaseChildren[predecessorID, default: 0] += 1
                guard releaseChildren[predecessorID] == 1 else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
            } else if value.revision != 1 {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }

        var bindingChildren: [UUID: Int] = [:]
        for value in bindings.values {
            guard let release = releases[value.releaseID] else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            try value.validate(release: release)
            if let predecessorID = value.supersedesBindingID {
                guard let predecessor = bindings[predecessorID] else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
                // validateSuccessor enforces subject/workspace continuity and
                // rejects successors to immutable finalized bindings.
                try value.validateSuccessor(of: predecessor, release: release)
                bindingChildren[predecessorID, default: 0] += 1
                guard bindingChildren[predecessorID] == 1 else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
            } else if value.revision != 1 {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }

        try validateAcyclicPredecessors(
            Dictionary(uniqueKeysWithValues: releases.values.map { ($0.releaseID, $0.supersedesReleaseID) })
        )
        try validateAcyclicPredecessors(
            Dictionary(uniqueKeysWithValues: bindings.values.map { ($0.bindingID, $0.supersedesBindingID) })
        )
    }

    static func validateAcyclicPredecessors(_ predecessors: [UUID: UUID?]) throws {
        for start in predecessors.keys {
            var seen = Set<UUID>()
            var cursor: UUID? = start
            while let current = cursor {
                guard seen.insert(current).inserted else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
                cursor = predecessors[current] ?? nil
            }
        }
    }

    static func validateRecoverabilityReceipts(_ records:V4BackupRecordsV1)throws{
        guard records.recordsSchemaVersion>=20 else{guard records.recoverabilityReceipts.isEmpty else{throw BackupCanonicalDecodingErrorV1.invalidRecords};return}
        var keys=Set<UUID>()
        for record in records.recoverabilityReceipts{let value=try RecoverabilityVerificationReceiptRow(RecoverabilityVerificationCanonicalCodecV1.decode(RecoverabilityVerificationReceiptV1.self,from:record.canonicalData)).value();guard record.id==value.receiptID,record.workspaceID==value.workspaceID.rawValue,record.revision==value.revision,keys.insert(record.id).inserted else{throw BackupCanonicalDecodingErrorV1.invalidRecords}}
    }

    static func validateClientCapabilities(_ records:V4BackupRecordsV1)throws{
        guard records.recordsSchemaVersion>=19 else{guard records.clientCapabilities.isEmpty else{throw BackupCanonicalDecodingErrorV1.invalidRecords};return}
        let releases=try records.packageEvolution.filter{$0.kind == .promotedRelease}.map{try PackageEvolutionCanonicalCodecV1.decode(PromotedPackageReleaseV1.self,from:$0.canonicalData).packageRelease}
        let releaseIndex=Dictionary(uniqueKeysWithValues:releases.map{($0.packageReleaseID,$0)});var keys=Set<String>()
        func accept(_ row:V20BackupClientCapabilityRecordV1,_ id:UUID,_ workspaceID:WorkspaceID,_ revision:UInt64)throws{guard row.id==id,row.workspaceID==workspaceID.rawValue,row.revision==revision,keys.insert("\(row.kind.rawValue)|\(row.id.uuidString)").inserted else{throw BackupCanonicalDecodingErrorV1.invalidRecords}}
        let profiles=try Dictionary(uniqueKeysWithValues:records.clientCapabilities.filter{$0.kind == .profile}.map{row in let v=try ClientCapabilityProfileRow(ClientCapabilityCanonicalCodecV1.decode(ClientCapabilityProfileV1.self,from:row.canonicalData)).value();try accept(row,v.profileID,v.workspaceID,v.revision);return(v.profileID,v)})
        let policies=try Dictionary(uniqueKeysWithValues:records.clientCapabilities.filter{$0.kind == .policy}.map{row in let seed=try ClientCapabilityCanonicalCodecV1.decode(PackageLifecyclePolicyV1.self,from:row.canonicalData);guard let release=releaseIndex[seed.packageReleaseID]else{throw BackupCanonicalDecodingErrorV1.invalidRecords};let v=try PackageLifecyclePolicyRow(seed,release:release).value(release:release);try accept(row,v.policyID,v.workspaceID,v.revision);return(v.policyID,v)})
        let dispositions=try Dictionary(uniqueKeysWithValues:records.clientCapabilities.filter{$0.kind == .disposition}.map{row in let seed=try ClientCapabilityCanonicalCodecV1.decode(PackageLifecycleDispositionV1.self,from:row.canonicalData);guard let release=releaseIndex[seed.packageReleaseID]else{throw BackupCanonicalDecodingErrorV1.invalidRecords};let v=try PackageLifecycleDispositionRow(seed,release:release).value(release:release);try accept(row,v.dispositionID,v.workspaceID,v.revision);return(v.dispositionID,v)})
        for row in records.clientCapabilities where row.kind == .admissionDecision{let seed=try ClientCapabilityCanonicalCodecV1.decode(ClientCapabilityAdmissionDecisionV1.self,from:row.canonicalData);guard let profile=profiles[seed.profileID],let policy=policies[seed.policyID],let disposition=dispositions[seed.dispositionID],let release=releaseIndex[seed.packageReleaseID]else{throw BackupCanonicalDecodingErrorV1.invalidRecords};let v=try ClientCapabilityAdmissionDecisionRow(seed,profile:profile,policy:policy,disposition:disposition,release:release).value(profile:profile,policy:policy,disposition:disposition,release:release);try accept(row,v.decisionID,v.workspaceID,v.revision)}
    }

    static func validatePrivacyTransforms(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 18 else {
            guard records.privacyTransforms.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        var keys = Set<String>()
        func accept(_ record: V19BackupPrivacyTransformRecordV1, _ id: UUID, _ workspaceID: WorkspaceID, _ revision: UInt64) throws {
            guard id == record.id, workspaceID.rawValue == record.workspaceID, revision == record.revision,
                  keys.insert("\(record.kind.rawValue)|\(record.id.uuidString)").inserted else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
        }
        let policyPairs = try records.privacyTransforms.filter { $0.kind == .policy }.map { record -> (UUID, PrivacyTransformPolicyV1) in
            let value = try PrivacyTransformPolicyRow(PrivacyTransformCanonicalCodecV1.decodePolicy(from: record.canonicalData)).value()
            try accept(record, value.policyID, value.workspaceID, value.revision); return (value.policyID, value)
        }
        let policies = Dictionary(uniqueKeysWithValues: policyPairs)
        for record in records.privacyTransforms where record.kind == .region {
            let value = try PrivacyRegionRow(PrivacyTransformCanonicalCodecV1.decodeRegion(from: record.canonicalData)).value()
            try accept(record, value.regionID, value.workspaceID, value.revision)
        }
        let manifestPairs = try records.privacyTransforms.filter { $0.kind == .manifest }.map { record -> (UUID, PrivacyTransformManifestV1) in
            let reference = try JSONDecoder().decode(PrivacyTransformCanonicalManifestEnvelopeV1.self, from: record.canonicalData)
            guard let policy = policies[reference.policyID], policy.revision == reference.policyRevision, policy.policySHA256 == reference.policySHA256 else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            let provisional = try PrivacyTransformCanonicalCodecV1.decodeManifest(from: record.canonicalData, policy: policy)
            let value = try PrivacyTransformManifestRow(provisional).value(policy: policy)
            try accept(record, value.manifestID, value.workspaceID, value.revision); return (value.manifestID, value)
        }
        let manifests = Dictionary(uniqueKeysWithValues: manifestPairs)
        for record in records.privacyTransforms where record.kind == .reviewReceipt {
            let reference = try JSONDecoder().decode(PrivacyTransformCanonicalReviewEnvelopeV1.self, from: record.canonicalData)
            guard let manifest = manifests[reference.manifestID], manifest.revision == reference.manifestRevision, manifest.manifestSHA256 == reference.manifestSHA256,
                  let policy = policies[reference.policyID], policy.revision == reference.policyRevision, policy.policySHA256 == reference.policySHA256 else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            let provisional = try PrivacyTransformCanonicalCodecV1.decodeReview(from: record.canonicalData, manifest: manifest, policy: policy)
            let value = try PrivacyReviewReceiptRow(provisional).value(manifest: manifest, policy: policy)
            try accept(record, value.receiptID, value.workspaceID, value.revision)
        }
    }

    static func validateMeasurementIntegrity(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 17 else {
            guard records.measurementIntegrity.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        var keys = Set<String>()
        for record in records.measurementIntegrity {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .instrumentReference:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(InstrumentReferenceV1.self, from: record.canonicalData); identity = (v.referenceID, v.workspaceID, v.revision)
            case .calibrationSnapshot:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(CalibrationStatusSnapshotV1.self, from: record.canonicalData); identity = (v.snapshotID, v.workspaceID, v.revision)
            case .measurementCapture:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementCaptureV1.self, from: record.canonicalData); identity = (v.captureID, v.workspaceID, v.revision)
            case .measurementSeries:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementSeriesV1.self, from: record.canonicalData); identity = (v.snapshotID, v.workspaceID, v.revision)
            case .qualityAssessment:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementQualityAssessmentV1.self, from: record.canonicalData); identity = (v.assessmentID, v.workspaceID, v.revision)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision,
                  keys.insert("\(record.kind.rawValue)|\(record.id.uuidString)").inserted else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
    }

    static func validatePackageEvolution(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 16 else {
            guard records.packageEvolution.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        var keys = Set<String>()
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        for record in records.packageEvolution {
            guard record.id != zero, record.workspaceID != zero, record.revision > 0,
                  !record.canonicalData.isEmpty,
                  keys.insert("\(record.kind.rawValue)|\(record.id.uuidString)").inserted else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
    }

    static func validateFieldDrafts(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 15 else {
            guard records.fieldDrafts.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        for record in records.fieldDrafts {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .checkpoint:
                let v = try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self, from: record.canonicalData)
                identity = (v.draftID, v.workspaceID, v.draftRevision)
            case .stagingItem:
                let v = try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self, from: record.canonicalData)
                identity = (v.stageID, v.workspaceID, v.revision)
            case .commitSaga:
                let v = try FieldDraftCanonicalCodecV1.decode(DraftCommitSagaV1.self, from: record.canonicalData)
                identity = (v.sagaID, v.workspaceID, v.revision)
            case .contentReservation:
                let v = try FieldDraftCanonicalCodecV1.decode(DraftContentReservationV1.self, from: record.canonicalData)
                identity = (v.reservationID, v.workspaceID, v.revision)
            case .commitReceipt:
                let v = try FieldDraftCanonicalCodecV1.decode(DraftCommitReceiptV1.self, from: record.canonicalData)
                identity = (v.receiptID, v.workspaceID, v.revision)
            case .discardReceipt:
                let v = try FieldDraftCanonicalCodecV1.decode(DraftDiscardReceiptV1.self, from: record.canonicalData)
                identity = (v.receiptID, v.workspaceID, v.revision)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
    }

    static func validateWorkPackets(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 14 else {
            guard records.workPackets.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        for record in records.workPackets {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .manifest:
                let v = try WorkPacketCanonicalCodecV1.decode(WorkPacketManifestV1.self, from: record.canonicalData); identity=(v.manifestID,v.workspaceID,v.revision)
            case .claim:
                let v = try WorkPacketCanonicalCodecV1.decode(WorkItemClaimV1.self, from: record.canonicalData); identity=(v.claimID,v.workspaceID,v.revision)
            case .lease:
                let v = try WorkPacketCanonicalCodecV1.decode(WorkLeaseV1.self, from: record.canonicalData); identity=(v.leaseID,v.workspaceID,v.revision)
            case .release:
                let v = try WorkPacketCanonicalCodecV1.decode(WorkReleaseV1.self, from: record.canonicalData); identity=(v.releaseID,v.workspaceID,v.revision)
            case .handoff:
                let v = try WorkPacketCanonicalCodecV1.decode(WorkHandoffV1.self, from: record.canonicalData); identity=(v.handoffID,v.workspaceID,v.revision)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
        }
    }

    static func validateInspectionReview(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 13 else {
            guard records.inspectionReview.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        for record in records.inspectionReview {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .reviewTransition:
                let value = try InspectionReviewCanonicalCodecV1.decode(InspectionReviewTransitionV1.self, from: record.canonicalData)
                identity = (value.transitionID, value.workspaceID, value.revision)
            case .reviewDisposition:
                let value = try InspectionReviewCanonicalCodecV1.decode(ReviewDispositionV1.self, from: record.canonicalData)
                identity = (value.dispositionID, value.workspaceID, value.revision)
            case .changeRequest:
                let value = try InspectionReviewCanonicalCodecV1.decode(ChangeRequestV1.self, from: record.canonicalData)
                identity = (value.requestRevisionID, value.workspaceID, value.revision)
            case .correctiveActionPolicy:
                let value = try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionPolicyV1.self, from: record.canonicalData)
                identity = (value.releaseID, value.workspaceID, value.revision)
            case .correctiveActionEvent:
                let value = try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionEventV1.self, from: record.canonicalData)
                identity = (value.eventID, value.workspaceID, value.revision)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
        }
    }

    static func validateEvidenceAssurance(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 12 else {
            guard records.evidenceAssurance.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        for record in records.evidenceAssurance {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .visibility:
                let value = try EvidenceAssuranceCanonicalCodecV1.decode(EvidenceVisibilityV1.self, from: record.canonicalData)
                identity = (value.visibilityID, value.workspaceID, value.revision)
            case .evidenceLink:
                let value = try EvidenceAssuranceCanonicalCodecV1.decode(ClaimEvidenceLinkV1.self, from: record.canonicalData)
                identity = (value.linkID, value.workspaceID, value.revision)
            case .manifest:
                let value = try EvidenceAssuranceCanonicalCodecV1.decode(AssuranceManifestV1.self, from: record.canonicalData)
                identity = (value.manifestID, value.workspaceID, value.revision)
            case .attestation:
                let value = try EvidenceAssuranceCanonicalCodecV1.decode(AttestationV1.self, from: record.canonicalData)
                identity = (value.attestationID, value.workspaceID, value.revision)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
        }
    }

    static func validateFunctionalRelationships(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 11 else {
            guard records.functionalRelationships.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        for record in records.functionalRelationships {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .descriptor:
                let value = try FunctionalRelationshipCanonicalCodecV1.decode(FunctionalRelationshipTypeDescriptorV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.descriptorReleaseID, value.workspaceID, value.revision)
            case .event:
                let value = try FunctionalRelationshipCanonicalCodecV1.decode(AssetFunctionalRelationshipEventV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.eventID, value.workspaceID, value.revision)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
        }
    }

    static func validateAuthorityCriterion(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 10 else {
            guard records.authorityCriterion.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        for record in records.authorityCriterion {
            let identity: (UUID, WorkspaceID, Bool)
            switch record.kind {
            case .authoritySourceRelease:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(AuthoritySourceReleaseV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.releaseID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .requirementBasisBinding:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(RequirementBasisBindingV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.bindingID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .applicabilityContextSnapshot:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(ApplicabilityContextSnapshotV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.snapshotID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .assessmentScopeSnapshot:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(AssessmentScopeSnapshotV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.snapshotID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .severityScaleRelease:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(SeverityScaleReleaseV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.releaseID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .findingClassificationBinding:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(FindingClassificationBindingV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.bindingID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .measurementProtocolRelease:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(MeasurementProtocolReleaseV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.releaseID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .derivedFactEvaluatorDescriptor:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(DerivedFactEvaluatorDescriptorV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.descriptorID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            case .derivedFactProvenance:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(DerivedFactProvenanceV1.self, from: record.canonicalData)
                try value.validate(); identity = (value.provenanceID, value.workspaceID, try AuthorityCriterionCanonicalCodecV1.encode(value) == record.canonicalData)
            }
            guard identity.0 == record.id, identity.1.rawValue == record.workspaceID,
                  identity.2 else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
    }

    static func validateAssetSemantics(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 9 else {
            guard records.assetSemantics.isEmpty else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            return
        }
        for record in records.assetSemantics {
            let identity: (UUID, WorkspaceID, UInt64)
            switch record.kind {
            case .kindBindingEvent:
                let value = try AssetSemanticCanonicalCodecV1.decode(
                    AssetKindBindingEventV1.self, from: record.canonicalData
                )
                try value.validate(); identity = (value.eventID, value.workspaceID, value.revision)
            case .workflowCapabilityBindingEvent:
                let value = try AssetSemanticCanonicalCodecV1.decode(
                    AssetWorkflowCapabilityBindingEventV1.self, from: record.canonicalData
                )
                try value.validate(); identity = (value.eventID, value.workspaceID, value.revision)
            case .productIdentity:
                let value = try AssetSemanticCanonicalCodecV1.decode(
                    AssetProductIdentityV1.self, from: record.canonicalData
                )
                try value.validate(); identity = (value.identityID, value.workspaceID, value.revision)
            case .lifecycleEvent:
                let value = try AssetSemanticCanonicalCodecV1.decode(
                    AssetLifecycleEventV1.self, from: record.canonicalData
                )
                try value.validate()
                identity = (value.record.eventID, value.record.workspaceID, value.record.revision)
            case .successorLink:
                let value = try AssetSemanticCanonicalCodecV1.decode(
                    AssetSuccessorLinkV1.self, from: record.canonicalData
                )
                try value.validate(); identity = (value.linkID, value.workspaceID, value.revision)
            case .workSubjectScopeSnapshot:
                let value = try AssetSemanticCanonicalCodecV1.decode(
                    WorkSubjectScopeSnapshotV1.self, from: record.canonicalData
                )
                try value.validate()
                identity = (value.snapshotID, value.workspaceID, value.workspaceRevision)
            }
            guard identity.0 == record.id,
                  identity.1.rawValue == record.workspaceID,
                  identity.2 == record.revision else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
    }

    static func validatePartyAccountability(_ records: V4BackupRecordsV1) throws {
        guard records.recordsSchemaVersion >= 8 else {
            guard records.partyAccountability.isEmpty else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            return
        }
        var partyIDs = Set<UUID>()
        var roleValues: [SitePartyRoleEventV1] = []
        var actorValues: [UUID: ActorSnapshotV1] = [:]
        var qualificationValues: [UUID: QualificationSnapshotV1] = [:]
        var signoffValues: [SignoffSnapshotV1] = []
        for record in records.partyAccountability {
            switch record.kind {
            case .serviceParty:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    ServicePartyReferenceV1.self, from: record.canonicalData
                )
                guard value.partyID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision,
                      partyIDs.insert(value.partyID).inserted else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
            case .sitePartyRoleEvent:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    SitePartyRoleEventV1.self, from: record.canonicalData
                )
                guard value.eventID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
                roleValues.append(value)
            case .actorSnapshot:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    ActorSnapshotV1.self, from: record.canonicalData
                )
                guard value.snapshotID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      record.revision == nil,
                      actorValues.updateValue(value, forKey: value.snapshotID) == nil else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
            case .qualificationSnapshot:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    QualificationSnapshotV1.self, from: record.canonicalData
                )
                guard value.snapshotID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      record.revision == nil,
                      qualificationValues.updateValue(value, forKey: value.snapshotID) == nil else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
            case .signoffSnapshot:
                let value = try PartyAccountabilitySnapshotCodecV1.decode(
                    SignoffSnapshotV1.self, from: record.canonicalData
                )
                guard value.snapshotID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.subjectRevision == record.revision else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
                signoffValues.append(value)
            }
        }
        let siteIDs = Set(records.sites.map(\.id))
        guard roleValues.allSatisfy({
                  partyIDs.contains($0.partyID) && siteIDs.contains($0.siteID)
              }),
              actorValues.values.allSatisfy({ value in
                  value.actor.partyID.map(partyIDs.contains) ?? true
              }),
              signoffValues.allSatisfy({ value in
                  (value.roleAssertion.map {
                      actorValues[$0.actor.snapshotID] == $0.actor
                  } ?? true)
                    && (value.qualification.map {
                        qualificationValues[$0.snapshotID] == $0
                    } ?? true)
              }) else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }

    func decoder() -> JSONDecoder {
        let value = JSONDecoder()
        let timestampFormatter = Self.makeTimestampFormatter()
        value.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard Self.isCanonicalTimestamp(string),
                  let date = timestampFormatter.date(from: string),
                  timestampFormatter.string(from: date) == string else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected canonical RFC3339 UTC milliseconds"
                )
            }
            return date
        }
        return value
    }

    static func isCanonicalTimestamp(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 24 else { return false }
        let punctuation: [Int: UInt8] = [
            4: 0x2d,
            7: 0x2d,
            10: 0x54,
            13: 0x3a,
            16: 0x3a,
            19: 0x2e,
            23: 0x5a,
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

    static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        value.timeZone = TimeZone(secondsFromGMT: 0)
        return value
    }
}
