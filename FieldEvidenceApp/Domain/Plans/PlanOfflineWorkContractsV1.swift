import Foundation

enum PlanOfflineWorkFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidDigest
    case wrongWorkspace
    case missingExactSource
    case staleSource
    case notOpenable
    case insufficientStorage
    case protectedDataUnavailable
    case historicRevisionMismatch
    case reviewReceiptMismatch
    case limitExceeded
}

enum PlanOfflineWorkLimitsV1 {
    static let maximumPlacements = PlanLimitsV1.maximumPlacements
    static let maximumFindings = 128
    static let maximumTextBytes = 512
    static let maximumZoomMillionths: Int64 = 16_000_000

    static func digest(_ value: String) throws {
        guard KernelCanonicalHashV1.validSHA256(value) else { throw PlanOfflineWorkFailureV1.invalidDigest }
    }

    static func id(_ value: UUID) throws {
        guard value != PlanLimitsV1.zeroUUID else { throw PlanOfflineWorkFailureV1.invalidValue }
    }

    static func instant(_ value: Date) throws {
        guard value.timeIntervalSinceReferenceDate.isFinite else { throw PlanOfflineWorkFailureV1.invalidValue }
    }

    static func text(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= maximumTextBytes,
              value == value.precomposedStringWithCanonicalMapping,
              value.trimmingCharacters(in: .whitespacesAndNewlines) == value else {
            throw PlanOfflineWorkFailureV1.invalidValue
        }
    }
}

enum PlanApplicabilityV1: String, Codable, CaseIterable, Hashable, Sendable {
    case required = "REQUIRED"
    case optional = "OPTIONAL"
    case notApplicable = "NOT_APPLICABLE"
}

enum PlanDocumentOpenabilityStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case openable = "OPENABLE"
    case missing = "MISSING"
    case partial = "PARTIAL"
    case corrupt = "CORRUPT"
    case encrypted = "ENCRYPTED"
    case unsupportedDocument = "UNSUPPORTED_DOCUMENT"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case uncheckable = "UNCHECKABLE"
}

enum PlanRevisionSelectionDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case current = "CURRENT"
    case historic = "HISTORIC"
}

struct PlanOfflineWorkRequestV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let packet: WorkPacketManifestReferenceV1
    let item: WorkPacketItemReferenceV1
    let applicability: PlanApplicabilityV1
    let exactPlanRevision: PlanRevisionReferenceV1
    let checkedAt: Date

    init(workspaceID: WorkspaceID, packet: WorkPacketManifestReferenceV1,
         item: WorkPacketItemReferenceV1,
         applicability: PlanApplicabilityV1, exactPlanRevision: PlanRevisionReferenceV1,
         checkedAt: Date) throws {
        self.workspaceID = workspaceID; self.packet = packet; self.item = item
        self.applicability = applicability; self.exactPlanRevision = exactPlanRevision
        self.checkedAt = checkedAt
        try packet.validate(); try item.validate(); try exactPlanRevision.validate()
        try PlanOfflineWorkLimitsV1.instant(checkedAt)
        guard applicability != .notApplicable, packet.workspaceID == workspaceID,
              item.workspaceID == workspaceID, item.packetID == packet.packetID,
              item.packetVersion == packet.packetVersion,
              item.manifestSHA256 == packet.manifestSHA256 else {
            throw PlanOfflineWorkFailureV1.invalidValue
        }
    }
}

enum PlanOfflineReadinessFindingCodeV1: String, Codable, CaseIterable, Hashable, Sendable {
    case referenceMissing = "REFERENCE_MISSING"
    case referenceExpired = "REFERENCE_EXPIRED"
    case referenceWithdrawn = "REFERENCE_WITHDRAWN"
    case referenceSuperseded = "REFERENCE_SUPERSEDED"
    case referenceStale = "REFERENCE_STALE"
    case contentMissing = "CONTENT_MISSING"
    case contentPartial = "CONTENT_PARTIAL"
    case contentCorrupt = "CONTENT_CORRUPT"
    case documentEncrypted = "DOCUMENT_ENCRYPTED"
    case documentUnsupported = "DOCUMENT_UNSUPPORTED"
    case documentUncheckable = "DOCUMENT_UNCHECKABLE"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case insufficientStorage = "INSUFFICIENT_STORAGE"
    case storageUncheckable = "STORAGE_UNCHECKABLE"
    case historicSource = "HISTORIC_SOURCE"
}

struct PlanOfflineReadinessFindingV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let code: PlanOfflineReadinessFindingCodeV1
    let remediationKey: String

    init(code: PlanOfflineReadinessFindingCodeV1, remediationKey: String) throws {
        self.code = code
        self.remediationKey = remediationKey
        try PlanOfflineWorkLimitsV1.text(remediationKey)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.code.rawValue, lhs.remediationKey) < (rhs.code.rawValue, rhs.remediationKey)
    }
}

/// Codable copy of the exact C23 projection. The source readiness value itself
/// intentionally remains non-Codable because it must be recomputed from local
/// content. This snapshot never becomes a new persistence family.
struct PlanOfflineFieldReferenceProofV1: Codable, Equatable, Hashable, Sendable {
    let bindingID: UUID
    let releaseID: UUID
    let releaseRevision: UInt64
    let releaseSHA256: String
    let manifestSHA256: String
    let availability: FieldReferenceAvailabilityV1
    let missingContentIDs: [String]
    let readinessSHA256: String
    let projectionSHA256: String

    init(_ value: WorkSessionFieldReferenceProjectionV1) throws {
        try value.validate()
        bindingID = value.bindingID
        releaseID = value.releaseID
        releaseRevision = value.releaseRevision
        releaseSHA256 = value.releaseSHA256
        manifestSHA256 = value.manifestSHA256
        availability = value.availability
        missingContentIDs = value.missingContentIDs.sorted()
        readinessSHA256 = value.readinessSHA256
        projectionSHA256 = value.projectionSHA256
        try validate()
    }

    func validate() throws {
        try PlanOfflineWorkLimitsV1.id(bindingID)
        try PlanOfflineWorkLimitsV1.id(releaseID)
        try PlanOfflineWorkLimitsV1.digest(releaseSHA256)
        try PlanOfflineWorkLimitsV1.digest(manifestSHA256)
        try PlanOfflineWorkLimitsV1.digest(readinessSHA256)
        try PlanOfflineWorkLimitsV1.digest(projectionSHA256)
        try missingContentIDs.forEach(PlanOfflineWorkLimitsV1.text)
        guard releaseRevision > 0, missingContentIDs == missingContentIDs.sorted(),
              Set(missingContentIDs).count == missingContentIDs.count,
              availability != .readyOffline || missingContentIDs.isEmpty else {
            throw PlanOfflineWorkFailureV1.invalidValue
        }
    }
}

struct PlanDocumentOpenabilityObservationV1: Codable, Equatable, Hashable, Sendable {
    let contentID: String
    let expectedByteLength: Int64
    let expectedSHA256: String
    let observedByteLength: Int64?
    let observedSHA256: String?
    let mediaType: String
    let state: PlanDocumentOpenabilityStateV1
    let checkedAt: Date
    let observationSHA256: String

    init(contentBinding: PlanContentBindingV1, observedByteLength: Int64?,
         observedSHA256: String?, state: PlanDocumentOpenabilityStateV1,
         checkedAt: Date) throws {
        try contentBinding.validate()
        contentID = contentBinding.contentID
        expectedByteLength = contentBinding.byteLength
        expectedSHA256 = contentBinding.contentSHA256
        self.observedByteLength = observedByteLength
        self.observedSHA256 = observedSHA256
        mediaType = contentBinding.mediaType
        self.state = state
        self.checkedAt = checkedAt
        observationSHA256 = try PlanCanonicalCodecV1.sha256(Basis(
            contentID: contentID, expectedByteLength: expectedByteLength,
            expectedSHA256: expectedSHA256, observedByteLength: observedByteLength,
            observedSHA256: observedSHA256, mediaType: mediaType, state: state,
            checkedAt: checkedAt
        ))
        try validate(contentBinding: contentBinding)
    }

    func validate(contentBinding: PlanContentBindingV1) throws {
        try contentBinding.validate()
        try PlanOfflineWorkLimitsV1.text(contentID)
        try PlanOfflineWorkLimitsV1.text(mediaType)
        try PlanOfflineWorkLimitsV1.digest(expectedSHA256)
        try observedSHA256.map(PlanOfflineWorkLimitsV1.digest)
        try PlanOfflineWorkLimitsV1.instant(checkedAt)
        let exactBytes = observedByteLength == expectedByteLength && observedSHA256 == expectedSHA256
        guard contentID == contentBinding.contentID,
              expectedByteLength == contentBinding.byteLength,
              expectedSHA256 == contentBinding.contentSHA256,
              mediaType == contentBinding.mediaType,
              observedByteLength.map({ $0 >= 0 }) ?? true,
              state != .openable || exactBytes,
              observationSHA256 == (try PlanCanonicalCodecV1.sha256(basis)) else {
            throw PlanOfflineWorkFailureV1.invalidValue
        }
    }

    private var basis: Basis { .init(contentID: contentID, expectedByteLength: expectedByteLength, expectedSHA256: expectedSHA256, observedByteLength: observedByteLength, observedSHA256: observedSHA256, mediaType: mediaType, state: state, checkedAt: checkedAt) }
    private struct Basis: Codable { let contentID: String; let expectedByteLength: Int64; let expectedSHA256: String; let observedByteLength: Int64?; let observedSHA256: String?; let mediaType: String; let state: PlanDocumentOpenabilityStateV1; let checkedAt: Date }
}

struct PlanOfflineWorkSourceV1: Sendable {
    let applicability: PlanApplicabilityV1
    let manifest: WorkPacketManifestV1
    let item: WorkPacketItemV1
    let fieldReferenceProjection: WorkPacketFieldReferenceProjectionV1
    let fieldReference: WorkSessionFieldReferenceProjectionV1
    let planRevision: PlanRevisionV1
    let placements: [PlanPlacementV1]
    let prerequisites: PlanPrerequisiteClosureV1
    let openability: PlanDocumentOpenabilityObservationV1
    let storage: OfflineReadinessStorageObservationV1
    let access: OfflineReadinessAccessObservationV1
    let revisionDisposition: PlanRevisionSelectionDispositionV1
    let checkedAt: Date

    func validate() throws {
        try manifest.validate(); try item.validate(); try fieldReferenceProjection.validate()
        try fieldReference.validate(expectedWorkspaceID: manifest.workspaceID,
                                    expectedSubjectKind: .workPacket,
                                    expectedSubjectID: manifest.packetID,
                                    expectedSubjectRevision: manifest.packetVersion,
                                    expectedSubjectState: fieldReferenceProjection.subjectState)
        try planRevision.validateIntrinsic()
        try prerequisites.validate(revision: planRevision, placements: placements)
        try openability.validate(contentBinding: planRevision.contentBinding)
        try PlanOfflineWorkLimitsV1.instant(checkedAt)
        guard applicability != .notApplicable, manifest.items.contains(item),
              manifest.workspaceID == planRevision.workspaceID,
              fieldReferenceProjection.workspaceID == manifest.workspaceID,
              fieldReferenceProjection.packetID == manifest.packetID,
              fieldReferenceProjection.packetVersion == manifest.packetVersion,
              fieldReferenceProjection.manifestSHA256 == manifest.manifestSHA256,
              fieldReferenceProjection.references.contains(fieldReference),
              fieldReference.workspaceID == manifest.workspaceID,
              checkedAt == openability.checkedAt,
              placements.count <= PlanOfflineWorkLimitsV1.maximumPlacements,
              Set(placements.map(\.placementID)).count == placements.count,
              placements == placements.sorted(by: { $0.placementID.uuidString < $1.placementID.uuidString }) else {
            throw PlanOfflineWorkFailureV1.staleSource
        }
    }
}

struct OfflineWorkPacketReadinessV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let persistenceMode = "DERIVED_ONLY"

    let schemaVersion: Int
    let persistenceMode: String
    let workspaceID: WorkspaceID
    let applicability: PlanApplicabilityV1
    let packet: WorkPacketManifestReferenceV1
    let item: WorkPacketItemReferenceV1
    let planRevision: PlanRevisionReferenceV1
    let contentBinding: PlanContentBindingV1
    let fieldReference: PlanOfflineFieldReferenceProofV1
    let openability: PlanDocumentOpenabilityObservationV1
    let storage: OfflineReadinessStorageObservationV1
    let protectedDataAvailable: Bool
    let revisionDisposition: PlanRevisionSelectionDispositionV1
    let requiredBytes: Int64?
    let findings: [PlanOfflineReadinessFindingV1]
    let status: OfflineReadinessStatusV1
    let checkedAt: Date
    let sourceSnapshotSHA256: String
    let readinessSHA256: String

    init(source: PlanOfflineWorkSourceV1) throws {
        try source.validate()
        let packet = try WorkPacketManifestReferenceV1(source.manifest)
        let item = try WorkPacketItemReferenceV1(manifest: source.manifest, item: source.item)
        let revision = try source.planRevision.reference
        let reference = try PlanOfflineFieldReferenceProofV1(source.fieldReference)
        let requiredBytes = Self.requiredBytes(content: source.planRevision.contentBinding,
                                               storage: source.storage)
        let findings = try Self.findings(reference: reference, openability: source.openability,
                                        storage: source.storage, requiredBytes: requiredBytes,
                                        access: source.access,
                                        revisionDisposition: source.revisionDisposition)
        let status: OfflineReadinessStatusV1 = findings.isEmpty ? .ready :
            (findings.contains(where: { $0.code == .referenceStale || $0.code == .historicSource }) ? .stale : .blocked)
        let sourceSHA = try PlanCanonicalCodecV1.sha256(SourceBasis(
            workspaceID: source.manifest.workspaceID, packet: packet, item: item,
            planRevision: revision, contentBinding: source.planRevision.contentBinding,
            fieldReference: reference, openability: source.openability,
            storage: source.storage, protectedDataAvailable: source.access.protectedDataAvailable,
            revisionDisposition: source.revisionDisposition, checkedAt: source.checkedAt
        ))
        schemaVersion = Self.schemaVersion; persistenceMode = Self.persistenceMode
        workspaceID = source.manifest.workspaceID; applicability = source.applicability
        self.packet = packet; self.item = item; planRevision = revision
        contentBinding = source.planRevision.contentBinding; fieldReference = reference
        openability = source.openability; storage = source.storage
        protectedDataAvailable = source.access.protectedDataAvailable
        revisionDisposition = source.revisionDisposition; self.requiredBytes = requiredBytes
        self.findings = findings; self.status = status; checkedAt = source.checkedAt
        sourceSnapshotSHA256 = sourceSHA
        readinessSHA256 = try PlanCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, persistenceMode: Self.persistenceMode,
            workspaceID: workspaceID, applicability: applicability, packet: packet,
            item: item, planRevision: revision, contentBinding: contentBinding,
            fieldReference: reference, openability: openability, storage: storage,
            protectedDataAvailable: protectedDataAvailable,
            revisionDisposition: revisionDisposition, requiredBytes: requiredBytes,
            findings: findings, status: status, checkedAt: checkedAt,
            sourceSnapshotSHA256: sourceSHA
        ))
        try validateIntrinsic()
    }

    func validate(source: PlanOfflineWorkSourceV1) throws {
        try validateIntrinsic(); try source.validate()
        guard self == (try Self(source: source)) else { throw PlanOfflineWorkFailureV1.staleSource }
    }

    func validateIntrinsic() throws {
        try packet.validate(); try item.validate(); try planRevision.validate()
        try contentBinding.validate(); try fieldReference.validate()
        try openability.validate(contentBinding: contentBinding)
        try findings.forEach { try PlanOfflineWorkLimitsV1.text($0.remediationKey) }
        try PlanOfflineWorkLimitsV1.instant(checkedAt)
        try PlanOfflineWorkLimitsV1.digest(sourceSnapshotSHA256)
        try PlanOfflineWorkLimitsV1.digest(readinessSHA256)
        let sourceSHA = try PlanCanonicalCodecV1.sha256(SourceBasis(
            workspaceID: workspaceID, packet: packet, item: item,
            planRevision: planRevision, contentBinding: contentBinding,
            fieldReference: fieldReference, openability: openability,
            storage: storage, protectedDataAvailable: protectedDataAvailable,
            revisionDisposition: revisionDisposition, checkedAt: checkedAt
        ))
        guard schemaVersion == Self.schemaVersion, persistenceMode == Self.persistenceMode,
              packet.workspaceID == workspaceID, item.workspaceID == workspaceID,
              item.packetID == packet.packetID, item.packetVersion == packet.packetVersion,
              item.manifestSHA256 == packet.manifestSHA256,
              findings == findings.sorted(), Set(findings).count == findings.count,
              findings.count <= PlanOfflineWorkLimitsV1.maximumFindings,
              (status == .ready) == findings.isEmpty,
              sourceSnapshotSHA256 == sourceSHA,
              readinessSHA256 == (try PlanCanonicalCodecV1.sha256(basis)) else {
            throw PlanOfflineWorkFailureV1.invalidDigest
        }
    }

    private static func requiredBytes(content: PlanContentBindingV1,
                                      storage: OfflineReadinessStorageObservationV1) -> Int64? {
        var value = content.byteLength
        for addition in [storage.reservedBytes, storage.operationReserveBytes] {
            let result = value.addingReportingOverflow(addition)
            guard !result.overflow else { return nil }
            value = result.partialValue
        }
        return value
    }

    private static func findings(reference: PlanOfflineFieldReferenceProofV1,
                                 openability: PlanDocumentOpenabilityObservationV1,
                                 storage: OfflineReadinessStorageObservationV1,
                                 requiredBytes: Int64?,
                                 access: OfflineReadinessAccessObservationV1,
                                 revisionDisposition: PlanRevisionSelectionDispositionV1) throws -> [PlanOfflineReadinessFindingV1] {
        var values: [PlanOfflineReadinessFindingV1] = []
        func add(_ code: PlanOfflineReadinessFindingCodeV1, _ key: String) throws {
            values.append(try .init(code: code, remediationKey: key))
        }
        switch reference.availability {
        case .readyOffline: break
        case .missingBytes: try add(.referenceMissing, "plan.offline.restore_reference")
        case .expired: try add(.referenceExpired, "plan.offline.renew_reference")
        case .revoked: try add(.referenceWithdrawn, "plan.offline.reference_withdrawn")
        case .superseded: try add(.referenceSuperseded, "plan.offline.select_exact_revision")
        case .staleBinding: try add(.referenceStale, "plan.offline.rebuild_packet")
        case .protectedDataUnavailable: try add(.protectedDataUnavailable, "plan.offline.unlock_device")
        case .unavailable: try add(.referenceStale, "plan.offline.recheck_reference")
        }
        switch openability.state {
        case .openable: break
        case .missing: try add(.contentMissing, "plan.offline.restore_content")
        case .partial: try add(.contentPartial, "plan.offline.restore_complete_content")
        case .corrupt: try add(.contentCorrupt, "plan.offline.restore_exact_content")
        case .encrypted: try add(.documentEncrypted, "plan.offline.use_supported_unlocked_document")
        case .unsupportedDocument: try add(.documentUnsupported, "plan.offline.use_supported_document")
        case .protectedDataUnavailable: try add(.protectedDataUnavailable, "plan.offline.unlock_device")
        case .uncheckable: try add(.documentUncheckable, "plan.offline.retry_openability")
        }
        if !access.protectedDataAvailable { try add(.protectedDataUnavailable, "plan.offline.unlock_device") }
        if storage.capacityState != .checked || requiredBytes == nil {
            try add(.storageUncheckable, "plan.offline.recheck_storage")
        } else if let available = storage.availableBytes, let requiredBytes, available < requiredBytes {
            try add(.insufficientStorage, "plan.offline.free_storage")
        }
        if revisionDisposition == .historic { try add(.historicSource, "plan.offline.historic_read_only") }
        let sorted = Array(Set(values)).sorted()
        guard sorted.count <= PlanOfflineWorkLimitsV1.maximumFindings else { throw PlanOfflineWorkFailureV1.limitExceeded }
        return sorted
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, persistenceMode: persistenceMode, workspaceID: workspaceID, applicability: applicability, packet: packet, item: item, planRevision: planRevision, contentBinding: contentBinding, fieldReference: fieldReference, openability: openability, storage: storage, protectedDataAvailable: protectedDataAvailable, revisionDisposition: revisionDisposition, requiredBytes: requiredBytes, findings: findings, status: status, checkedAt: checkedAt, sourceSnapshotSHA256: sourceSnapshotSHA256) }
    private struct SourceBasis: Codable { let workspaceID: WorkspaceID; let packet: WorkPacketManifestReferenceV1; let item: WorkPacketItemReferenceV1; let planRevision: PlanRevisionReferenceV1; let contentBinding: PlanContentBindingV1; let fieldReference: PlanOfflineFieldReferenceProofV1; let openability: PlanDocumentOpenabilityObservationV1; let storage: OfflineReadinessStorageObservationV1; let protectedDataAvailable: Bool; let revisionDisposition: PlanRevisionSelectionDispositionV1; let checkedAt: Date }
    private struct Basis: Codable { let schemaVersion: Int; let persistenceMode: String; let workspaceID: WorkspaceID; let applicability: PlanApplicabilityV1; let packet: WorkPacketManifestReferenceV1; let item: WorkPacketItemReferenceV1; let planRevision: PlanRevisionReferenceV1; let contentBinding: PlanContentBindingV1; let fieldReference: PlanOfflineFieldReferenceProofV1; let openability: PlanDocumentOpenabilityObservationV1; let storage: OfflineReadinessStorageObservationV1; let protectedDataAvailable: Bool; let revisionDisposition: PlanRevisionSelectionDispositionV1; let requiredBytes: Int64?; let findings: [PlanOfflineReadinessFindingV1]; let status: OfflineReadinessStatusV1; let checkedAt: Date; let sourceSnapshotSHA256: String }
}

struct PlanViewportPresentationV1: Codable, Equatable, Hashable, Sendable {
    static let conveysPhysicalDirection = false
    let pageID: UUID
    let zoomMillionths: Int64
    let panXMillionths: Int64
    let panYMillionths: Int64
    let displayedRotation: PlanPageRotationV1

    init(pageID: UUID, zoomMillionths: Int64, panXMillionths: Int64,
         panYMillionths: Int64, displayedRotation: PlanPageRotationV1) throws {
        self.pageID = pageID; self.zoomMillionths = zoomMillionths
        self.panXMillionths = panXMillionths; self.panYMillionths = panYMillionths
        self.displayedRotation = displayedRotation
        try PlanOfflineWorkLimitsV1.id(pageID)
        guard zoomMillionths >= 250_000,
              zoomMillionths <= PlanOfflineWorkLimitsV1.maximumZoomMillionths,
              (-PlanLimitsV1.normalizedScale...PlanLimitsV1.normalizedScale).contains(panXMillionths),
              (-PlanLimitsV1.normalizedScale...PlanLimitsV1.normalizedScale).contains(panYMillionths) else {
            throw PlanOfflineWorkFailureV1.invalidValue
        }
    }
}

struct PlanPagePresentationV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let page: PlanPageReferenceV1
    let thumbnailAvailable: Bool
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.page.presentedPageOrdinal, lhs.page.pageID.uuidString) <
            (rhs.page.presentedPageOrdinal, rhs.page.pageID.uuidString)
    }
}

struct PlanAccessiblePlacementV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let placement: PlanPlacementV1
    let accessibilityLabelKey: String
    let accessibilityOrdinal: Int

    init(placement: PlanPlacementV1, accessibilityLabelKey: String,
         accessibilityOrdinal: Int) throws {
        try placement.validateIntrinsic(); try PlanOfflineWorkLimitsV1.text(accessibilityLabelKey)
        guard accessibilityOrdinal > 0 else { throw PlanOfflineWorkFailureV1.invalidValue }
        self.placement = placement; self.accessibilityLabelKey = accessibilityLabelKey
        self.accessibilityOrdinal = accessibilityOrdinal
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.accessibilityOrdinal, lhs.placement.placementID.uuidString) <
            (rhs.accessibilityOrdinal, rhs.placement.placementID.uuidString)
    }
}

struct PlanMaterializedPoseSnapshotV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let placementID: UUID
    let event: AssetPoseEventReferenceV1
    let disposition: PoseObservationDispositionV1
    let source: PoseObservationSourceV1
    let notObservedReason: PoseNotObservedReasonV1?
    let planFrame: PlanRelativePoseFrameBindingV1?
    let snapshotSHA256: String

    init(placementID: UUID, event value: AssetPoseEventV1) throws {
        try value.validateIntrinsic(); try PlanOfflineWorkLimitsV1.id(placementID)
        let frame: PlanRelativePoseFrameBindingV1?
        if case .planRelative(let binding) = value.pose.referenceFrame { frame = binding } else { frame = nil }
        self.placementID = placementID; event = value.reference
        disposition = value.pose.disposition; source = value.source
        notObservedReason = value.pose.notObservedReason; planFrame = frame
        snapshotSHA256 = try PlanCanonicalCodecV1.sha256(Basis(
            placementID: placementID, event: value.reference,
            disposition: value.pose.disposition, source: value.source,
            notObservedReason: value.pose.notObservedReason, planFrame: frame
        ))
        try validate()
    }

    func validate() throws {
        try PlanOfflineWorkLimitsV1.id(placementID); try event.validate(); try planFrame?.validate()
        guard (disposition == .notObserved) == (notObservedReason != nil),
              disposition != .notObserved || planFrame == nil,
              snapshotSHA256 == (try PlanCanonicalCodecV1.sha256(basis)) else {
            throw PlanOfflineWorkFailureV1.invalidValue
        }
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.placementID.uuidString, lhs.event.axisID.rawValue, lhs.event.revision) <
            (rhs.placementID.uuidString, rhs.event.axisID.rawValue, rhs.event.revision)
    }
    private var basis: Basis { .init(placementID: placementID, event: event, disposition: disposition, source: source, notObservedReason: notObservedReason, planFrame: planFrame) }
    private struct Basis: Codable { let placementID: UUID; let event: AssetPoseEventReferenceV1; let disposition: PoseObservationDispositionV1; let source: PoseObservationSourceV1; let notObservedReason: PoseNotObservedReasonV1?; let planFrame: PlanRelativePoseFrameBindingV1? }
}

struct PlanWorkSurfaceStateV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let persistenceMode = "DERIVED_DEVICE_LOCAL_PRESENTATION"
    let schemaVersion: Int
    let persistenceMode: String
    let workspaceID: WorkspaceID
    let applicability: PlanApplicabilityV1
    let packet: WorkPacketManifestReferenceV1
    let item: WorkPacketItemReferenceV1
    let planRevision: PlanRevisionReferenceV1
    let pages: [PlanPagePresentationV1]
    let placements: [PlanAccessiblePlacementV1]
    let selectedPlacementID: UUID?
    let viewport: PlanViewportPresentationV1
    let resumeDraft: FieldDraftReferenceProjectionV1?
    let poseSnapshots: [PlanMaterializedPoseSnapshotV1]
    let evaluatedAt: Date
    let sourceSnapshotSHA256: String
    let stateSHA256: String

    init(source: PlanOfflineWorkSourceV1, selectedPageID: UUID,
         selectedPlacementID: UUID?, viewport: PlanViewportPresentationV1,
         resumeDraft: FieldDraftReferenceProjectionV1?,
         poseSnapshots: [PlanMaterializedPoseSnapshotV1], evaluatedAt: Date) throws {
        try source.validate(); try resumeDraft?.validate(); try PlanOfflineWorkLimitsV1.instant(evaluatedAt)
        let pages = source.planRevision.pages.map { PlanPagePresentationV1(page: $0, thumbnailAvailable: true) }.sorted()
        let placements = try source.placements.enumerated().map {
            try PlanAccessiblePlacementV1(placement: $0.element,
                                          accessibilityLabelKey: "plan.placement.item",
                                          accessibilityOrdinal: $0.offset + 1)
        }.sorted()
        let poses = poseSnapshots.sorted()
        try poses.forEach { try $0.validate() }
        guard selectedPageID == viewport.pageID,
              pages.contains(where: { $0.page.pageID == selectedPageID }),
              selectedPlacementID.map({ id in placements.contains(where: { $0.placement.placementID == id }) }) ?? true,
              Set(poses.map { "\($0.placementID.uuidString)|\($0.event.axisID.rawValue)" }).count == poses.count,
              poses.allSatisfy({ pose in placements.contains(where: { $0.placement.placementID == pose.placementID }) && pose.event.workspaceID == source.manifest.workspaceID }) else {
            throw PlanOfflineWorkFailureV1.staleSource
        }
        let packet = try WorkPacketManifestReferenceV1(source.manifest)
        let item = try WorkPacketItemReferenceV1(manifest: source.manifest, item: source.item)
        let revision = try source.planRevision.reference
        let sourceSHA = try PlanCanonicalCodecV1.sha256(SourceBasis(
            packet: packet, item: item, planRevision: revision,
            placements: placements.map(\.placement), poseSnapshots: poses
        ))
        schemaVersion = Self.schemaVersion; persistenceMode = Self.persistenceMode
        workspaceID = source.manifest.workspaceID; applicability = source.applicability
        self.packet = packet; self.item = item; planRevision = revision
        self.pages = pages; self.placements = placements
        self.selectedPlacementID = selectedPlacementID; self.viewport = viewport
        self.resumeDraft = resumeDraft; self.poseSnapshots = poses; self.evaluatedAt = evaluatedAt
        sourceSnapshotSHA256 = sourceSHA
        stateSHA256 = try PlanCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, persistenceMode: Self.persistenceMode,
            workspaceID: workspaceID, applicability: applicability, packet: packet,
            item: item, planRevision: revision, pages: pages, placements: placements,
            selectedPlacementID: selectedPlacementID, viewport: viewport,
            resumeDraft: resumeDraft, poseSnapshots: poses, evaluatedAt: evaluatedAt,
            sourceSnapshotSHA256: sourceSHA
        ))
        try validateIntrinsic()
    }

    func validateIntrinsic() throws {
        try packet.validate(); try item.validate(); try planRevision.validate()
        try pages.forEach { try $0.page.validate() }
        try placements.forEach { try $0.placement.validateIntrinsic(); try PlanOfflineWorkLimitsV1.text($0.accessibilityLabelKey) }
        try poseSnapshots.forEach { try $0.validate() }; try resumeDraft?.validate()
        try PlanOfflineWorkLimitsV1.instant(evaluatedAt)
        try PlanOfflineWorkLimitsV1.digest(sourceSnapshotSHA256)
        try PlanOfflineWorkLimitsV1.digest(stateSHA256)
        let sourceSHA = try PlanCanonicalCodecV1.sha256(SourceBasis(
            packet: packet, item: item, planRevision: planRevision,
            placements: placements.map(\.placement), poseSnapshots: poseSnapshots
        ))
        guard schemaVersion == Self.schemaVersion, persistenceMode == Self.persistenceMode,
              packet.workspaceID == workspaceID, item.workspaceID == workspaceID,
              pages == pages.sorted(), placements == placements.sorted(),
              Set(pages.map(\.page.pageID)).count == pages.count,
              Set(placements.map(\.placement.placementID)).count == placements.count,
              selectedPlacementID.map({ id in placements.contains(where: { $0.placement.placementID == id }) }) ?? true,
              pages.contains(where: { $0.page.pageID == viewport.pageID }),
              sourceSnapshotSHA256 == sourceSHA,
              stateSHA256 == (try PlanCanonicalCodecV1.sha256(basis)) else {
            throw PlanOfflineWorkFailureV1.invalidDigest
        }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, persistenceMode: persistenceMode, workspaceID: workspaceID, applicability: applicability, packet: packet, item: item, planRevision: planRevision, pages: pages, placements: placements, selectedPlacementID: selectedPlacementID, viewport: viewport, resumeDraft: resumeDraft, poseSnapshots: poseSnapshots, evaluatedAt: evaluatedAt, sourceSnapshotSHA256: sourceSnapshotSHA256) }
    private struct SourceBasis: Codable { let packet: WorkPacketManifestReferenceV1; let item: WorkPacketItemReferenceV1; let planRevision: PlanRevisionReferenceV1; let placements: [PlanPlacementV1]; let poseSnapshots: [PlanMaterializedPoseSnapshotV1] }
    private struct Basis: Codable { let schemaVersion: Int; let persistenceMode: String; let workspaceID: WorkspaceID; let applicability: PlanApplicabilityV1; let packet: WorkPacketManifestReferenceV1; let item: WorkPacketItemReferenceV1; let planRevision: PlanRevisionReferenceV1; let pages: [PlanPagePresentationV1]; let placements: [PlanAccessiblePlacementV1]; let selectedPlacementID: UUID?; let viewport: PlanViewportPresentationV1; let resumeDraft: FieldDraftReferenceProjectionV1?; let poseSnapshots: [PlanMaterializedPoseSnapshotV1]; let evaluatedAt: Date; let sourceSnapshotSHA256: String }
}

enum RebaseReviewDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case pending = "PENDING"
    case approvedActivated = "APPROVED_ACTIVATED"
    case rejected = "REJECTED"
}

struct RebaseReviewStateV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let persistenceMode = "DERIVED_REVIEW_PROJECTION"
    let schemaVersion: Int
    let persistenceMode: String
    let workspaceID: WorkspaceID
    let preview: RebasePreviewV1
    let rows: [PlanRebaseRowV1]
    let warnings: [PlanRebaseWarningV1]
    let disposition: RebaseReviewDispositionV1
    let receipt: RebaseReceiptV1?
    let evaluatedAt: Date
    let stateSHA256: String

    init(preview: RebasePreviewV1, receipt: RebaseReceiptV1?, evaluatedAt: Date) throws {
        try preview.validate(); try PlanOfflineWorkLimitsV1.instant(evaluatedAt)
        if let receipt { try receipt.validate(preview: preview) }
        let disposition: RebaseReviewDispositionV1
        switch receipt?.decision {
        case nil: disposition = .pending
        case .approved?: disposition = .approvedActivated
        case .rejected?: disposition = .rejected
        }
        schemaVersion = Self.schemaVersion; persistenceMode = Self.persistenceMode
        workspaceID = preview.workspaceID; self.preview = preview
        rows = preview.rows; warnings = preview.warnings; self.disposition = disposition
        self.receipt = receipt; self.evaluatedAt = evaluatedAt
        stateSHA256 = try PlanCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, persistenceMode: Self.persistenceMode,
            workspaceID: preview.workspaceID, previewSHA256: preview.previewSHA256,
            rows: preview.rows, warnings: preview.warnings, disposition: disposition,
            receiptSHA256: receipt?.receiptSHA256, evaluatedAt: evaluatedAt
        ))
        try validate()
    }

    static func pending(preview: RebasePreviewV1, evaluatedAt: Date) throws -> Self {
        try .init(preview: preview, receipt: nil, evaluatedAt: evaluatedAt)
    }

    static func resolved(preview: RebasePreviewV1, receipt: RebaseReceiptV1,
                         evaluatedAt: Date) throws -> Self {
        try .init(preview: preview, receipt: receipt, evaluatedAt: evaluatedAt)
    }

    func validate() throws {
        try preview.validate(); try receipt?.validate(preview: preview)
        try PlanOfflineWorkLimitsV1.instant(evaluatedAt)
        guard rows == preview.rows, warnings == preview.warnings,
              (disposition == .pending) == (receipt == nil),
              disposition != .approvedActivated || receipt?.decision == .approved,
              disposition != .rejected || receipt?.decision == .rejected,
              stateSHA256 == (try PlanCanonicalCodecV1.sha256(basis)) else {
            throw PlanOfflineWorkFailureV1.reviewReceiptMismatch
        }
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, persistenceMode: persistenceMode, workspaceID: workspaceID, previewSHA256: preview.previewSHA256, rows: rows, warnings: warnings, disposition: disposition, receiptSHA256: receipt?.receiptSHA256, evaluatedAt: evaluatedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let persistenceMode: String; let workspaceID: WorkspaceID; let previewSHA256: String; let rows: [PlanRebaseRowV1]; let warnings: [PlanRebaseWarningV1]; let disposition: RebaseReviewDispositionV1; let receiptSHA256: String?; let evaluatedAt: Date }
}
