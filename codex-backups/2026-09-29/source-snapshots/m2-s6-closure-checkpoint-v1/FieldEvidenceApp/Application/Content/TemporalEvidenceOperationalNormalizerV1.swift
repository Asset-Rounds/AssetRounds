import Foundation

/// Canonical counter observation shared by genuine writer and cold-reader
/// sources. Deliberately cannot be passed as a writer expected revision.
struct TemporalNormalizationSourceRevisionV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let revision: UInt64
    let entityRevisions: [WorkspaceEntityRevisionV1]

    init(workspaceID: WorkspaceID, generationID: UUID,
         history: MutationHistorySnapshotV1) throws {
        guard generationID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              Set(history.entityRevisions.map(\.identity)).count == history.entityRevisions.count else {
            throw TemporalEvidenceContractFailureV1.staleSource
        }
        self.workspaceID = workspaceID
        self.generationID = generationID
        revision = history.workspaceRevision
        entityRevisions = history.entityRevisions.map {
            WorkspaceEntityRevisionV1(identity: $0.identity, revision: $0.revision)
        }.sorted { $0.identity.stableKey < $1.identity.stableKey }
    }
}

/// Full canonical observation, never cached mutation authority. No canonical
/// family or immutable receipt is filtered to make a cleanup admissible.
struct TemporalNormalizationCanonicalSnapshotV1: Sendable {
    let source: V4BackupSourceV1
    let records: V4BackupRecordsV1
    let recordsData: Data
    let semanticRecordsData: Data
    let history: MutationHistorySnapshotV1
    let workspaceIdentity: WorkspaceReplicaIdentityV1
    let generationID: UUID
    let revision: TemporalNormalizationSourceRevisionV1

    init(source: V4BackupSourceV1, records: V4BackupRecordsV1, recordsData: Data, semanticRecordsData: Data,
         history: MutationHistorySnapshotV1, workspaceIdentity: WorkspaceReplicaIdentityV1,
         generationID: UUID, revision: TemporalNormalizationSourceRevisionV1) throws {
        guard source.workspaceID == workspaceIdentity.workspaceID.rawValue,
              source.replicaID == workspaceIdentity.replicaID.rawValue,
              source.sourceGenerationID == generationID,
              source.recordsSchemaVersion == records.recordsSchemaVersion,
              BackupSchemaAdmissionV1.supports(backup: 4,
                  persistent: source.persistentSchemaVersion, records: records.recordsSchemaVersion),
              records.mutationHistory == history, records.deletionLedger != nil,
              revision.workspaceID == workspaceIdentity.workspaceID,
              revision.generationID == generationID,
              revision.revision == history.workspaceRevision,
              revision.entityRevisions == history.entityRevisions.map({
                  WorkspaceEntityRevisionV1(identity: $0.identity, revision: $0.revision)
              }).sorted(by: { $0.identity.stableKey < $1.identity.stableKey }),
              try BackupCanonicalEncoderV1().encodeRecords(records).data == recordsData,
              try BackupCanonicalEncoderV1().encodeSemanticRecords(records).data == semanticRecordsData,
              try BackupCanonicalDecoderV1().decodeRecords(recordsData) == records else {
            throw TemporalEvidenceContractFailureV1.staleSource
        }
        _ = try MutationJournalStoreV1.validatedImportedSnapshotFacts(history,
            sourcePersistentSchemaVersion: source.persistentSchemaVersion)
        self.source = source
        self.records = records; self.recordsData = recordsData
        self.semanticRecordsData = semanticRecordsData; self.history = history
        self.workspaceIdentity = workspaceIdentity; self.generationID = generationID
        self.revision = revision
    }
}

/// Decoded immutable history with exact envelope/receipt binding. This is an
/// observation only: it neither admits a source nor authorizes publication.
/// Every command, including commands unrelated to C33, remains retained for
/// the complete family projector. Historical workspace/generation identities
/// are preserved verbatim; restored history is never rebound here.
struct TemporalNormalizationHistoryObservationV1: Sendable {
    struct Entry: Sendable {
        let raw: MutationHistoryReceiptRecordV1
        let envelope: MutationEnvelopeV1
        let receipt: MutationReceiptV1
        let reversalBasis: ReversalBasisV1?
        let semanticReversal: SemanticReversalReceiptV1?
    }

    let importedValidationFacts: MutationHistoryImportedValidationFactsV1
    let history: MutationHistorySnapshotV1
    let entries: [Entry]

    init(history: MutationHistorySnapshotV1) throws {
        // Reuse the incumbent complete normalized-history predicate, not only
        // per-entry checks. These facts seal values, never accepted source ownership.
        importedValidationFacts = try MutationJournalStoreV1.validatedImportedSnapshotFacts(history)
        guard history.schemaVersion == MutationHistorySnapshotV1.schemaVersion else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        struct MutationKey: Hashable {
            let workspace: WorkspaceID
            let mutation: MutationIDV1
        }
        var mutations = Set<MutationKey>()
        var receiptIdentities = Set<String>()
        var result: [Entry] = []
        for raw in history.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: raw.envelopeData)
            let receipt = try MutationReceiptV1.decodeCanonical(from: raw.receiptData)
            try envelope.validate()
            try receipt.validate()
            guard try envelope.canonicalData() == raw.envelopeData,
                  try receipt.canonicalData() == raw.receiptData,
                  receipt.mutationID == envelope.mutationID,
                  receipt.identity.workspaceID == envelope.workspaceID,
                  receipt.identity.replicaID == envelope.replicaID,
                  receipt.envelopeSHA256 == (try envelope.canonicalSHA256()),
                  receipt.commandBodySHA256 == envelope.commandBodySHA256,
                  receipt.expectedRevision == envelope.expectedRevision,
                  receipt.contentDependencyIDs == envelope.contentDependencyIDs,
                  receipt.sourceKind == envelope.sourceKind,
                  receipt.causationMutationID == envelope.causationMutationID,
                  receipt.correlationID == envelope.correlationID,
                  mutations.insert(.init(workspace: envelope.workspaceID,
                                         mutation: envelope.mutationID)).inserted,
                  receiptIdentities.insert(receipt.identity.stableKey).inserted else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let basis = try raw.reversalBasisData.map { try ReversalBasisV1.decodeCanonical(from: $0) }
            if let basis {
                guard basis.targetMutationID == receipt.mutationID,
                      basis.targetReceiptIdentity == receipt.identity,
                      envelope.reversalPlanDigest == basis.planDigest else {
                    throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                }
            } else if envelope.reversalPlanDigest != nil {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let reversal = try raw.semanticReversalData.map {
                try SemanticReversalReceiptV1.decodeCanonical(from: $0)
            }
            if let reversal {
                guard let execution = envelope.semanticReversalExecution,
                      receipt.reversesMutationID == reversal.reversesMutationID,
                      receipt.identity == reversal.reversalReceiptIdentity,
                      reversal.resultingRevision == receipt.resultingRevision,
                      execution.targetMutationID == reversal.reversesMutationID,
                      execution.targetReceiptIdentity == reversal.targetReceiptIdentity,
                      execution.reversalBasisSHA256 == reversal.reversalBasisSHA256,
                      execution.planDigest == reversal.planDigest,
                      execution.compensatingMutationIDs == reversal.compensatingMutationIDs else {
                    throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                }
            } else if receipt.reversesMutationID != nil || envelope.semanticReversalExecution != nil {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            result.append(.init(raw: raw, envelope: envelope, receipt: receipt,
                                reversalBasis: basis, semanticReversal: reversal))
        }
        self.history = history
        entries = result
    }
}

/// C33's typed contribution to the eventual all-family reference closure.
/// Deliberately has no `isUnreferenced`, removal decision, or publication API.
/// Other families and operational owners remain required even when this
/// contribution is empty. Full values retain source namespace, locator, digest,
/// byte length, provenance, predecessor and command/receipt identity.
struct TemporalNormalizationTemporalReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonicalClip(UUID, source: TemporalNormalizationCanonicalSnapshotV1)
        case canonicalAnchor(UUID, source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case clip(TemporalEvidenceClipV1)
        case anchor(TimecodedEvidenceAnchorV1)
        case derivative(TemporalEvidenceDerivativeV1)
        case captureReview(TemporalEvidenceCaptureReviewV1)
        case retention(TemporalEvidenceRetentionEventV1)
    }
    struct Observation: Sendable {
        let origin: Origin
        let value: Value
    }
    let observations: [Observation]

    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else {
            throw TemporalEvidenceContractFailureV1.staleSource
        }
        let canonical = try snapshot.records.validateC33TemporalEvidence()
        var result: [Observation] = []
        for clip in canonical.clips {
            try clip.validateIntrinsic()
            result.append(.init(origin: .canonicalClip(clip.clipID, source: snapshot), value: .clip(clip)))
        }
        for anchor in canonical.anchors {
            try anchor.validateIntrinsic()
            result.append(.init(origin: .canonicalAnchor(anchor.anchorID, source: snapshot), value: .anchor(anchor)))
        }
        for entry in history.entries {
            guard case let .applyTemporalEvidence(mutation) = entry.envelope.command else { continue }
            try mutation.validate()
            _ = try TemporalEvidenceMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
            let origin = Origin.immutableHistory(entry)
            func retain(_ value: Value) { result.append(.init(origin: origin, value: value)) }
            // Exhaustive typed traversal deliberately includes predecessor and
            // removed values. A current-row-only view loses immutable owners.
            switch mutation.payload {
            case let .acceptClip(clip, review, predecessor):
                retain(.clip(clip)); retain(.captureReview(review))
                if let predecessor { retain(.clip(predecessor)) }
            case let .appendAnchor(anchor, clip, predecessor):
                retain(.anchor(anchor)); retain(.clip(clip))
                if let predecessor { retain(.anchor(predecessor)) }
            case let .registerDerivative(clip, derivative, predecessorClip, predecessorDerivative):
                retain(.clip(clip)); retain(.derivative(derivative)); retain(.clip(predecessorClip))
                if let predecessorDerivative { retain(.derivative(predecessorDerivative)) }
            case let .applyRetention(clip, event, predecessorClip, predecessorEvent):
                retain(.clip(clip)); retain(.retention(event)); retain(.clip(predecessorClip))
                if let predecessorEvent { retain(.retention(predecessorEvent)) }
            case let .removeClip(event, clips, anchors, derivatives, predecessorEvent):
                retain(.retention(event))
                for clip in clips { retain(.clip(clip)) }
                for anchor in anchors { retain(.anchor(anchor)) }
                for derivative in derivatives { retain(.derivative(derivative)) }
                if let predecessorEvent { retain(.retention(predecessorEvent)) }
            }
        }
        observations = result
    }
}

/// All six draft row kinds are retained, including terminal rows. This does
/// not yet decode purpose-owned checkpoint payloads or immutable draft command
/// history, so it is not the complete draft reference closure and grants no
/// cleanup authority. Never interpret an empty direct ContentReference field
/// as absence of a lease, reservation, payload, saga or historical owner.
struct TemporalNormalizationDraftRowsV1: Sendable {
    enum Value: Sendable {
        case checkpoint(FieldDraftCheckpointV1)
        case stagingItem(AttachmentStagingItemV1)
        case commitSaga(DraftCommitSagaV1)
        case contentReservation(DraftContentReservationV1)
        case commitReceipt(DraftCommitReceiptV1)
        case discardReceipt(DraftDiscardReceiptV1)
    }
    struct Observation: Sendable {
        let row: V16BackupFieldDraftRecordV1
        let value: Value
        let source: TemporalNormalizationCanonicalSnapshotV1
    }
    let observations: [Observation]

    init(snapshot: TemporalNormalizationCanonicalSnapshotV1) throws {
        var result: [Observation] = []
        // A typed tuple is not Hashable in supported Swift, so retain kind and
        // UUID in an explicit key instead of inventing a string byte identity.
        struct Key: Hashable { let kind: String; let id: UUID }
        var seen = Set<Key>()
        for row in snapshot.records.fieldDrafts {
            guard row.workspaceID == snapshot.workspaceIdentity.workspaceID.rawValue,
                  seen.insert(.init(kind: row.kind.rawValue, id: row.id)).inserted else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            let value: Value
            switch row.kind {
            case .checkpoint:
                let decoded = try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self, from: row.canonicalData)
                try decoded.validate()
                guard decoded.workspaceID.rawValue == row.workspaceID,
                      decoded.draftID == row.id, decoded.draftRevision == row.revision,
                      try FieldDraftCanonicalCodecV1.encode(decoded) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                value = .checkpoint(decoded)
            case .stagingItem:
                let decoded = try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self, from: row.canonicalData)
                try decoded.validate()
                guard decoded.workspaceID.rawValue == row.workspaceID,
                      decoded.stageID == row.id, decoded.revision == row.revision,
                      try FieldDraftCanonicalCodecV1.encode(decoded) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                value = .stagingItem(decoded)
            case .commitSaga:
                let decoded = try FieldDraftCanonicalCodecV1.decode(DraftCommitSagaV1.self, from: row.canonicalData)
                try decoded.validate()
                guard decoded.workspaceID.rawValue == row.workspaceID,
                      decoded.sagaID == row.id, decoded.revision == row.revision,
                      try FieldDraftCanonicalCodecV1.encode(decoded) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                value = .commitSaga(decoded)
            case .contentReservation:
                let decoded = try FieldDraftCanonicalCodecV1.decode(DraftContentReservationV1.self, from: row.canonicalData)
                try decoded.validate()
                guard decoded.workspaceID.rawValue == row.workspaceID,
                      decoded.reservationID == row.id, decoded.revision == row.revision,
                      try FieldDraftCanonicalCodecV1.encode(decoded) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                value = .contentReservation(decoded)
            case .commitReceipt:
                let decoded = try FieldDraftCanonicalCodecV1.decode(DraftCommitReceiptV1.self, from: row.canonicalData)
                try decoded.validate()
                guard decoded.workspaceID.rawValue == row.workspaceID,
                      decoded.receiptID == row.id, decoded.revision == row.revision,
                      try FieldDraftCanonicalCodecV1.encode(decoded) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                value = .commitReceipt(decoded)
            case .discardReceipt:
                let decoded = try FieldDraftCanonicalCodecV1.decode(DraftDiscardReceiptV1.self, from: row.canonicalData)
                try decoded.validate()
                guard decoded.workspaceID.rawValue == row.workspaceID,
                      decoded.receiptID == row.id, decoded.revision == row.revision,
                      try FieldDraftCanonicalCodecV1.encode(decoded) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                value = .discardReceipt(decoded)
            }
            result.append(.init(row: row, value: value, source: snapshot))
        }
        observations = result
    }
}

/// Field references and plans contribute exact typed document bindings. An
/// old manifest-only release stays a manifest-only observation: no original
/// descriptor is invented from its ID. Historic namespaces remain unchanged.
/// This contribution is not all-family reachability or publication authority.
struct TemporalNormalizationDocumentReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonicalFieldReference(V22BackupFieldReferenceRecordV1, source: TemporalNormalizationCanonicalSnapshotV1)
        case canonicalPlan(V28BackupPlanRecordV1, source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case release(FieldReferenceReleaseV1)
        case binding(FieldReferenceBindingV1)
        case document(PlanDocumentV1)
        case revision(PlanRevisionV1)
        case frame(SpatialReferenceFrameV1)
        case placement(PlanPlacementV1)
        case rebaseReceipt(RebaseReceiptV1)
        // Retain the complete admitted nested pose command; its independent
        // family contribution remains due, not silently classified byte-free.
        case rebasePoseEffects(PlacementPoseMutationV1)
    }
    struct Observation: Sendable {
        let origin: Origin
        let value: Value
    }
    enum ByteBinding: Sendable {
        case requiredManifest(workspace: WorkspaceID, release: FieldReferenceReleaseV1,
                              entry: ContentManifestEntryV1)
        case importedOriginal(release: FieldReferenceReleaseV1,
                              entry: FieldReferenceImportedContentV1.Entry)
        case planContent(workspace: WorkspaceID, revision: PlanRevisionV1,
                         binding: PlanContentBindingV1)
    }
    struct ByteObservation: Sendable {
        let origin: Origin
        let binding: ByteBinding
    }
    let observations: [Observation]
    let byteObservations: [ByteObservation]

    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else {
            throw TemporalEvidenceContractFailureV1.staleSource
        }
        let workspace = snapshot.workspaceIdentity.workspaceID
        var result: [Observation] = []
        var bytes: [ByteObservation] = []
        func retain(_ value: Value, origin: Origin) throws {
            result.append(.init(origin: origin, value: value))
            switch value {
            case let .release(release):
                try release.validate()
                for entry in release.manifest.entries {
                    bytes.append(.init(origin: origin, binding: .requiredManifest(
                        workspace: release.workspaceID, release: release, entry: entry)))
                }
                if let imported = release.importedContent {
                    try imported.validate(manifest: release.manifest)
                    for entry in imported.entries {
                        bytes.append(.init(origin: origin,
                            binding: .importedOriginal(release: release, entry: entry)))
                    }
                }
            case let .revision(revision):
                try revision.validateIntrinsic()
                bytes.append(.init(origin: origin, binding: .planContent(
                    workspace: revision.workspaceID, revision: revision,
                    binding: revision.contentBinding)))
                // Frames are embedded immutable plan-revision truth as well
                // as canonical transport rows; retain them in old history too.
                for frame in revision.spatialFrames {
                    try frame.validate()
                    result.append(.init(origin: origin, value: .frame(frame)))
                }
            case .binding:
                // Both canonical and history callers validate with the exact
                // release, because binding has no independent byte authority.
                break
            case let .document(value): try value.validateIntrinsic()
            case let .frame(value): try value.validate()
            case let .placement(value): try value.validateIntrinsic()
            case let .rebaseReceipt(value): try value.validateIntrinsic()
            case let .rebasePoseEffects(value): try value.validate()
            }
        }

        var releases: [UUID: FieldReferenceReleaseV1] = [:]
        var bindings: [UUID: FieldReferenceBindingV1] = [:]
        for row in snapshot.records.fieldReferences where row.kind == .release {
            let value = try FieldReferencePackCanonicalCodecV1.decode(
                FieldReferenceReleaseV1.self, from: row.canonicalData)
            try value.validate()
            guard row.workspaceID == workspace.rawValue,
                  value.workspaceID == workspace, row.id == value.releaseID,
                  row.revision == value.revision,
                  try FieldReferencePackCanonicalCodecV1.encode(value) == row.canonicalData,
                  releases.updateValue(value, forKey: value.releaseID) == nil else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
        }
        for row in snapshot.records.fieldReferences {
            let origin = Origin.canonicalFieldReference(row, source: snapshot)
            switch row.kind {
            case .release:
                guard let value = releases[row.id] else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.release(value), origin: origin)
            case .binding:
                let value = try FieldReferencePackCanonicalCodecV1.decode(
                    FieldReferenceBindingV1.self, from: row.canonicalData)
                guard let release = releases[value.releaseID],
                      row.workspaceID == workspace.rawValue,
                      value.workspaceID == workspace, row.id == value.bindingID,
                      row.revision == value.revision,
                      try FieldReferencePackCanonicalCodecV1.encode(value) == row.canonicalData,
                      bindings.updateValue(value, forKey: value.bindingID) == nil else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try value.validate(release: release)
                try retain(.binding(value), origin: origin)
            }
        }
        // Preserve the incumbent predecessor/unique-successor law. Strictly
        // increasing revision also precludes cycles, without a recursive walk.
        var releaseParents = Set<UUID>(), bindingParents = Set<UUID>()
        for value in releases.values {
            if let parent = value.supersedesReleaseID {
                guard let predecessor = releases[parent], releaseParents.insert(parent).inserted else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try value.validateSuccessor(of: predecessor)
            } else if value.revision != 1 {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
        }
        for value in bindings.values {
            if let parent = value.supersedesBindingID {
                guard let predecessor = bindings[parent], let release = releases[value.releaseID],
                      bindingParents.insert(parent).inserted else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try value.validateSuccessor(of: predecessor, release: release)
            } else if value.revision != 1 {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
        }

        // Incumbent decoder validates all five kinds and their exact immutable
        // document/revision/frame/placement/rebase lifecycle before projection.
        let planSet = try PlanBackupRecordSetV1.decode(snapshot.records.plans)
        var embeddedFrames: [UUID: SpatialReferenceFrameV1] = [:]
        var frameOwnerRevisions: [UUID: Set<UInt64>] = [:]
        for revision in planSet.revisions {
            for frame in revision.spatialFrames {
                if let prior = embeddedFrames[frame.frameID], prior != frame {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                embeddedFrames[frame.frameID] = frame
                frameOwnerRevisions[frame.frameID, default: []].insert(revision.revision)
            }
        }
        for row in snapshot.records.plans {
            guard row.workspaceID == workspace.rawValue else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            let origin = Origin.canonicalPlan(row, source: snapshot)
            switch row.kind {
            case .document:
                let value = try PlanCanonicalCodecV1.decode(PlanDocumentV1.self, from: row.canonicalData)
                guard try PlanCanonicalCodecV1.encode(value) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.document(value), origin: origin)
            case .revision:
                let value = try PlanCanonicalCodecV1.decode(PlanRevisionV1.self, from: row.canonicalData)
                guard try PlanCanonicalCodecV1.encode(value) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.revision(value), origin: origin)
            case .spatialFrame:
                let value = try PlanCanonicalCodecV1.decode(SpatialReferenceFrameV1.self, from: row.canonicalData)
                guard embeddedFrames[value.frameID] == value,
                      frameOwnerRevisions[value.frameID]?.contains(row.revision) == true,
                      try PlanCanonicalCodecV1.encode(value) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.frame(value), origin: origin)
            case .placement:
                let value = try PlanCanonicalCodecV1.decode(PlanPlacementV1.self, from: row.canonicalData)
                guard try PlanCanonicalCodecV1.encode(value) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.placement(value), origin: origin)
            case .rebaseReceipt:
                let value = try PlanCanonicalCodecV1.decode(RebaseReceiptV1.self, from: row.canonicalData)
                guard try PlanCanonicalCodecV1.encode(value) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.rebaseReceipt(value), origin: origin)
            }
        }

        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .applyFieldReference(mutation):
                try mutation.validate()
                _ = try FieldReferenceMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                switch mutation {
                case let .importRelease(release):
                    try retain(.release(release), origin: origin)
                case let .bind(value, release):
                    try retain(.binding(value), origin: origin)
                    try retain(.release(release), origin: origin)
                }
            case let .applyPlan(mutation):
                try mutation.validate()
                _ = try PlanMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                switch mutation.payload {
                case let .appendDocument(value, predecessor):
                    try retain(.document(value), origin: origin)
                    if let predecessor { try retain(.document(predecessor), origin: origin) }
                case let .appendRevision(value, predecessor, document):
                    try retain(.revision(value), origin: origin)
                    try retain(.document(document), origin: origin)
                    if let predecessor { try retain(.revision(predecessor), origin: origin) }
                case let .appendPlacement(value, predecessor, revision):
                    try retain(.placement(value), origin: origin)
                    try retain(.revision(revision), origin: origin)
                    if let predecessor { try retain(.placement(predecessor), origin: origin) }
                case let .applyRebase(revision, predecessorRevision, placements,
                                     predecessorPlacements, receipt, predecessorReceipt, poseEffects):
                    try retain(.revision(revision), origin: origin)
                    try retain(.revision(predecessorRevision), origin: origin)
                    for value in placements { try retain(.placement(value), origin: origin) }
                    for value in predecessorPlacements { try retain(.placement(value), origin: origin) }
                    try retain(.rebaseReceipt(receipt), origin: origin)
                    if let predecessorReceipt { try retain(.rebaseReceipt(predecessorReceipt), origin: origin) }
                    if let poseEffects { try retain(.rebasePoseEffects(poseEffects), origin: origin) }
                case let .recordRebaseRejection(receipt, predecessorReceipt):
                    try retain(.rebaseReceipt(receipt), origin: origin)
                    if let predecessorReceipt { try retain(.rebaseReceipt(predecessorReceipt), origin: origin) }
                }
            default:
                // Kept in history.entries for other typed contributors. This
                // is not a classification that the command has no references.
                continue
            }
        }
        observations = result
        byteObservations = bytes
    }
}

/// Privacy projection eligibility is intentionally irrelevant to reachability:
/// rejected, stale, superseded and unreviewed manifests still retain both byte
/// identities. No audience filter may turn an original into an orphan.
struct TemporalNormalizationPrivacyReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonical(V19BackupPrivacyTransformRecordV1, source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case policy(PrivacyTransformPolicyV1)
        case region(PrivacyRegionV1)
        case manifest(PrivacyTransformManifestV1, policy: PrivacyTransformPolicyV1)
        case review(PrivacyReviewReceiptV1, manifest: PrivacyTransformManifestV1,
                    policy: PrivacyTransformPolicyV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    enum ByteBinding: Sendable {
        case regionSource(PrivacyRegionV1)
        case original(ContentReferenceV1, manifest: PrivacyTransformManifestV1)
        case derivative(ContentReferenceV1, manifest: PrivacyTransformManifestV1)
        case review(PrivacyReviewReceiptV1)
        case canonicalEvidence(ContentReferenceV1, file: V4BackupEvidenceFileDTO)
    }
    struct ByteObservation: Sendable { let origin: Origin; let binding: ByteBinding }
    let observations: [Observation]
    let byteObservations: [ByteObservation]

    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        let workspace = snapshot.workspaceIdentity.workspaceID
        var result: [Observation] = [], bytes: [ByteObservation] = []
        func retain(_ value: Value, origin: Origin) throws {
            switch value {
            case let .policy(policy):
                guard policy.schemaVersion == PrivacyTransformPolicyV1.schemaVersion else {
                    throw PrivacyTransformFailureV1.incompatibleVersion
                }
                try policy.validate()
            case let .region(region):
                guard region.schemaVersion == PrivacyRegionV1.schemaVersion else {
                    throw PrivacyTransformFailureV1.incompatibleVersion
                }
                try region.validate(); try region.bounds.validate()
                bytes.append(.init(origin: origin, binding: .regionSource(region)))
            case let .manifest(manifest, policy):
                try PrivacyTransformLifecycleClosureV1(policy: policy, regions: manifest.orderedRegions,
                    manifest: manifest, review: nil).validate()
                bytes.append(.init(origin: origin, binding: .original(manifest.original, manifest: manifest)))
                bytes.append(.init(origin: origin, binding: .derivative(manifest.derivative, manifest: manifest)))
                for region in manifest.orderedRegions {
                    try region.validate()
                    bytes.append(.init(origin: origin, binding: .regionSource(region)))
                }
            case let .review(review, manifest, policy):
                try PrivacyTransformLifecycleClosureV1(policy: policy, regions: manifest.orderedRegions,
                    manifest: manifest, review: review).validate()
                bytes.append(.init(origin: origin, binding: .review(review)))
            }
            result.append(.init(origin: origin, value: value))
        }
        var policies: [UUID: PrivacyTransformPolicyV1] = [:]
        var regions: [UUID: PrivacyRegionV1] = [:]
        var manifests: [UUID: PrivacyTransformManifestV1] = [:]
        var reviews: [UUID: PrivacyReviewReceiptV1] = [:]
        for row in snapshot.records.privacyTransforms {
            guard row.workspaceID == workspace.rawValue else { throw TemporalEvidenceContractFailureV1.staleSource }
            switch row.kind {
            case .policy:
                let value = try PrivacyTransformCanonicalCodecV1.decodePolicy(from: row.canonicalData)
                guard value.workspaceID == workspace, value.policyID == row.id, value.revision == row.revision,
                      policies.updateValue(value, forKey: value.policyID) == nil else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
            case .region:
                let value = try PrivacyTransformCanonicalCodecV1.decodeRegion(from: row.canonicalData)
                guard value.workspaceID == workspace, value.regionID == row.id, value.revision == row.revision,
                      regions.updateValue(value, forKey: value.regionID) == nil else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
            case .manifest, .reviewReceipt: break // Resolved against exact typed prerequisites below.
            }
        }
        for row in snapshot.records.privacyTransforms where row.kind == .manifest {
            let seed = try PrivacyTransformCanonicalCodecV1.decode(PrivacyTransformManifestV1.self,
                                                                   from: row.canonicalData)
            guard let policy = policies[seed.policyID] else { throw TemporalEvidenceContractFailureV1.staleSource }
            let value = try PrivacyTransformCanonicalCodecV1.decodeManifest(from: row.canonicalData, policy: policy)
            guard value.workspaceID == workspace, value.manifestID == row.id, value.revision == row.revision,
                  manifests.updateValue(value, forKey: value.manifestID) == nil else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
        }
        for row in snapshot.records.privacyTransforms where row.kind == .reviewReceipt {
            let seed = try PrivacyTransformCanonicalCodecV1.decode(PrivacyReviewReceiptV1.self,
                                                                   from: row.canonicalData)
            guard let policy = policies[seed.policyID], let manifest = manifests[seed.manifestID] else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            let value = try PrivacyTransformCanonicalCodecV1.decodeReview(from: row.canonicalData,
                                                                         manifest: manifest, policy: policy)
            guard value.workspaceID == workspace, value.receiptID == row.id, value.revision == row.revision,
                  reviews.updateValue(value, forKey: value.receiptID) == nil else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
        }
        // Exact current file metadata is retained as well as ContentReference.
        // This is the incumbent canonical privacy graph check, not file-open or
        // deletion authority. Historical content need not be a current row.
        let evidence = Dictionary(grouping: snapshot.records.evidenceFiles, by: \.id)
        func canonicalEvidence(_ reference: ContentReferenceV1) throws -> V4BackupEvidenceFileDTO {
            guard reference.workspaceID == workspace.rawValue.uuidString.lowercased(),
                  let id = UUID(uuidString: reference.contentID), let matches = evidence[id],
                  matches.count == 1, let file = matches.first,
                  let digest = reference.digests.digest(for: .sha256),
                  file.sha256 == digest.hexadecimalValue,
                  Int64(file.byteCount) == reference.byteLength, file.mimeType == reference.mediaType else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            return file
        }
        var usedRegions = Set<UUID>()
        for value in policies.values {
            if let id = value.supersedesPolicyID {
                guard let predecessor = policies[id] else { throw TemporalEvidenceContractFailureV1.staleSource }
                try value.validateSuccessor(of: predecessor)
            } else if value.revision != 1 { throw TemporalEvidenceContractFailureV1.staleSource }
        }
        for value in manifests.values {
            guard let policy = policies[value.policyID] else { throw TemporalEvidenceContractFailureV1.staleSource }
            for embedded in value.orderedRegions {
                guard regions[embedded.regionID] == embedded else { throw TemporalEvidenceContractFailureV1.staleSource }
                usedRegions.insert(embedded.regionID)
            }
            if let id = value.supersedesManifestID {
                guard let predecessor = manifests[id] else { throw TemporalEvidenceContractFailureV1.staleSource }
                try value.validateSuccessor(of: predecessor, policy: policy)
            } else if value.revision != 1 { throw TemporalEvidenceContractFailureV1.staleSource }
        }
        guard usedRegions == Set(regions.keys) else { throw TemporalEvidenceContractFailureV1.staleSource }
        for value in reviews.values {
            guard let manifest = manifests[value.manifestID], let policy = policies[value.policyID] else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            if let id = value.supersedesReceiptID {
                guard let predecessor = reviews[id] else { throw TemporalEvidenceContractFailureV1.staleSource }
                try value.validateSuccessor(of: predecessor, manifest: manifest, policy: policy)
            } else if value.revision != 1 { throw TemporalEvidenceContractFailureV1.staleSource }
        }
        // All predecessor validators require strictly increasing bounded
        // revision, which excludes cycles without recursive traversal.
        for row in snapshot.records.privacyTransforms {
            let origin = Origin.canonical(row, source: snapshot)
            switch row.kind {
            case .policy:
                guard let value = policies[row.id] else { throw TemporalEvidenceContractFailureV1.staleSource }
                try retain(.policy(value), origin: origin)
            case .region:
                guard let value = regions[row.id] else { throw TemporalEvidenceContractFailureV1.staleSource }
                try retain(.region(value), origin: origin)
            case .manifest:
                guard let value = manifests[row.id], let policy = policies[value.policyID] else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.manifest(value, policy: policy), origin: origin)
                for reference in [value.original, value.derivative] {
                    bytes.append(.init(origin: origin, binding: .canonicalEvidence(reference,
                        file: try canonicalEvidence(reference))))
                }
            case .reviewReceipt:
                guard let value = reviews[row.id], let manifest = manifests[value.manifestID],
                      let policy = policies[value.policyID] else { throw TemporalEvidenceContractFailureV1.staleSource }
                try retain(.review(value, manifest: manifest, policy: policy), origin: origin)
            }
        }
        for entry in history.entries {
            guard case let .applyPrivacyTransform(mutation) = entry.envelope.command else { continue }
            try mutation.validate()
            _ = try PrivacyTransformMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
            let origin = Origin.immutableHistory(entry)
            switch mutation {
            case let .policy(value):
                try retain(.policy(value), origin: origin)
            case let .publish(policy, regions, manifest):
                try retain(.policy(policy), origin: origin)
                for region in regions { try retain(.region(region), origin: origin) }
                try retain(.manifest(manifest, policy: policy), origin: origin)
            case let .review(value, manifest, policy):
                try retain(.policy(policy), origin: origin)
                try retain(.manifest(manifest, policy: policy), origin: origin)
                try retain(.review(value, manifest: manifest, policy: policy), origin: origin)
            }
        }
        observations = result; byteObservations = bytes
    }
}

/// Evidence reassignment/removal does not erase its previous content binding.
/// Keep full association and sequence-item provenance rather than reducing
/// these digest-bound relationships to a set of unqualified content IDs.
struct TemporalNormalizationEvidenceMetadataReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonicalAssociation(EvidenceAssociationV1, source: TemporalNormalizationCanonicalSnapshotV1)
        case canonicalSequence(EvidenceSequenceV1, source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case association(EvidenceAssociationV1)
        case sequence(EvidenceSequenceV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    enum ByteBinding: Sendable {
        case associationCurrent(EvidenceAssociationV1)
        case associationPrevious(EvidenceAssociationV1)
        case orderedItem(sequence: EvidenceSequenceV1, item: EvidenceSequenceItemV1)
    }
    struct ByteObservation: Sendable { let origin: Origin; let binding: ByteBinding }
    let observations: [Observation]
    let byteObservations: [ByteObservation]

    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        let events = snapshot.records.evidenceAssociationEvents
        let sequences = snapshot.records.evidenceSequenceRevisions
        let workspace = snapshot.workspaceIdentity.workspaceID
        guard events.allSatisfy({ $0.workspaceID == workspace.rawValue.uuidString.lowercased() }),
              sequences.allSatisfy({ $0.workspaceID == workspace }) else {
            throw TemporalEvidenceContractFailureV1.staleSource
        }
        try EvidenceMetadataGraphV1.validate(sequences: sequences, associationEvents: events)
        var result: [Observation] = [], bytes: [ByteObservation] = []
        func retainAssociation(_ event: EvidenceAssociationV1, origin: Origin) throws {
            // Closed typed decoding invokes the incumbent event constructor;
            // this does not search JSON or infer a reference from its spelling.
            let checked = try EvidenceMetadataCanonicalCodecV1.decode(EvidenceAssociationV1.self,
                from: EvidenceMetadataCanonicalCodecV1.data(event))
            guard checked == event else { throw TemporalEvidenceContractFailureV1.staleSource }
            result.append(.init(origin: origin, value: .association(event)))
            if event.contentID != nil {
                bytes.append(.init(origin: origin, binding: .associationCurrent(event)))
            }
            if event.previousContentID != nil {
                bytes.append(.init(origin: origin, binding: .associationPrevious(event)))
            }
        }
        func retainSequence(_ sequence: EvidenceSequenceV1, origin: Origin) throws {
            try sequence.validate()
            result.append(.init(origin: origin, value: .sequence(sequence)))
            for item in sequence.orderedItems {
                bytes.append(.init(origin: origin, binding: .orderedItem(sequence: sequence, item: item)))
            }
        }
        for event in events { try retainAssociation(event, origin: .canonicalAssociation(event, source: snapshot)) }
        for sequence in sequences { try retainSequence(sequence, origin: .canonicalSequence(sequence, source: snapshot)) }
        for entry in history.entries {
            guard case let .applyEvidenceMetadata(mutation) = entry.envelope.command else { continue }
            try mutation.validate()
            _ = try EvidenceMetadataMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
            let origin = Origin.immutableHistory(entry)
            try retainAssociation(mutation.associationEvent, origin: origin)
            try retainSequence(mutation.sequenceSuccessor, origin: origin)
        }
        observations = result; byteObservations = bytes
    }
}

/// Typed attachment observations only. Full family graph/current-history resolution
/// and physical source authority are still required; this type grants no absence,
/// removal, publication, or reference-closure capability.
struct TemporalNormalizationAuthorityMeasurementReferencesV1: Sendable {
    enum Origin: Sendable {
        case authorityRow(V11BackupAuthorityCriterionRecordV1, source: TemporalNormalizationCanonicalSnapshotV1)
        case measurementRow(V18BackupMeasurementIntegrityRecordV1, source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Equatable, Sendable {
        case authoritySourceRelease(AuthoritySourceReleaseV1)
        case requirementBasisBinding(RequirementBasisBindingV1)
        case applicabilityContextSnapshot(ApplicabilityContextSnapshotV1)
        case assessmentScopeSnapshot(AssessmentScopeSnapshotV1)
        case severityScaleRelease(SeverityScaleReleaseV1)
        case findingClassificationBinding(FindingClassificationBindingV1)
        case measurementProtocolRelease(MeasurementProtocolReleaseV1)
        case derivedFactEvaluatorDescriptor(DerivedFactEvaluatorDescriptorV1)
        case derivedFactProvenance(DerivedFactProvenanceV1)
        case instrumentReference(InstrumentReferenceV1)
        case calibrationSnapshot(CalibrationStatusSnapshotV1)
        case measurementCapture(MeasurementCaptureV1)
        case measurementSeries(MeasurementSeriesV1)
        case qualityAssessment(MeasurementQualityAssessmentV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    enum ByteBinding: Sendable {
        case authorityContent(source: AuthoritySourceReleaseV1, reference: ContentReferenceV1)
        case authorityLocator(source: AuthoritySourceReleaseV1, locator: ContentLocatorV1)
        case calibrationSource(calibration: CalibrationStatusSnapshotV1, reference: ContentReferenceV1)
        case captureEvidence(capture: MeasurementCaptureV1, reference: ContentReferenceV1)
        case qualityEvidence(assessment: MeasurementQualityAssessmentV1, reference: ContentReferenceV1)
    }
    struct ByteObservation: Sendable { let origin: Origin; let binding: ByteBinding }
    /// Immutable object identity spans physical generations in one workspace,
    /// as in the incumbent normalized-history reader. Each origin still retains
    /// its exact generation; no cross-workspace rebinding is performed here.
    struct Namespace: Hashable, Sendable {
        let workspaceID: WorkspaceID
    }
    enum Identity: Hashable, Sendable {
        case authoritySourceRelease(UUID)
        case requirementBasisBinding(UUID)
        case applicabilityContextSnapshot(UUID)
        case assessmentScopeSnapshot(UUID)
        case severityScaleRelease(UUID)
        case findingClassificationBinding(UUID)
        case measurementProtocolRelease(UUID)
        case derivedFactEvaluatorDescriptor(UUID)
        case derivedFactProvenance(UUID)
        case instrumentReference(UUID)
        case calibrationSnapshot(UUID)
        case measurementCapture(UUID)
        case measurementSeries(UUID)
        case qualityAssessment(UUID)
    }
    enum PredecessorResolution: Sendable {
        case root
        case resolved(Value, origins: [Observation])
        case unresolved(Identity)
    }
    struct PredecessorObservation: Sendable {
        let owner: Observation
        let namespace: Namespace
        let resolution: PredecessorResolution
    }
    /// Unresolved entries are retained obligations, never permission to remove.
    enum Requirement: Sendable {
        case family(Identity)
        case actor(UUID)
        case qualification(UUID)
        case workScope(UUID)
        case qualitySeries(MeasurementQualityAssessmentV1)
    }
    enum GraphResolution: Sendable {
        case validatedTypedGraph
        case unresolved([Requirement])
    }
    struct NamespaceGraphObservation: Sendable {
        let namespace: Namespace
        let inputs: [Observation]
        let externalInputs: [ExternalObservation]
        let authority: GraphResolution
        let measurement: GraphResolution
    }
    enum ExternalValue: Equatable, Sendable {
        case actor(ActorSnapshotV1)
        case qualification(QualificationSnapshotV1)
        case workScope(WorkSubjectScopeSnapshotV1)
    }
    enum ExternalOrigin: Sendable {
        case canonicalParty(V9BackupPartyAccountabilityRecordV1, source: TemporalNormalizationCanonicalSnapshotV1)
        case canonicalAsset(V10BackupAssetSemanticRecordV1, source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    struct ExternalObservation: Sendable {
        let namespace: Namespace
        let origin: ExternalOrigin
        let value: ExternalValue
    }
    let externalObservations: [ExternalObservation]
    /// These are pure graph results, not admitted source or byte capabilities.
    let namespaceGraphs: [NamespaceGraphObservation]
    let predecessors: [PredecessorObservation]
    let observations: [Observation]
    let byteObservations: [ByteObservation]

    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        let graphValidator = BackupPackageValidatorV1()
        try graphValidator.validateAuthorityCriterionGraph(snapshot.records,
            workspaceID: snapshot.workspaceIdentity.workspaceID.rawValue)
        try graphValidator.validateMeasurementIntegrityGraph(snapshot.records,
            rawWorkspaceID: snapshot.workspaceIdentity.workspaceID.rawValue)
        var result: [Observation] = [], bytes: [ByteObservation] = []
        func retain(_ value: Value, origin: Origin) throws {
            switch value {
            case let .authoritySourceRelease(v):
                try v.validate()
                if let reference = v.lawfulContentReference {
                    bytes.append(.init(origin: origin, binding: .authorityContent(source: v, reference: reference)))
                }
                if let locator = v.contentLocator {
                    bytes.append(.init(origin: origin, binding: .authorityLocator(source: v, locator: locator)))
                }
            case let .requirementBasisBinding(v):
                try v.validate()
            case let .applicabilityContextSnapshot(v):
                try v.validate()
            case let .assessmentScopeSnapshot(v):
                try v.validate()
            case let .severityScaleRelease(v):
                try v.validate()
            case let .findingClassificationBinding(v):
                try v.validate()
            case let .measurementProtocolRelease(v):
                try v.validate()
            case let .derivedFactEvaluatorDescriptor(v):
                try v.validate()
            case let .derivedFactProvenance(v):
                try v.validate()
            case let .instrumentReference(v):
                try v.validate()
            case let .calibrationSnapshot(v):
                try v.validate()
                if let reference = v.sourceReference {
                    bytes.append(.init(origin: origin, binding: .calibrationSource(calibration: v, reference: reference)))
                }
            case let .measurementCapture(v):
                try v.validate()
                for reference in v.evidence {
                    bytes.append(.init(origin: origin, binding: .captureEvidence(capture: v, reference: reference)))
                }
            case let .measurementSeries(v):
                try v.validate()
            case let .qualityAssessment(v):
                try v.validate()
                for reference in v.evidence {
                    bytes.append(.init(origin: origin, binding: .qualityEvidence(assessment: v, reference: reference)))
                }
            }
            result.append(.init(origin: origin, value: value))
        }
        var authorityKeys = Set<String>()
        for row in snapshot.records.authorityCriterion {
            guard row.workspaceID == snapshot.workspaceIdentity.workspaceID.rawValue,
                  authorityKeys.insert(row.kind.rawValue + "\0" + row.id.uuidString).inserted else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            switch row.kind {
            case .authoritySourceRelease:
                let v = try AuthorityCriterionCanonicalCodecV1.decode(AuthoritySourceReleaseV1.self, from: row.canonicalData)
                guard v.releaseID == row.id, v.workspaceID.rawValue == row.workspaceID,
                      try AuthorityCriterionCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.authoritySourceRelease(v), origin: .authorityRow(row, source: snapshot))
            case .requirementBasisBinding:
                let v = try AuthorityCriterionCanonicalCodecV1.decode(RequirementBasisBindingV1.self, from: row.canonicalData)
                guard v.bindingID == row.id, v.workspaceID.rawValue == row.workspaceID,
                      try AuthorityCriterionCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.requirementBasisBinding(v), origin: .authorityRow(row, source: snapshot))
            case .applicabilityContextSnapshot:
                let v = try AuthorityCriterionCanonicalCodecV1.decode(ApplicabilityContextSnapshotV1.self, from: row.canonicalData)
                guard v.snapshotID == row.id, v.workspaceID.rawValue == row.workspaceID,
                      try AuthorityCriterionCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.applicabilityContextSnapshot(v), origin: .authorityRow(row, source: snapshot))
            case .assessmentScopeSnapshot:
                let v = try AuthorityCriterionCanonicalCodecV1.decode(AssessmentScopeSnapshotV1.self, from: row.canonicalData)
                guard v.snapshotID == row.id, v.workspaceID.rawValue == row.workspaceID,
                      try AuthorityCriterionCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.assessmentScopeSnapshot(v), origin: .authorityRow(row, source: snapshot))
            case .severityScaleRelease:
                let v = try AuthorityCriterionCanonicalCodecV1.decode(SeverityScaleReleaseV1.self, from: row.canonicalData)
                guard v.releaseID == row.id, v.workspaceID.rawValue == row.workspaceID,
                      try AuthorityCriterionCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.severityScaleRelease(v), origin: .authorityRow(row, source: snapshot))
            case .findingClassificationBinding:
                let v = try AuthorityCriterionCanonicalCodecV1.decode(FindingClassificationBindingV1.self, from: row.canonicalData)
                guard v.bindingID == row.id, v.workspaceID.rawValue == row.workspaceID,
                      try AuthorityCriterionCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.findingClassificationBinding(v), origin: .authorityRow(row, source: snapshot))
            case .measurementProtocolRelease:
                let v = try AuthorityCriterionCanonicalCodecV1.decode(MeasurementProtocolReleaseV1.self, from: row.canonicalData)
                guard v.releaseID == row.id, v.workspaceID.rawValue == row.workspaceID,
                      try AuthorityCriterionCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.measurementProtocolRelease(v), origin: .authorityRow(row, source: snapshot))
            case .derivedFactEvaluatorDescriptor:
                let v = try AuthorityCriterionCanonicalCodecV1.decode(DerivedFactEvaluatorDescriptorV1.self, from: row.canonicalData)
                guard v.descriptorID == row.id, v.workspaceID.rawValue == row.workspaceID,
                      try AuthorityCriterionCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.derivedFactEvaluatorDescriptor(v), origin: .authorityRow(row, source: snapshot))
            case .derivedFactProvenance:
                let v = try AuthorityCriterionCanonicalCodecV1.decode(DerivedFactProvenanceV1.self, from: row.canonicalData)
                guard v.provenanceID == row.id, v.workspaceID.rawValue == row.workspaceID,
                      try AuthorityCriterionCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.derivedFactProvenance(v), origin: .authorityRow(row, source: snapshot))
            }
        }
        var measurementKeys = Set<String>()
        for row in snapshot.records.measurementIntegrity {
            guard row.workspaceID == snapshot.workspaceIdentity.workspaceID.rawValue,
                  measurementKeys.insert(row.kind.rawValue + "\0" + row.id.uuidString).inserted else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            switch row.kind {
            case .instrumentReference:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(InstrumentReferenceV1.self, from: row.canonicalData)
                guard v.referenceID == row.id, v.workspaceID.rawValue == row.workspaceID, v.revision == row.revision,
                      try MeasurementIntegrityCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.instrumentReference(v), origin: .measurementRow(row, source: snapshot))
            case .calibrationSnapshot:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(CalibrationStatusSnapshotV1.self, from: row.canonicalData)
                guard v.snapshotID == row.id, v.workspaceID.rawValue == row.workspaceID, v.revision == row.revision,
                      try MeasurementIntegrityCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.calibrationSnapshot(v), origin: .measurementRow(row, source: snapshot))
            case .measurementCapture:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementCaptureV1.self, from: row.canonicalData)
                guard v.captureID == row.id, v.workspaceID.rawValue == row.workspaceID, v.revision == row.revision,
                      try MeasurementIntegrityCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.measurementCapture(v), origin: .measurementRow(row, source: snapshot))
            case .measurementSeries:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementSeriesV1.self, from: row.canonicalData)
                guard v.snapshotID == row.id, v.workspaceID.rawValue == row.workspaceID, v.revision == row.revision,
                      try MeasurementIntegrityCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.measurementSeries(v), origin: .measurementRow(row, source: snapshot))
            case .qualityAssessment:
                let v = try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementQualityAssessmentV1.self, from: row.canonicalData)
                guard v.assessmentID == row.id, v.workspaceID.rawValue == row.workspaceID, v.revision == row.revision,
                      try MeasurementIntegrityCanonicalCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retain(.qualityAssessment(v), origin: .measurementRow(row, source: snapshot))
            }
        }
        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .applyAuthorityCriterion(mutation):
                try mutation.validate()
                switch entry.receipt.sourceKind {
                case .localUser:
                    _ = try AuthorityCriterionMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                case .importedHistory, .localRecovery, .semanticReversal:
                    // Nonlocal canonical history is an observation, not a local
                    // writer receipt. The full imported-history predicate and
                    // Entry bind source kind and any reversal sidecars exactly.
                    let concurrency = try mutation.concurrencyIdentity
                    let affected = try mutation.affectedIdentity
                    guard entry.receipt.mutationID == mutation.mutationID,
                          entry.receipt.identity.workspaceID == mutation.workspaceID,
                          entry.receipt.commandBodySHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                            WorkspaceCommandV1.applyAuthorityCriterion(mutation))),
                          entry.receipt.expectedRevision.entityRevisions.first(where: {
                            $0.identity == concurrency
                          })?.revision == mutation.expectedRevision,
                          entry.receipt.resultingRevision.entityRevisions.first(where: {
                            $0.identity == affected
                          })?.revision == mutation.postImage.revision,
                          entry.receipt.postImages == [try mutation.postImage.mutationPostImage] else {
                        throw WorkspaceMutationFailureV1.invalidReceipt
                    }
                }
                switch mutation.postImage {
                case let .appendAuthoritySource(v), let .supersedeAuthoritySource(v):
                    try retain(.authoritySourceRelease(v), origin: origin)
                case let .appendRequirementBasis(v), let .supersedeRequirementBasis(v):
                    try retain(.requirementBasisBinding(v), origin: origin)
                case let .appendApplicabilityContext(v), let .supersedeApplicabilityContext(v):
                    try retain(.applicabilityContextSnapshot(v), origin: origin)
                case let .appendAssessmentScope(v), let .supersedeAssessmentScope(v):
                    try retain(.assessmentScopeSnapshot(v), origin: origin)
                case let .appendSeverityScale(v), let .supersedeSeverityScale(v):
                    try retain(.severityScaleRelease(v), origin: origin)
                case let .appendFindingClassification(v), let .supersedeFindingClassification(v):
                    try retain(.findingClassificationBinding(v), origin: origin)
                case let .appendMeasurementProtocol(v), let .supersedeMeasurementProtocol(v):
                    try retain(.measurementProtocolRelease(v), origin: origin)
                case let .appendEvaluatorDescriptor(v), let .supersedeEvaluatorDescriptor(v):
                    try retain(.derivedFactEvaluatorDescriptor(v), origin: origin)
                case let .appendDerivedFact(v), let .supersedeDerivedFact(v):
                    try retain(.derivedFactProvenance(v), origin: origin)
                }
            case let .applyMeasurementIntegrity(mutation):
                try mutation.validate()
                _ = try MeasurementIntegrityMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                // mutationPayloads exhausts all five collections in the bound
                // atomic bundle; the full bundle remains in the history origin.
                for payload in mutation.bundle.mutationPayloads {
                    switch payload {
                    case let .instrument(v): try retain(.instrumentReference(v), origin: origin)
                    case let .calibration(v): try retain(.calibrationSnapshot(v), origin: origin)
                    case let .capture(v): try retain(.measurementCapture(v), origin: origin)
                    case let .series(v): try retain(.measurementSeries(v), origin: origin)
                    case let .quality(v): try retain(.qualityAssessment(v), origin: origin)
                    }
                }
            default:
                // Other commands remain in the complete history and explicitly
                // unhandled by this family-specific contribution.
                break
            }
        }
        struct Key: Hashable { let namespace: Namespace; let identity: Identity }
        func namespace(_ observation: Observation) -> Namespace {
            switch observation.origin {
            case let .authorityRow(_, source), let .measurementRow(_, source):
                return .init(workspaceID: source.workspaceIdentity.workspaceID)
            case let .immutableHistory(entry):
                return .init(workspaceID: entry.envelope.workspaceID)
            }
        }
        func linkage(_ value: Value) -> (WorkspaceID, Identity, Identity?, UInt64, Bool) {
            switch value {
            case let .authoritySourceRelease(v):
                return (v.workspaceID, .authoritySourceRelease(v.releaseID),
                        v.supersedesReleaseID.map { .authoritySourceRelease($0) }, v.revision, true)
            case let .requirementBasisBinding(v):
                return (v.workspaceID, .requirementBasisBinding(v.bindingID),
                        v.supersedesBindingID.map { .requirementBasisBinding($0) }, v.revision, true)
            case let .applicabilityContextSnapshot(v):
                return (v.workspaceID, .applicabilityContextSnapshot(v.snapshotID),
                        v.supersedesSnapshotID.map { .applicabilityContextSnapshot($0) }, v.revision, true)
            case let .assessmentScopeSnapshot(v):
                return (v.workspaceID, .assessmentScopeSnapshot(v.snapshotID),
                        v.supersedesSnapshotID.map { .assessmentScopeSnapshot($0) }, v.revision, true)
            case let .severityScaleRelease(v):
                return (v.workspaceID, .severityScaleRelease(v.releaseID),
                        v.supersedesReleaseID.map { .severityScaleRelease($0) }, v.revision, true)
            case let .findingClassificationBinding(v):
                return (v.workspaceID, .findingClassificationBinding(v.bindingID),
                        v.supersedesBindingID.map { .findingClassificationBinding($0) }, v.revision, true)
            case let .measurementProtocolRelease(v):
                return (v.workspaceID, .measurementProtocolRelease(v.releaseID),
                        v.supersedesReleaseID.map { .measurementProtocolRelease($0) }, v.revision, true)
            case let .derivedFactEvaluatorDescriptor(v):
                return (v.workspaceID, .derivedFactEvaluatorDescriptor(v.descriptorID),
                        v.supersedesDescriptorID.map { .derivedFactEvaluatorDescriptor($0) }, v.revision, true)
            case let .derivedFactProvenance(v):
                return (v.workspaceID, .derivedFactProvenance(v.provenanceID),
                        v.predecessorProvenanceID.map { .derivedFactProvenance($0) }, v.revision, true)
            case let .instrumentReference(v):
                return (v.workspaceID, .instrumentReference(v.referenceID),
                        v.supersedesReferenceID.map { .instrumentReference($0) }, v.revision, false)
            case let .calibrationSnapshot(v):
                return (v.workspaceID, .calibrationSnapshot(v.snapshotID),
                        v.supersedesSnapshotID.map { .calibrationSnapshot($0) }, v.revision, false)
            case let .measurementCapture(v):
                return (v.workspaceID, .measurementCapture(v.captureID),
                        v.supersedesCaptureID.map { .measurementCapture($0) }, v.revision, false)
            case let .measurementSeries(v):
                return (v.workspaceID, .measurementSeries(v.snapshotID),
                        v.supersedesSnapshotID.map { .measurementSeries($0) }, v.revision, false)
            case let .qualityAssessment(v):
                return (v.workspaceID, .qualityAssessment(v.assessmentID),
                        v.supersedesAssessmentID.map { .qualityAssessment($0) }, v.revision, false)
            }
        }
        var values: [Key: Value] = [:]
        var originsByKey: [Key: [Observation]] = [:]
        var inputsByNamespace: [Namespace: [Observation]] = [:]
        for observation in result {
            let ns = namespace(observation), link = linkage(observation.value)
            guard ns.workspaceID == link.0 else { throw TemporalEvidenceContractFailureV1.staleSource }
            let key = Key(namespace: ns, identity: link.1)
            if let prior = values[key], prior != observation.value {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            values[key] = observation.value
            originsByKey[key, default: []].append(observation)
            inputsByNamespace[ns, default: []].append(observation)
        }
        var claimedAuthorityPredecessors: [Key: Identity] = [:]
        var links: [PredecessorObservation] = []
        for observation in result {
            let ns = namespace(observation), link = linkage(observation.value)
            guard let predecessorID = link.2 else {
                guard link.3 == 1 else { throw TemporalEvidenceContractFailureV1.staleSource }
                links.append(.init(owner: observation, namespace: ns, resolution: .root))
                continue
            }
            let key = Key(namespace: ns, identity: predecessorID)
            if link.4 {
                // Duplicate observations of the same immutable successor are
                // lawful; two distinct successor identities are not.
                if let claimed = claimedAuthorityPredecessors[key], claimed != link.1 {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                claimedAuthorityPredecessors[key] = link.1
            }
            guard let predecessor = values[key] else {
                links.append(.init(owner: observation, namespace: ns,
                                   resolution: .unresolved(predecessorID)))
                continue
            }
            let priorLink = linkage(predecessor)
            guard priorLink.3 < UInt64.max, priorLink.3 + 1 == link.3 else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            // Exact increasing revisions exclude predecessor cycles. Measurement
            // adds all incumbent stable identity/immutable successor predicates.
            switch (observation.value, predecessor) {
            case let (.instrumentReference(value), .instrumentReference(prior)): try value.validateSuccessor(of: prior)
            case let (.calibrationSnapshot(value), .calibrationSnapshot(prior)): try value.validateSuccessor(of: prior)
            case let (.measurementCapture(value), .measurementCapture(prior)): try value.validateSuccessor(of: prior)
            case let (.measurementSeries(value), .measurementSeries(prior)): try value.validateSuccessor(of: prior)
            case let (.qualityAssessment(value), .qualityAssessment(prior)): try value.validateSuccessor(of: prior)
            default:
                guard link.4 else { throw TemporalEvidenceContractFailureV1.staleSource }
            }
            guard let predecessorOrigins = originsByKey[key], !predecessorOrigins.isEmpty else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            links.append(.init(owner: observation, namespace: ns,
                               resolution: .resolved(predecessor, origins: predecessorOrigins)))
        }
        struct Graphs {
            var authority = AuthorityCriterionGraphValuesV1()
            var measurement = MeasurementIntegrityGraphValuesV1()
        }
        var graphs: [Namespace: Graphs] = [:]
        for (key, value) in values {
            var graph = graphs[key.namespace] ?? Graphs()
            switch value {
            case let .authoritySourceRelease(v): graph.authority.sources[v.releaseID] = v
            case let .requirementBasisBinding(v): graph.authority.bases[v.bindingID] = v
            case let .applicabilityContextSnapshot(v): graph.authority.contexts[v.snapshotID] = v
            case let .assessmentScopeSnapshot(v): graph.authority.scopes[v.snapshotID] = v
            case let .severityScaleRelease(v): graph.authority.scales[v.releaseID] = v
            case let .findingClassificationBinding(v): graph.authority.classifications[v.bindingID] = v
            case let .measurementProtocolRelease(v): graph.authority.protocols[v.releaseID] = v
            case let .derivedFactEvaluatorDescriptor(v): graph.authority.evaluators[v.descriptorID] = v
            case let .derivedFactProvenance(v): graph.authority.facts[v.provenanceID] = v
            case let .instrumentReference(v): graph.measurement.instruments[v.referenceID] = v
            case let .calibrationSnapshot(v): graph.measurement.calibrations[v.snapshotID] = v
            case let .measurementCapture(v): graph.measurement.captures[v.captureID] = v
            case let .measurementSeries(v): graph.measurement.series[v.snapshotID] = v
            case let .qualityAssessment(v): graph.measurement.assessments[v.assessmentID] = v
            }
            graphs[key.namespace] = graph
        }
        var external: [ExternalObservation] = []
        func retainExternal(_ value: ExternalValue, namespace: Namespace, origin: ExternalOrigin) throws {
            var graph = graphs[namespace] ?? Graphs()
            switch value {
            case let .actor(v):
                try v.validate()
                guard v.workspaceID == namespace.workspaceID,
                      graph.authority.actors[v.snapshotID].map({ $0 == v }) ?? true else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                graph.authority.actors[v.snapshotID] = v
            case let .qualification(v):
                try v.validate()
                guard v.workspaceID == namespace.workspaceID,
                      graph.authority.qualifications[v.snapshotID].map({ $0 == v }) ?? true else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                graph.authority.qualifications[v.snapshotID] = v
            case let .workScope(v):
                try v.validate()
                guard v.workspaceID == namespace.workspaceID,
                      graph.authority.workScopes[v.snapshotID].map({ $0 == v }) ?? true else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                graph.authority.workScopes[v.snapshotID] = v
            }
            graphs[namespace] = graph
            external.append(.init(namespace: namespace, origin: origin, value: value))
        }
        let currentNamespace = Namespace(workspaceID: snapshot.workspaceIdentity.workspaceID)
        for row in snapshot.records.partyAccountability {
            switch row.kind {
            case .actorSnapshot:
                let v = try PartyAccountabilitySnapshotCodecV1.decode(ActorSnapshotV1.self, from: row.canonicalData)
                guard v.snapshotID == row.id, v.workspaceID.rawValue == row.workspaceID, row.revision == nil,
                      try PartyAccountabilitySnapshotCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retainExternal(.actor(v), namespace: currentNamespace, origin: .canonicalParty(row, source: snapshot))
            case .qualificationSnapshot:
                let v = try PartyAccountabilitySnapshotCodecV1.decode(QualificationSnapshotV1.self, from: row.canonicalData)
                guard v.snapshotID == row.id, v.workspaceID.rawValue == row.workspaceID, row.revision == nil,
                      try PartyAccountabilitySnapshotCodecV1.encode(v) == row.canonicalData else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
                try retainExternal(.qualification(v), namespace: currentNamespace, origin: .canonicalParty(row, source: snapshot))
            case .serviceParty, .sitePartyRoleEvent, .signoffSnapshot: break
            }
        }
        for row in snapshot.records.assetSemantics where row.kind == .workSubjectScopeSnapshot {
            let v = try AssetSemanticCanonicalCodecV1.decode(WorkSubjectScopeSnapshotV1.self, from: row.canonicalData)
            guard v.snapshotID == row.id, v.workspaceID.rawValue == row.workspaceID,
                  v.workspaceRevision == row.revision,
                  try AssetSemanticCanonicalCodecV1.encode(v) == row.canonicalData else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            try retainExternal(.workScope(v), namespace: currentNamespace, origin: .canonicalAsset(row, source: snapshot))
        }
        for entry in history.entries {
            let ns = Namespace(workspaceID: entry.envelope.workspaceID)
            switch entry.envelope.command {
            case let .applyPartyAccountability(mutation):
                try mutation.validate()
                guard mutation.workspaceID == ns.workspaceID else { throw TemporalEvidenceContractFailureV1.staleSource }
                switch mutation {
                case let .appendActorSnapshot(v):
                    let identity = try mutation.affectedIdentity
                    guard entry.receipt.postImages == [try MutationJournalStoreV1.observationPostImage(v, revision: 1)],
                          entry.receipt.expectedRevision.entityRevisions.first(where: { $0.identity == identity })?.revision == 0,
                          entry.receipt.resultingRevision.entityRevisions.first(where: { $0.identity == identity })?.revision == 1 else {
                        throw WorkspaceMutationFailureV1.invalidReceipt
                    }
                    try retainExternal(.actor(v), namespace: ns, origin: .immutableHistory(entry))
                case let .appendQualificationSnapshot(v):
                    let identity = try mutation.affectedIdentity
                    guard entry.receipt.postImages == [try MutationJournalStoreV1.observationPostImage(v, revision: 1)],
                          entry.receipt.expectedRevision.entityRevisions.first(where: { $0.identity == identity })?.revision == 0,
                          entry.receipt.resultingRevision.entityRevisions.first(where: { $0.identity == identity })?.revision == 1 else {
                        throw WorkspaceMutationFailureV1.invalidReceipt
                    }
                    try retainExternal(.qualification(v), namespace: ns, origin: .immutableHistory(entry))
                case .recordParty, .appendSiteRole, .appendSignoff: break
                }
            case let .applyAssetSemantics(mutation):
                try mutation.validate()
                guard mutation.workspaceID == ns.workspaceID else { throw TemporalEvidenceContractFailureV1.staleSource }
                if let scope = mutation.workSubjectScope {
                    let identity = try mutation.affectedIdentity
                    guard entry.receipt.mutationID == mutation.mutationID,
                          mutation.expectedAssetRevision < UInt64.max,
                          entry.receipt.expectedRevision.entityRevisions.first(where: { $0.identity == identity })?.revision == mutation.expectedAssetRevision,
                          entry.receipt.resultingRevision.entityRevisions.first(where: { $0.identity == identity })?.revision == mutation.expectedAssetRevision + 1,
                          entry.receipt.postImages.count == 1,
                          let image = entry.receipt.postImages.first,
                          try image.identity == identity,
                          image.revision == mutation.expectedAssetRevision + 1 else {
                        throw WorkspaceMutationFailureV1.invalidReceipt
                    }
                    try retainExternal(.workScope(scope), namespace: ns, origin: .immutableHistory(entry))
                }
            default: break
            }
        }
        let externalByNamespace = Dictionary(grouping: external, by: \.namespace)
        var graphObservations: [NamespaceGraphObservation] = []
        for ns in graphs.keys.sorted(by: {
            $0.workspaceID.rawValue.uuidString < $1.workspaceID.rawValue.uuidString
        }) {
            guard var graph = graphs[ns] else { throw TemporalEvidenceContractFailureV1.staleSource }
            graph.measurement.protocolsByID = graph.authority.protocols
            let a = graph.authority, m = graph.measurement
            var authorityMissing: [Requirement] = [], measurementMissing: [Requirement] = []
            for link in links where link.namespace == ns {
                if case let .unresolved(identity) = link.resolution {
                    if linkage(link.owner.value).4 { authorityMissing.append(.family(identity)) }
                    else { measurementMissing.append(.family(identity)) }
                }
            }
            for v in a.bases.values {
                if a.sources[v.authorityReleaseID] == nil { authorityMissing.append(.family(.authoritySourceRelease(v.authorityReleaseID))) }
                if a.actors[v.selectedBy.snapshotID] == nil { authorityMissing.append(.actor(v.selectedBy.snapshotID)) }
            }
            for v in a.contexts.values {
                if a.workScopes[v.workSubjectScope.snapshotID] == nil { authorityMissing.append(.workScope(v.workSubjectScope.snapshotID)) }
                if a.actors[v.actor.snapshotID] == nil { authorityMissing.append(.actor(v.actor.snapshotID)) }
                if let q = v.qualification, a.qualifications[q.snapshotID] == nil { authorityMissing.append(.qualification(q.snapshotID)) }
                for basis in v.basisBindings where a.bases[basis.bindingID] == nil { authorityMissing.append(.family(.requirementBasisBinding(basis.bindingID))) }
            }
            for v in a.scopes.values {
                if a.contexts[v.applicabilityContextID] == nil { authorityMissing.append(.family(.applicabilityContextSnapshot(v.applicabilityContextID))) }
                if a.workScopes[v.workSubjectScope.snapshotID] == nil { authorityMissing.append(.workScope(v.workSubjectScope.snapshotID)) }
            }
            for v in a.classifications.values {
                if a.contexts[v.applicabilityContextID] == nil { authorityMissing.append(.family(.applicabilityContextSnapshot(v.applicabilityContextID))) }
                if a.scopes[v.assessmentScopeID] == nil { authorityMissing.append(.family(.assessmentScopeSnapshot(v.assessmentScopeID))) }
                if let id = v.severityScaleReleaseID, a.scales[id] == nil { authorityMissing.append(.family(.severityScaleRelease(id))) }
            }
            for v in a.protocols.values where a.evaluators[v.evaluatorDescriptorID] == nil {
                authorityMissing.append(.family(.derivedFactEvaluatorDescriptor(v.evaluatorDescriptorID)))
            }
            for v in a.facts.values {
                if a.protocols[v.protocolReleaseID] == nil { authorityMissing.append(.family(.measurementProtocolRelease(v.protocolReleaseID))) }
                if a.evaluators[v.evaluatorDescriptorID] == nil { authorityMissing.append(.family(.derivedFactEvaluatorDescriptor(v.evaluatorDescriptorID))) }
            }
            for v in m.calibrations.values where m.instruments[v.instrument.referenceID] == nil {
                measurementMissing.append(.family(.instrumentReference(v.instrument.referenceID)))
            }
            for v in m.captures.values {
                if let ref = v.instrument, m.instruments[ref.referenceID] == nil { measurementMissing.append(.family(.instrumentReference(ref.referenceID))) }
                if let ref = v.calibration, m.calibrations[ref.snapshotID] == nil { measurementMissing.append(.family(.calibrationSnapshot(ref.snapshotID))) }
            }
            for v in m.series.values {
                if m.protocolsByID[v.protocolReference.releaseID] == nil { measurementMissing.append(.family(.measurementProtocolRelease(v.protocolReference.releaseID))) }
                for ref in v.samples where m.captures[ref.captureID] == nil { measurementMissing.append(.family(.measurementCapture(ref.captureID))) }
            }
            for v in m.assessments.values {
                switch v.subjectKind {
                case .capture:
                    if m.captures[v.subjectID] == nil { measurementMissing.append(.family(.measurementCapture(v.subjectID))) }
                case .series:
                    if !m.series.values.contains(where: { $0.snapshotID == v.subjectID || $0.seriesID == v.subjectID }) {
                        measurementMissing.append(.qualitySeries(v))
                    }
                }
            }
            // Missing dependencies are observations, never substituted facts.
            // With every dependency present, run the incumbent laws themselves,
            // including exact embedded equality/digests and quality finalization.
            if authorityMissing.isEmpty { try graphValidator.validateAuthorityCriterionValues(a) }
            if measurementMissing.isEmpty { try graphValidator.validateMeasurementIntegrityValues(m) }
            graphObservations.append(.init(namespace: ns,
                inputs: inputsByNamespace[ns] ?? [],
                externalInputs: externalByNamespace[ns] ?? [],
                authority: authorityMissing.isEmpty ? .validatedTypedGraph : .unresolved(authorityMissing),
                measurement: measurementMissing.isEmpty ? .validatedTypedGraph : .unresolved(measurementMissing)))
        }
        externalObservations = external
        namespaceGraphs = graphObservations
        predecessors = links
        observations = result; byteObservations = bytes
    }
}


/// Pure, incomplete preflight observation. No success case, removal decision or
/// completion seal exists. Genuine retained-reader admission is outside this type.
struct TemporalNormalizationReferencePreflightV1: Sendable {
    enum UnresolvedRequirement: String, Sendable, CaseIterable {
        case crossFamilyGraphResolution
        case sourceProvenanceAndTerminalAdmission
        case purposePayloadSourceAndContinuationClosure
        case physicalContentAndLocatorOwnership
        case retainedReaderGenerationAndLifetime
        case liveAndPortableOwnerInventoryAndDrain
        case publicationAndRevalidationAuthority
    }
    let snapshot: TemporalNormalizationCanonicalSnapshotV1
    let history: TemporalNormalizationHistoryObservationV1
    let unresolvedRequirements: [UnresolvedRequirement]
    let temporal: TemporalNormalizationTemporalReferencesV1
    let document: TemporalNormalizationDocumentReferencesV1
    let privacy: TemporalNormalizationPrivacyReferencesV1
    let evidenceMetadata: TemporalNormalizationEvidenceMetadataReferencesV1
    let authorityMeasurement: TemporalNormalizationAuthorityMeasurementReferencesV1
    let surveyLightingInbox: TemporalNormalizationSurveyLightingInboxReferencesV1
    let activityLabelReliability: TemporalNormalizationActivityLabelReliabilityReferencesV1
    let draftHistory: TemporalNormalizationDraftHistoryReferencesV1
    let shopProfile: TemporalNormalizationShopProfileReferencesV1
    let workflowFile: TemporalNormalizationWorkflowFileReferencesV1
    let evidenceSemantic: TemporalNormalizationEvidenceSemanticReferencesV1
    let reversal: TemporalNormalizationReversalReferencesV1
    let reviewWork: TemporalNormalizationReviewWorkReferencesV1
    let definitionAccessibility: TemporalNormalizationDefinitionAccessibilityReferencesV1
    let serviceRequest: TemporalNormalizationServiceRequestReferencesV1
    let contactReinspection: TemporalNormalizationContactReinspectionReferencesV1
    let spatialSchedule: TemporalNormalizationSpatialScheduleReferencesV1
    let assetPartyRequirement: TemporalNormalizationAssetPartyRequirementReferencesV1
    let operationalGraph: TemporalNormalizationOperationalGraphReferencesV1
    let packageClient: TemporalNormalizationPackageClientReferencesV1
    let structural: TemporalNormalizationStructuralReferencesV1
    let dualReceipts: TemporalNormalizationDualReceiptObservationsV1
    let commandPostImages: TemporalNormalizationCommandPostImageObservationsV1
    let requirementAssuranceHistory: TemporalNormalizationRequirementAssuranceHistoryV1
    let requirementGraph: TemporalNormalizationRequirementReferenceGraphV1
    let reportContent: TemporalNormalizationReportContentReferencesV1?
    let reportRequirements: TemporalNormalizationReportRequirementObservationsV1
    let myDayGraph: TemporalNormalizationMyDayReferenceGraphV1
    let photoHistory: CheckRunnerPhotoBackupHistoryV1
    let workPacketGraph: TemporalNormalizationWorkPacketReferenceGraphV1
    let reviewWorkActors: TemporalNormalizationReviewWorkActorGraphV1
    let reviewSubjects: TemporalNormalizationReviewSubjectGraphV1
    let reviewGraph: TemporalNormalizationReviewReferenceGraphV1
    let qualityGraph: TemporalNormalizationQualityReferenceGraphV1
    let assuranceGraph: TemporalNormalizationAssuranceGraphV1
    let knownDraftPayloads: TemporalNormalizationKnownDraftPayloadReferencesV1
    static func observe(snapshot: TemporalNormalizationCanonicalSnapshotV1,
                        history: TemporalNormalizationHistoryObservationV1) throws -> Self {
        try Self(snapshot: snapshot, history: history, reports: [])
    }
    static func observe(snapshot: TemporalNormalizationCanonicalSnapshotV1,
                        history: TemporalNormalizationHistoryObservationV1,
                        reports: [TemporalNormalizationReportSnapshotObservationV1]) throws -> Self {
        try Self(snapshot: snapshot, history: history, reports: reports)
    }
    static func observe(snapshot: TemporalNormalizationCanonicalSnapshotV1,
                        history: TemporalNormalizationHistoryObservationV1,
                        reports: [TemporalNormalizationReportSnapshotObservationV1],
                        profileRegistry: WorkspacePackageLifecycleProfileRegistryV1) throws -> Self {
        try Self(snapshot: snapshot, history: history, reports: reports, profileRegistry: profileRegistry)
    }
    private init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
                 history: TemporalNormalizationHistoryObservationV1,
                 reports: [TemporalNormalizationReportSnapshotObservationV1],
                 profileRegistry: WorkspacePackageLifecycleProfileRegistryV1? = nil) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        self.snapshot = snapshot; self.history = history
        // Reuse the real incumbent photo/C36 graph with genuine source metadata.
        // This remains a value proof, not retained-reader or physical-byte authority.
        photoHistory = try CheckRunnerPhotoBackupHistoryV1.project(source: snapshot.source,
            records: snapshot.records)
        unresolvedRequirements = UnresolvedRequirement.allCases
        temporal = try TemporalNormalizationTemporalReferencesV1(snapshot: snapshot, history: history)
        document = try TemporalNormalizationDocumentReferencesV1(snapshot: snapshot, history: history)
        privacy = try TemporalNormalizationPrivacyReferencesV1(snapshot: snapshot, history: history)
        evidenceMetadata = try TemporalNormalizationEvidenceMetadataReferencesV1(snapshot: snapshot, history: history)
        authorityMeasurement = try TemporalNormalizationAuthorityMeasurementReferencesV1(snapshot: snapshot, history: history)
        surveyLightingInbox = try TemporalNormalizationSurveyLightingInboxReferencesV1(snapshot: snapshot, history: history)
        activityLabelReliability = try TemporalNormalizationActivityLabelReliabilityReferencesV1(snapshot: snapshot, history: history)
        draftHistory = try TemporalNormalizationDraftHistoryReferencesV1(snapshot: snapshot, history: history)
        shopProfile = try TemporalNormalizationShopProfileReferencesV1(snapshot: snapshot, history: history)
        workflowFile = try TemporalNormalizationWorkflowFileReferencesV1(snapshot: snapshot, history: history)
        evidenceSemantic = try TemporalNormalizationEvidenceSemanticReferencesV1(snapshot: snapshot, history: history)
        reversal = try TemporalNormalizationReversalReferencesV1(history: history)
        reviewWork = try TemporalNormalizationReviewWorkReferencesV1(snapshot: snapshot, history: history)
        definitionAccessibility = try TemporalNormalizationDefinitionAccessibilityReferencesV1(snapshot: snapshot, history: history)
        serviceRequest = try TemporalNormalizationServiceRequestReferencesV1(snapshot: snapshot, history: history)
        contactReinspection = try TemporalNormalizationContactReinspectionReferencesV1(snapshot: snapshot, history: history)
        spatialSchedule = try TemporalNormalizationSpatialScheduleReferencesV1(snapshot: snapshot, history: history)
        assetPartyRequirement = try TemporalNormalizationAssetPartyRequirementReferencesV1(snapshot: snapshot, history: history)
        operationalGraph = try TemporalNormalizationOperationalGraphReferencesV1(snapshot: snapshot, history: history)
        packageClient = try TemporalNormalizationPackageClientReferencesV1(snapshot: snapshot, history: history)
        structural = try TemporalNormalizationStructuralReferencesV1(snapshot: snapshot, history: history)
        dualReceipts = try TemporalNormalizationDualReceiptObservationsV1(snapshot: snapshot, history: history)
        commandPostImages = try TemporalNormalizationCommandPostImageObservationsV1(history: history)
        requirementAssuranceHistory = try TemporalNormalizationRequirementAssuranceHistoryV1(
            snapshot: snapshot, history: history)
        reportRequirements = try TemporalNormalizationReportRequirementObservationsV1(snapshot: snapshot, members: reports)
        if let profileRegistry, reportRequirements.missingReports.isEmpty {
            reportContent = try TemporalNormalizationReportContentReferencesV1(snapshot: snapshot,
                members: reportRequirements, photoHistory: photoHistory, profileRegistry: profileRegistry)
        } else { reportContent = nil }
        requirementGraph = try TemporalNormalizationRequirementReferenceGraphV1(requirements: assetPartyRequirement, reports: reportRequirements)
        myDayGraph = try TemporalNormalizationMyDayReferenceGraphV1(snapshot: snapshot, operational: operationalGraph)
        qualityGraph = try TemporalNormalizationQualityReferenceGraphV1(semantics: evidenceSemantic)
        assuranceGraph = try TemporalNormalizationAssuranceGraphV1(semantics: evidenceSemantic)
        workPacketGraph = try TemporalNormalizationWorkPacketReferenceGraphV1(review: reviewWork)
        reviewWorkActors = try TemporalNormalizationReviewWorkActorGraphV1(review: reviewWork, parties: assetPartyRequirement)
        reviewGraph = try TemporalNormalizationReviewReferenceGraphV1(review: reviewWork, assurance: assuranceGraph, workflowFiles: workflowFile, requirements: requirementGraph)
        reviewSubjects = try TemporalNormalizationReviewSubjectGraphV1(review: reviewWork,
            authority: authorityMeasurement, functional: assetPartyRequirement, assurance: assuranceGraph)
        knownDraftPayloads = try TemporalNormalizationKnownDraftPayloadReferencesV1(drafts: draftHistory)
    }
}


/// Candidate-specific, conservative pure classification. This result neither
/// asserts that the supplied sources are the owner's entire inventory nor
/// authorizes publication. The owner must retain/revalidate the exact sources,
/// M1 observation, original access, EX/G and physical identity independently.
struct TemporalNormalizationUncommittedOriginalClassificationV1: Sendable {
    enum CanonicalField: String, CaseIterable, Sendable {
        case guidedSurveys
        case assetLocators
        case schedules
        case plans
        case placementPoses
        case evidenceContexts
        case pairedObservationLinks
        case lighting
        case lightingDayInventoryWorkflows
        case lightingNightWorkflows
        case assistanceAcceptanceReceipts
        case temporalEvidence
        case acceptedLabelGenerationSnapshots
        case operationalContacts
        case activityContracts
        case workResources
        case serviceRequests
        case serviceRequestDispositionEvents
        case serviceRequestWorkLinkEvents
        case serviceReliabilityIncidents
        case serviceImpactSegments
        case serviceCauseAssertions
        case serviceRemedyAssertions
        case serviceRepairIntervals
        case serviceRestorationAssertions
        case qualifiedServiceExposures
        case serviceReliabilityReceipts
        case myDayPlans
        case myDayCarryoverReceipts
        case nonactivePlanReferences
        case evidenceAssociationEvents
        case evidenceSequenceRevisions
        case shopReportProfiles
        case roundSessions
        case importMappingProfiles
        case bulkSessions
        case bulkCommitReceipts
        case evidenceQuality
        case fastSurveyInbox
        case reinspectionExceptionQueue
        case entityIdentityResolution
        case practiceWorkspaceProvenance
        case partsStockSnapshot
        case surveyDefinitions
        case accessibleDocumentAssessments
        case fieldReferences
        case recoverabilityReceipts
        case clientCapabilities
        case privacyTransforms
        case measurementIntegrity
        case packageEvolution
        case fieldDrafts
        case workPackets
        case inspectionReview
        case evidenceAssurance
        case functionalRelationships
        case authorityCriterion
        case assetSemantics
        case assetCompositionEdges
        case assetCompositionEvents
        case assetPlacementEvents
        case assets
        case deletionLedger
        case evidenceFiles
        case issues
        case locationHierarchyEvents
        case locationMigrationReceipts
        case locationNodes
        case mutationHistory
        case packets
        case partyAccountability
        case recordsSchemaVersion
        case reports
        case requirementAssurance
        case savedSmartViews
        case sites
        case workflowRecords
    }
    enum Disposition: Sendable {
        case concreteDescriptors, typedOwnerEdges, closedLogicalMetadata, unsupportedAffectedOwner
    }
    struct CanonicalBranch: Sendable {
        let field: CanonicalField
        let count: Int
        let disposition: Disposition
    }
    struct CommandBranch: Sendable {
        let entry: TemporalNormalizationHistoryObservationV1.Entry
        let disposition: Disposition
    }
    struct SourceBranches: Sendable {
        let source: TemporalNormalizationReferencePreflightV1
        let canonical: [CanonicalBranch]
        let commands: [CommandBranch]
    }
    enum Owner: Sendable {
        case temporal(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationTemporalReferencesV1.Observation)
        case document(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationDocumentReferencesV1.ByteObservation)
        case privacy(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationPrivacyReferencesV1.ByteObservation)
        case evidenceMetadata(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationEvidenceMetadataReferencesV1.ByteObservation)
        case captureQuality(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationEvidenceSemanticReferencesV1.Reference)
        case workflowFile(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationWorkflowFileReferencesV1.Reference)
        case draft(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationDraftHistoryReferencesV1.Reference)
        case purpose(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationKnownDraftPayloadReferencesV1.Reference)
        case roundEndpoint(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationKnownDraftPayloadReferencesV1.Reference,
                           TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationSurveyLightingInboxReferencesV1.Observation)
        case report(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationReportContentReferencesV1.Reference)
        case authorityMeasurement(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationAuthorityMeasurementReferencesV1.ByteObservation)
        case round(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationSurveyLightingInboxReferencesV1.Reference)
        case survey(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationSurveyLightingInboxReferencesV1.Reference)
        case activity(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationActivityLabelReliabilityReferencesV1.Reference)
        case historyDependency(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Blocker: Sendable {
        case noSourceObservation
        case noMatchingWorkspace
        case mutationIdentityOccupied(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationHistoryObservationV1.Entry)
        case quarantinedMutation(TemporalNormalizationCanonicalSnapshotV1, MutationHistoryQuarantineRecordV1)
        case unsupportedCanonical(TemporalNormalizationCanonicalSnapshotV1, CanonicalField)
        case unsupportedCommand(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationHistoryObservationV1.Entry)
        case terminalReservation(TemporalEvidencePromotionReservationV1)
        case reservationNotPublished
        case divergentReservation(TemporalEvidencePromotionReservationV1)
        case sharedPromotion(TemporalEvidencePromotionReservationV1)
        case retentionReservation(TemporalEvidenceRetentionCleanupReservationV1)
        case pendingPublication(TemporalOperationalJournalObservationV1.PendingPublication)
        case retainedOwner(Owner)
        case unresolvedDefinition(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationDefinitionAccessibilityReferencesV1.Reference)
        case unresolvedAccountability(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationAssetPartyRequirementReferencesV1.Observation)
        case unresolvedResponse(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationSurveyLightingInboxReferencesV1.Reference)
        case unresolvedActivityFile(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationActivityLabelReliabilityReferencesV1.Reference)
        case unresolvedPurpose(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationKnownDraftPayloadReferencesV1.Reference)
        case unknownPurpose(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationKnownDraftPayloadReferencesV1.Observation)
        case unresolvedDraftPlan(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationDraftHistoryReferencesV1.Reference)
        case reportMemberOrSemanticAdmission(TemporalNormalizationCanonicalSnapshotV1)
        case unresolvedReportReference(TemporalNormalizationCanonicalSnapshotV1, TemporalNormalizationReportContentReferencesV1.Reference)
    }
    let reservation: TemporalEvidencePromotionReservationV1
    let operational: TemporalOperationalJournalObservationV1
    let sources: [SourceBranches]
    let blockers: [Blocker]

    /// An exhaustive answer about these exact values only, never a permission.
    /// No source-set-completeness bit or publication proof is accepted here.
    enum Decision: Sendable { case preserve, noReferencedContentInSuppliedObservations }
    var decision: Decision { blockers.isEmpty ? .noReferencedContentInSuppliedObservations : .preserve }

    init(reservation: TemporalEvidencePromotionReservationV1,
         operational: TemporalOperationalJournalObservationV1,
         sources: [TemporalNormalizationReferencePreflightV1]) throws {
        // Re-run the actual reservation constructor; no caller-generated ID key
        // substitutes for its complete scratch request/lease/digest binding.
        guard reservation == (try TemporalEvidencePromotionReservationV1(
            workspaceID: reservation.workspaceID, mutationID: reservation.mutationID,
            contentID: reservation.contentID, contentSHA256: reservation.contentSHA256,
            binding: reservation.binding, state: reservation.state)) else {
            throw TemporalEvidenceContractFailureV1.staleSource
        }
        self.reservation = reservation; self.operational = operational
        var failures: [Blocker] = [], branches: [SourceBranches] = []
        if sources.isEmpty { failures.append(.noSourceObservation) }
        if !sources.contains(where: { $0.snapshot.workspaceIdentity.workspaceID == reservation.workspaceID }) {
            failures.append(.noMatchingWorkspace)
        }
        switch reservation.state {
        case .prepared, .originalPromoted: break
        case .canonicalCommitted, .finished, .quarantined:
            failures.append(.terminalReservation(reservation))
        }
        // M1 must be reconciled under its own law before this fixed operation.
        // Keep the full displaced/successor payload, even if it seems unrelated.
        if let pending = operational.pending { failures.append(.pendingPublication(pending)) }
        var matching = 0
        for manifest in operational.published {
            for other in manifest.promotions {
                if other.workspaceID == reservation.workspaceID && other.mutationID == reservation.mutationID {
                    if other == reservation { matching += 1 }
                    else { failures.append(.divergentReservation(other)) }
                } else if other.workspaceID == reservation.workspaceID && other.contentID == reservation.contentID {
                    failures.append(.sharedPromotion(other))
                }
            }
            for retention in manifest.retentions {
                if retention.mutation.workspaceID == reservation.workspaceID {
                    // The complete typed remove payload must remain available;
                    // its original set cannot be inferred from a receipt ID.
                    if case let .removeClip(_, clips, _, derivatives, _) = retention.mutation.payload,
                       clips.contains(where: { $0.original.contentID == reservation.contentID }) ||
                       derivatives.contains(where: { $0.content.contentID == reservation.contentID || $0.source.contentID == reservation.contentID }) {
                        failures.append(.retentionReservation(retention))
                    }
                }
            }
        }
        if matching != 1 { failures.append(.reservationNotPublished) }
        func matches(_ workspace: String, _ content: String) -> Bool {
            UUID(uuidString: workspace) == reservation.workspaceID.rawValue && content == reservation.contentID
        }
        func matches(_ content: ContentReferenceV1) -> Bool { matches(content.workspaceID, content.contentID) }
        func matches(_ locator: ContentLocatorV1) -> Bool { matches(locator.workspaceID, locator.contentID) }
        // Index once, retaining every genuine endpoint observation. Namespace
        // and exact revision/digest must resolve; a missing endpoint is refusal.
        var roundEndpoints: [(snapshot: TemporalNormalizationCanonicalSnapshotV1,
                              observation: TemporalNormalizationSurveyLightingInboxReferencesV1.Observation,
                              value: RoundSessionV1)] = []
        for source in sources {
            for observation in source.surveyLightingInbox.observations {
                if case let .round(value) = observation.value {
                    roundEndpoints.append((source.snapshot, observation, value))
                }
            }
        }
        let roundIndex = try TemporalNormalizationRoundReferenceIndexV1(rounds: roundEndpoints.map(\.value))
        for source in sources {
            for quarantine in source.history.history.quarantines
                where quarantine.workspaceID == reservation.workspaceID && quarantine.mutationID == reservation.mutationID.rawValue {
                failures.append(.quarantinedMutation(source.snapshot, quarantine))
            }
            let canonical = Self.canonicalBranches(records: source.snapshot.records, history: source.history)
            let commands = source.history.entries.map { CommandBranch(entry: $0, disposition: Self.commandDisposition($0.envelope.command)) }
            branches.append(.init(source: source, canonical: canonical, commands: commands))
            for branch in canonical where branch.count > 0 {
                if case .unsupportedAffectedOwner = branch.disposition {
                    failures.append(.unsupportedCanonical(source.snapshot, branch.field))
                }
            }
            for branch in commands {
                if branch.entry.envelope.workspaceID == reservation.workspaceID,
                   branch.entry.envelope.mutationID == reservation.mutationID {
                    failures.append(.mutationIdentityOccupied(source.snapshot, branch.entry))
                }
                if case .unsupportedAffectedOwner = branch.disposition {
                    failures.append(.unsupportedCommand(source.snapshot, branch.entry))
                }
                if case let .applyFieldDraft(value) = branch.entry.envelope.command {
                    // Destination continuation/review embeds separate retained
                    // source-owner bindings. The photo/staging slice cannot
                    // declare those endpoints complete from checkpoint bytes.
                    if value.continuationBinding != nil {
                        failures.append(.unsupportedCommand(source.snapshot, branch.entry))
                    }
                    if case .resolveConflict = value.postImage {
                        failures.append(.unsupportedCommand(source.snapshot, branch.entry))
                    }
                }
                // This is the incumbent typed envelope dependency list, not a
                // scan of arbitrary strings. Preserve every historical origin.
                switch branch.entry.envelope.command {
                case .finalizeCheck, .finalizeCorrection, .recordWork:
                    // These incumbent writers bind content SHA digests here,
                    // not ContentIDs. Their genuine file descriptors below
                    // carry byte ownership; retain the commitment unchanged.
                    break
                default:
                    if branch.entry.envelope.workspaceID == reservation.workspaceID,
                       branch.entry.envelope.contentDependencyIDs.contains(reservation.contentID) {
                        failures.append(.retainedOwner(.historyDependency(source.snapshot, branch.entry)))
                    }
                }
            }
            // DraftImmutableContentWriteRequestV1.relativePath is the fixed
            // original-content namespace. Compare only typed file descriptors,
            // including thumbnails: never interpret an EvidenceID as ContentID.
            let originalPath = "content/\(reservation.workspaceID.rawValue.uuidString.lowercased())/\(reservation.contentID)/original.bin"
            for reference in source.workflowFile.references {
                let paths: [String]
                switch reference.binding {
                case let .evidence(value): paths = [value.relativePath, value.thumbnailRelativePath]
                case let .acceptedEvidence(value): paths = [value.relativePath, value.thumbnailRelativePath]
                case let .report(value): paths = [value.snapshotRelativePath] + [value.pdfRelativePath].compactMap { $0 }
                case let .finalization(value):
                    paths = [value.snapshotRelativePath] + [value.payload.reportInsert?.pdfRelativePath].compactMap { $0 }
                case let .work(value):
                    paths = value.writerAuthority?.evidenceInsert.map { [$0.relativePath, $0.thumbnailRelativePath] } ?? []
                case let .reportTransition(value):
                    var named = [value.reportBefore.snapshotRelativePath]
                    if let path = value.reportBefore.pdfRelativePath { named.append(path) }
                    switch value.transition {
                    case let .pendingToReady(path, _, _): named.append(path)
                    case .pendingToFailed, .failedToPending: break
                    }
                    paths = named
                // Lawfully retained legacy headers contain only logical IDs
                // and semantic/digest commitments; file rows/acceptance bodies
                // are separately inventoried. Never reconstruct absent bodies.
                case .legacyFinalization, .legacyCorrection: paths = []
                }
                if paths.contains(originalPath) {
                    failures.append(.retainedOwner(.workflowFile(source.snapshot, reference)))
                }
            }
            for observation in source.temporal.observations {
                let owned: Bool
                switch observation.value {
                case let .clip(value): owned = matches(value.original) || matches(value.locator)
                case let .derivative(value):
                    owned = matches(value.content) || matches(value.locator) ||
                        (value.workspaceID == reservation.workspaceID && value.source.contentID == reservation.contentID)
                case .anchor, .captureReview, .retention: owned = false
                }
                if owned { failures.append(.retainedOwner(.temporal(source.snapshot, observation))) }
            }
            for observation in source.document.byteObservations {
                let owned: Bool
                switch observation.binding {
                case let .requiredManifest(workspace, _, entry):
                    owned = workspace == reservation.workspaceID && entry.contentID == reservation.contentID
                case let .importedOriginal(_, entry): owned = matches(entry.reference) || matches(entry.locator)
                case let .planContent(workspace, _, binding):
                    owned = workspace == reservation.workspaceID && binding.contentID == reservation.contentID
                }
                if owned { failures.append(.retainedOwner(.document(source.snapshot, observation))) }
            }
            for observation in source.privacy.byteObservations {
                let owned: Bool
                switch observation.binding {
                case let .original(value, _), let .derivative(value, _), let .canonicalEvidence(value, _): owned = matches(value)
                case let .regionSource(value):
                    owned = value.workspaceID == reservation.workspaceID && value.sourceContentID == reservation.contentID
                case let .review(value):
                    owned = value.workspaceID == reservation.workspaceID &&
                        (value.sourceContentID == reservation.contentID || value.derivativeContentID == reservation.contentID)
                }
                if owned { failures.append(.retainedOwner(.privacy(source.snapshot, observation))) }
            }
            for observation in source.evidenceMetadata.byteObservations {
                let owned: Bool
                switch observation.binding {
                case let .associationCurrent(value): owned = value.contentID.map { matches(value.workspaceID, $0) } ?? false
                case let .associationPrevious(value): owned = value.previousContentID.map { matches(value.workspaceID, $0) } ?? false
                case let .orderedItem(sequence, item):
                    owned = sequence.workspaceID == reservation.workspaceID && item.contentID == reservation.contentID
                }
                if owned { failures.append(.retainedOwner(.evidenceMetadata(source.snapshot, observation))) }
            }
            // C10 stores the concrete content key independently of its logical
            // evidence ID. Subject, comparison and waiver descriptors from every
            // canonical/history observation retain ownership even after deletion.
            for reference in source.evidenceSemantic.references {
                switch reference.binding {
                case let .evidenceQuality(value):
                    if value.workspaceID == reservation.workspaceID && value.contentID == reservation.contentID {
                        failures.append(.retainedOwner(.captureQuality(source.snapshot, reference)))
                    }
                // These families retain their own unsupported dispositions.
                // Never reinterpret their logical evidence IDs as content IDs.
                case .evidenceContext, .pairedObservation, .claimEvidence, .attestationManifest: break
                }
            }
            for reference in source.draftHistory.references {
                switch reference.binding {
                case let .content(value):
                    if matches(value) { failures.append(.retainedOwner(.draft(source.snapshot, reference))) }
                case let .reservation(value):
                    if matches(value.locator) { failures.append(.retainedOwner(.draft(source.snapshot, reference))) }
                case .purposePayload: break // Every checkpoint is dispatched below.
                case .commitPlan: failures.append(.unresolvedDraftPlan(source.snapshot, reference))
                }
            }
            for observation in source.knownDraftPayloads.observations {
                if case .unresolvedCodec = observation.payload { failures.append(.unknownPurpose(source.snapshot, observation)) }
            }
            for reference in source.knownDraftPayloads.references {
                switch reference.binding {
                case let .content(value):
                    if matches(value) { failures.append(.retainedOwner(.purpose(source.snapshot, reference))) }
                case .photoRaw, .photoPair:
                    if try TemporalNormalizationKnownDraftPayloadReferencesV1.photoOwnsOriginal(
                        reference.binding, workspaceID: reservation.workspaceID, contentID: reservation.contentID) {
                        failures.append(.retainedOwner(.purpose(source.snapshot, reference)))
                    }
                case .rawStage:
                    // A pre-byte intent names stage/evidence identities and an
                    // expected count, not a ContentID. Raw-ready/pair bodies and
                    // independently inventoried staging/reservation rows carry
                    // actual content ownership when they exist.
                    break
                case let .round(value):
                    let positions = try roundIndex.matchingPositions(value)
                    if positions.isEmpty { failures.append(.unresolvedPurpose(source.snapshot, reference)) }
                    for position in positions {
                        let endpoint = roundEndpoints[position]
                        if endpoint.value.items.contains(where: { $0.requirement.requiredContent.contains(where: matches) }) {
                            failures.append(.retainedOwner(.roundEndpoint(source.snapshot, reference,
                                endpoint.snapshot, endpoint.observation)))
                        }
                    }
                case .myDayEligible, .myDayPlan,
                     .repetitiveCheckpoint, .retainedSourceGraph, .destinationPredecessor:
                    failures.append(.unresolvedPurpose(source.snapshot, reference))
                }
            }
            if !source.snapshot.records.reports.isEmpty {
                if let reportContent = source.reportContent {
                    for reference in reportContent.references {
                        switch reference.binding {
                        case let .content(value):
                            if matches(value) { failures.append(.retainedOwner(.report(source.snapshot, reference))) }
                        case let .locator(value):
                            if matches(value) { failures.append(.retainedOwner(.report(source.snapshot, reference))) }
                        case let .temporal(value):
                            // The report names the original explicitly. A digest
                            // mismatch cannot turn that owner into absence.
                            if value.workspaceID == reservation.workspaceID && value.contentID == reservation.contentID {
                                failures.append(.retainedOwner(.report(source.snapshot, reference)))
                            }
                            // The genuine report visitor has already applied
                            // the incumbent exact clip/anchor endpoint law.
                        case let .legacyEvidence(value):
                            if value.relativePath == originalPath || value.thumbnailRelativePath == originalPath {
                                failures.append(.retainedOwner(.report(source.snapshot, reference)))
                            }
                        case let .privacy(value):
                            if value.workspaceID == reservation.workspaceID && value.derivativeContentID == reservation.contentID {
                                failures.append(.retainedOwner(.report(source.snapshot, reference)))
                            }
                        case .output, .claim, .review:
                            // Closed output/claim/review identities and hashes
                            // remain in the original report observation. Their
                            // contracts carry no managed-file path or ContentID;
                            // never invert them into a physical byte owner.
                            // Concrete input descriptors are independently
                            // inventoried across all canonical/history families.
                            break
                        }
                    }
                } else { failures.append(.reportMemberOrSemanticAdmission(source.snapshot)) }
            }
            for observation in source.authorityMeasurement.byteObservations {
                let owned: Bool
                switch observation.binding {
                case let .authorityContent(_, value), let .calibrationSource(_, value),
                     let .captureEvidence(_, value), let .qualityEvidence(_, value): owned = matches(value)
                case let .authorityLocator(_, value): owned = matches(value)
                }
                if owned { failures.append(.retainedOwner(.authorityMeasurement(source.snapshot, observation))) }
            }
            for reference in source.surveyLightingInbox.references {
                switch reference.binding {
                case let .content(value):
                    if matches(value) { failures.append(.retainedOwner(.survey(source.snapshot, reference))) }
                case let .locator(value):
                    if matches(value) { failures.append(.retainedOwner(.survey(source.snapshot, reference))) }
                case .responseContent:
                    failures.append(.unresolvedResponse(source.snapshot, reference))
                }
            }
            for reference in source.definitionAccessibility.references {
                failures.append(.unresolvedDefinition(source.snapshot, reference))
            }
            for observation in source.assetPartyRequirement.observations {
                switch observation.value {
                case let .qualification(value):
                    if value.credentialLocator != nil { failures.append(.unresolvedAccountability(source.snapshot, observation)) }
                case let .signoff(value):
                    if value.externalEvidenceID != nil || value.qualification?.credentialLocator != nil {
                        failures.append(.unresolvedAccountability(source.snapshot, observation))
                    }
                case .party, .siteRole, .actor: break
                // These other families keep their own branch dispositions.
                case .kindBinding, .workflowBinding, .product, .lifecycle, .successor,
                     .workScope, .functionalDescriptor, .functionalEvent, .requirement, .contactImport: break
                }
            }
            for reference in source.activityLabelReliability.references {
                switch reference.binding {
                case let .content(value):
                    if matches(value) { failures.append(.retainedOwner(.activity(source.snapshot, reference))) }
                case let .locator(value):
                    if matches(value) { failures.append(.retainedOwner(.activity(source.snapshot, reference))) }
                case .completedFile, .compatibilitySnapshot:
                    failures.append(.unresolvedActivityFile(source.snapshot, reference))
                }
            }
        }
        self.sources = branches; blockers = failures
    }

    static func canonicalBranches(records: V4BackupRecordsV1,
                                  history: TemporalNormalizationHistoryObservationV1) -> [CanonicalBranch] {
        [
            .init(field: .guidedSurveys, count: records.guidedSurveys.count, disposition: .concreteDescriptors),
            .init(field: .assetLocators, count: records.assetLocators.count, disposition: .unsupportedAffectedOwner),
            .init(field: .schedules, count: records.schedules.count, disposition: .unsupportedAffectedOwner),
            .init(field: .plans, count: records.plans.count, disposition: .concreteDescriptors),
            .init(field: .placementPoses, count: records.placementPoses.count, disposition: .unsupportedAffectedOwner),
            .init(field: .evidenceContexts, count: records.evidenceContexts.count, disposition: .unsupportedAffectedOwner),
            .init(field: .pairedObservationLinks, count: records.pairedObservationLinks.count, disposition: .unsupportedAffectedOwner),
            .init(field: .lighting, count: records.lighting.count, disposition: .concreteDescriptors),
            .init(field: .lightingDayInventoryWorkflows, count: records.lightingDayInventoryWorkflows.count, disposition: .concreteDescriptors),
            .init(field: .lightingNightWorkflows, count: records.lightingNightWorkflows.count, disposition: .concreteDescriptors),
            .init(field: .assistanceAcceptanceReceipts, count: records.assistanceAcceptanceReceipts.count, disposition: .unsupportedAffectedOwner),
            .init(field: .temporalEvidence, count: records.temporalEvidence.count, disposition: .concreteDescriptors),
            .init(field: .acceptedLabelGenerationSnapshots, count: records.acceptedLabelGenerationSnapshots.count, disposition: .concreteDescriptors),
            .init(field: .operationalContacts, count: records.operationalContacts.count, disposition: .unsupportedAffectedOwner),
            .init(field: .activityContracts, count: records.activityContracts.count, disposition: .concreteDescriptors),
            .init(field: .workResources, count: records.workResources.count, disposition: .unsupportedAffectedOwner),
            .init(field: .serviceRequests, count: records.serviceRequests.count, disposition: .unsupportedAffectedOwner),
            .init(field: .serviceRequestDispositionEvents, count: records.serviceRequestDispositionEvents.count, disposition: .unsupportedAffectedOwner),
            .init(field: .serviceRequestWorkLinkEvents, count: records.serviceRequestWorkLinkEvents.count, disposition: .unsupportedAffectedOwner),
            .init(field: .serviceReliabilityIncidents, count: records.serviceReliabilityIncidents.count, disposition: .typedOwnerEdges),
            .init(field: .serviceImpactSegments, count: records.serviceImpactSegments.count, disposition: .concreteDescriptors),
            .init(field: .serviceCauseAssertions, count: records.serviceCauseAssertions.count, disposition: .typedOwnerEdges),
            .init(field: .serviceRemedyAssertions, count: records.serviceRemedyAssertions.count, disposition: .typedOwnerEdges),
            .init(field: .serviceRepairIntervals, count: records.serviceRepairIntervals.count, disposition: .typedOwnerEdges),
            .init(field: .serviceRestorationAssertions, count: records.serviceRestorationAssertions.count, disposition: .typedOwnerEdges),
            .init(field: .qualifiedServiceExposures, count: records.qualifiedServiceExposures.count, disposition: .typedOwnerEdges),
            .init(field: .serviceReliabilityReceipts, count: records.serviceReliabilityReceipts.count, disposition: .typedOwnerEdges),
            .init(field: .myDayPlans, count: records.myDayPlans.count, disposition: .unsupportedAffectedOwner),
            .init(field: .myDayCarryoverReceipts, count: records.myDayCarryoverReceipts.count, disposition: .unsupportedAffectedOwner),
            .init(field: .nonactivePlanReferences, count: records.nonactivePlanReferences.count, disposition: .unsupportedAffectedOwner),
            .init(field: .evidenceAssociationEvents, count: records.evidenceAssociationEvents.count, disposition: .concreteDescriptors),
            .init(field: .evidenceSequenceRevisions, count: records.evidenceSequenceRevisions.count, disposition: .concreteDescriptors),
            .init(field: .shopReportProfiles, count: records.shopReportProfiles.count, disposition: .unsupportedAffectedOwner),
            .init(field: .roundSessions, count: records.roundSessions.count, disposition: .concreteDescriptors),
            .init(field: .importMappingProfiles, count: records.importMappingProfiles.count, disposition: .unsupportedAffectedOwner),
            .init(field: .bulkSessions, count: records.bulkSessions.count, disposition: .unsupportedAffectedOwner),
            .init(field: .bulkCommitReceipts, count: records.bulkCommitReceipts.count, disposition: .unsupportedAffectedOwner),
            .init(field: .evidenceQuality, count: (records.evidenceQuality.map { [$0.ruleSets.count, $0.assessments.count, $0.waivers.count, $0.receipts.count, $0.effectProvenance.count].reduce(0, +) } ?? 0), disposition: .concreteDescriptors),
            .init(field: .fastSurveyInbox, count: (records.fastSurveyInbox.map { [$0.inboxItems.count, $0.promotions.count, $0.snippets.count, $0.snippetInsertions.count, $0.receipts.count, $0.effectProvenance.count].reduce(0, +) } ?? 0), disposition: .concreteDescriptors),
            .init(field: .reinspectionExceptionQueue, count: (records.reinspectionExceptionQueue.map { [$0.plans.count, $0.attestations.count, $0.acknowledgements.count, $0.receipts.count, $0.effectProvenance.count].reduce(0, +) } ?? 0), disposition: .unsupportedAffectedOwner),
            .init(field: .entityIdentityResolution, count: (records.entityIdentityResolution.map { [$0.aliasLinks.count, $0.consolidationReceipts.count, $0.mutationReceipts.count].reduce(0, +) } ?? 0), disposition: .unsupportedAffectedOwner),
            .init(field: .practiceWorkspaceProvenance, count: (records.practiceWorkspaceProvenance == nil ? 0 : 1), disposition: .unsupportedAffectedOwner),
            .init(field: .partsStockSnapshot, count: (records.partsStockSnapshot.map { [$0.parts.count, $0.locations.count, $0.movements.count, $0.uses.count, $0.reversals.count, $0.returns.count, $0.abandonments.count].reduce(0, +) } ?? 0), disposition: .unsupportedAffectedOwner),
            .init(field: .surveyDefinitions, count: records.surveyDefinitions.count, disposition: .typedOwnerEdges),
            .init(field: .accessibleDocumentAssessments, count: records.accessibleDocumentAssessments.count, disposition: .unsupportedAffectedOwner),
            .init(field: .fieldReferences, count: records.fieldReferences.count, disposition: .concreteDescriptors),
            .init(field: .recoverabilityReceipts, count: records.recoverabilityReceipts.count, disposition: .unsupportedAffectedOwner),
            .init(field: .clientCapabilities, count: records.clientCapabilities.count, disposition: .unsupportedAffectedOwner),
            .init(field: .privacyTransforms, count: records.privacyTransforms.count, disposition: .concreteDescriptors),
            .init(field: .measurementIntegrity, count: records.measurementIntegrity.count, disposition: .concreteDescriptors),
            .init(field: .packageEvolution, count: records.packageEvolution.count, disposition: .closedLogicalMetadata),
            .init(field: .fieldDrafts, count: records.fieldDrafts.count, disposition: .concreteDescriptors),
            .init(field: .workPackets, count: records.workPackets.count, disposition: .unsupportedAffectedOwner),
            .init(field: .inspectionReview, count: records.inspectionReview.count, disposition: .unsupportedAffectedOwner),
            .init(field: .evidenceAssurance, count: records.evidenceAssurance.count, disposition: .unsupportedAffectedOwner),
            .init(field: .functionalRelationships, count: records.functionalRelationships.count, disposition: .unsupportedAffectedOwner),
            .init(field: .authorityCriterion, count: records.authorityCriterion.count, disposition: .concreteDescriptors),
            .init(field: .assetSemantics, count: records.assetSemantics.count, disposition: .unsupportedAffectedOwner),
            .init(field: .assetCompositionEdges, count: records.assetCompositionEdges.count, disposition: .unsupportedAffectedOwner),
            .init(field: .assetCompositionEvents, count: records.assetCompositionEvents.count, disposition: .unsupportedAffectedOwner),
            .init(field: .assetPlacementEvents, count: records.assetPlacementEvents.count, disposition: .closedLogicalMetadata),
            .init(field: .assets, count: records.assets.count, disposition: .closedLogicalMetadata),
            .init(field: .deletionLedger, count: records.deletionLedger?.entries.count ?? 0, disposition: .closedLogicalMetadata),
            .init(field: .evidenceFiles, count: records.evidenceFiles.count, disposition: .concreteDescriptors),
            .init(field: .issues, count: records.issues.count, disposition: .typedOwnerEdges),
            .init(field: .locationHierarchyEvents, count: records.locationHierarchyEvents.count, disposition: .unsupportedAffectedOwner),
            .init(field: .locationMigrationReceipts, count: records.locationMigrationReceipts.count, disposition: .unsupportedAffectedOwner),
            .init(field: .locationNodes, count: records.locationNodes.count, disposition: .unsupportedAffectedOwner),
            .init(field: .mutationHistory, count: history.entries.count, disposition: .typedOwnerEdges),
            .init(field: .packets, count: records.packets.count, disposition: .typedOwnerEdges),
            .init(field: .partyAccountability, count: records.partyAccountability.count, disposition: .typedOwnerEdges),
            .init(field: .recordsSchemaVersion, count: 1, disposition: .closedLogicalMetadata),
            .init(field: .reports, count: records.reports.count, disposition: .concreteDescriptors),
            .init(field: .requirementAssurance, count: records.requirementAssurance.count, disposition: .closedLogicalMetadata),
            .init(field: .savedSmartViews, count: records.savedSmartViews.count, disposition: .unsupportedAffectedOwner),
            .init(field: .sites, count: records.sites.count, disposition: .closedLogicalMetadata),
            .init(field: .workflowRecords, count: records.workflowRecords.count, disposition: .typedOwnerEdges),
        ]
    }
    static func commandDisposition(_ command: WorkspaceCommandV1) -> Disposition {
        switch command {
        case .createFirstSign: return .closedLogicalMetadata
        case .createCheckDraft: return .closedLogicalMetadata
        case .acceptCheckEvidence: return .concreteDescriptors
        case .updateSiteTimeZone: return .closedLogicalMetadata
        case .deleteAsset: return .closedLogicalMetadata
        case .deleteSite: return .closedLogicalMetadata
        case .eraseWorkspace: return .closedLogicalMetadata
        case .finalizeCheck: return .concreteDescriptors
        case .finalizeCorrection: return .concreteDescriptors
        case .transitionReportPDF: return .concreteDescriptors
        case .recordWork: return .concreteDescriptors
        case .restoreWorkspace: return .unsupportedAffectedOwner
        case .archiveEntities: return .closedLogicalMetadata
        case .applyLocationHierarchyChange: return .unsupportedAffectedOwner
        case .applyAssetPlacementChange: return .unsupportedAffectedOwner
        case .applyAssetCompositionChange: return .unsupportedAffectedOwner
        case .applySavedSmartView: return .unsupportedAffectedOwner
        // C12 commitments retain evaluator/kind/logical evidence identifiers.
        // The incumbent C13/C14 and workflow/media bridges own actual bytes;
        // do not invent content identity or invert a historical workflow hash.
        case .applyRequirementAssurance: return .closedLogicalMetadata
        case .applyPartyAccountability: return .typedOwnerEdges
        case .applyPartyContactSiteRoleImport: return .unsupportedAffectedOwner
        case .applyAssetSemantics: return .unsupportedAffectedOwner
        case .applyAuthorityCriterion: return .concreteDescriptors
        case .applyFunctionalRelationship: return .unsupportedAffectedOwner
        case .applyEvidenceAssurance: return .unsupportedAffectedOwner
        case .applyInspectionReview: return .unsupportedAffectedOwner
        case .applyWorkPacket: return .unsupportedAffectedOwner
        case .applyFieldDraft: return .concreteDescriptors
        case .applyPackagePromotion: return .closedLogicalMetadata
        case .applyMeasurementIntegrity: return .concreteDescriptors
        case .applyPrivacyTransform: return .concreteDescriptors
        case .applyEvidenceMetadata: return .concreteDescriptors
        case .applyClientCapability: return .unsupportedAffectedOwner
        case .applyFieldReference: return .concreteDescriptors
        case .applyAccessibleDocumentAssessment: return .unsupportedAffectedOwner
        case .applySurveyDefinition: return .typedOwnerEdges
        case .applySurveySession: return .concreteDescriptors
        case .applyAssetLocator: return .unsupportedAffectedOwner
        case .applySchedule: return .unsupportedAffectedOwner
        case .applyPlan: return .concreteDescriptors
        case .applyPlacementPose: return .unsupportedAffectedOwner
        case .applyEvidenceContext: return .unsupportedAffectedOwner
        case .applyLighting: return .concreteDescriptors
        case .applyLightingDayInventory: return .concreteDescriptors
        case .applyLightingNightWorkflow: return .concreteDescriptors
        case .applyAssistanceAcceptance: return .unsupportedAffectedOwner
        case .applyTemporalEvidence: return .concreteDescriptors
        case .applyAssetLabel: return .concreteDescriptors
        case .applyOperationalContact: return .unsupportedAffectedOwner
        case .applyActivityContract: return .concreteDescriptors
        case .applyPortableReview: return .unsupportedAffectedOwner
        case .applyWorkResource: return .unsupportedAffectedOwner
        case .applyPartsStock: return .unsupportedAffectedOwner
        case .applyMyDay: return .unsupportedAffectedOwner
        case .applyServiceRequest: return .unsupportedAffectedOwner
        case .applyServiceReliability: return .concreteDescriptors
        case .applyShopReportProfile: return .unsupportedAffectedOwner
        case .applyRoundSession: return .concreteDescriptors
        case .applyImportBulk: return .unsupportedAffectedOwner
        case .applyEvidenceQuality: return .concreteDescriptors
        case .applyFastSurveyInbox: return .concreteDescriptors
        case .applyReinspectionException: return .unsupportedAffectedOwner
        case .applyEntityIdentityResolution: return .unsupportedAffectedOwner
        case .applyWorkspaceExperience: return .unsupportedAffectedOwner
        }
    }
}
