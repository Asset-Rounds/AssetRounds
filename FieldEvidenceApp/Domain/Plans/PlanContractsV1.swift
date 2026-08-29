import Foundation

// Declaration owner: PlanRebaseCoordinatorV1 is the sole application-level
// assembler/writer bridge for this contract family; components remain pure.

enum PlanContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidDigest
    case wrongWorkspace
    case wrongRevision
    case invalidSuccessor
    case stalePreview
    case registryViolation
    case componentConflict
    case reviewRequired
    case limitExceeded
}

enum PlanLimitsV1 {
    static let normalizedScale: Int64 = 1_000_000
    static let transformScale: Int64 = 1_000_000_000
    static let maximumPages = 512
    static let maximumPlacements = 20_000
    static let maximumComponents = 32
    static let maximumWarnings = 2_048
    static let maximumComponentRows = 20_000
    static let maximumTextBytes = 512

    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func id(_ value: UUID) throws {
        guard value != zeroUUID else { throw PlanContractFailureV1.invalidValue }
    }

    static func revision(_ value: UInt64) throws {
        guard value > 0 else { throw PlanContractFailureV1.wrongRevision }
    }

    static func digest(_ value: String) throws {
        guard KernelCanonicalHashV1.validSHA256(value) else { throw PlanContractFailureV1.invalidDigest }
    }

    static func token(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= maximumTextBytes,
              value == value.precomposedStringWithCanonicalMapping,
              value.unicodeScalars.allSatisfy({ scalar in
                  let raw = scalar.value
                  return raw >= 0x20 && raw != 0x7f && !(0x202a...0x202e).contains(raw)
                      && !(0x2066...0x2069).contains(raw)
              }) else { throw PlanContractFailureV1.invalidValue }
    }

    static func instant(_ value: Date) throws {
        guard value.timeIntervalSinceReferenceDate.isFinite else { throw PlanContractFailureV1.invalidValue }
    }
}

enum PlanCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try WorkspaceMutationCanonicalV1.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try WorkspaceMutationCanonicalV1.decode(type, from: data)
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(value)
    }
}

enum PlanDocumentStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case active = "ACTIVE"
    case retired = "RETIRED"
}

enum PlanRevisionStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case draft = "DRAFT"
    case released = "RELEASED"
    case withdrawn = "WITHDRAWN"
}

enum PlanLifecycleOwnershipV1 {
    static let durableFamilies = ["PlanDocumentV1", "PlanRevisionV1", "PlanPlacementV1", "RebaseReceiptV1"]
    static let spatialReferenceFramePersistence = "EMBEDDED_IMMUTABLE_IN_PLAN_REVISION"
    static let rebasePreviewPersistence = "DERIVED_NONPERSISTENT"
    static let writer = "SOLE_CANONICAL_WORKSPACE_WRITER"
}

enum PlanPageRotationV1: Int, Codable, CaseIterable, Hashable, Sendable {
    case degrees0 = 0
    case degrees90 = 90
    case degrees180 = 180
    case degrees270 = 270
}

enum PlanPlacementSubjectKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case asset = "ASSET"
    case observation = "OBSERVATION"
    case location = "LOCATION"
}

enum PlanPlacementDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case accepted = "ACCEPTED"
    case reviewRequired = "REVIEW_REQUIRED"
    case orphaned = "ORPHANED"
    case outOfBounds = "OUT_OF_BOUNDS"
}

enum PlanRebaseDecisionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case approved = "APPROVED"
    case rejected = "REJECTED"
}

enum PlanRebaseWarningCodeV1: String, Codable, CaseIterable, Hashable, Sendable {
    case pageMissing = "PAGE_MISSING"
    case pageReordered = "PAGE_REORDERED"
    case outOfBounds = "OUT_OF_BOUNDS"
    case orphanedAnchor = "ORPHANED_ANCHOR"
    case residualExceeded = "RESIDUAL_EXCEEDED"
    case calibrationUnavailable = "CALIBRATION_UNAVAILABLE"
    case componentReviewRequired = "COMPONENT_REVIEW_REQUIRED"
}

struct NormalizedPlanCoordinateV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let millionths: Int64

    init(millionths: Int64) throws {
        guard (0...PlanLimitsV1.normalizedScale).contains(millionths) else {
            throw PlanContractFailureV1.invalidValue
        }
        self.millionths = millionths
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.millionths < rhs.millionths }

    private enum CodingKeys: String, CodingKey { case millionths }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(millionths: container.decode(Int64.self, forKey: .millionths))
    }
}

struct PlanCropRectV1: Codable, Equatable, Hashable, Sendable {
    let minX: NormalizedPlanCoordinateV1
    let minY: NormalizedPlanCoordinateV1
    let maxX: NormalizedPlanCoordinateV1
    let maxY: NormalizedPlanCoordinateV1

    init(minX: NormalizedPlanCoordinateV1, minY: NormalizedPlanCoordinateV1,
         maxX: NormalizedPlanCoordinateV1, maxY: NormalizedPlanCoordinateV1) throws {
        guard minX < maxX, minY < maxY else { throw PlanContractFailureV1.invalidValue }
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }
}

struct PlanPageReferenceV1: Codable, Equatable, Hashable, Sendable {
    let pageID: UUID
    let sourcePageOrdinal: Int
    let presentedPageOrdinal: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let crop: PlanCropRectV1
    let rotation: PlanPageRotationV1
    let sourcePageSHA256: String

    init(pageID: UUID, sourcePageOrdinal: Int, presentedPageOrdinal: Int,
         pixelWidth: Int, pixelHeight: Int, crop: PlanCropRectV1,
         rotation: PlanPageRotationV1, sourcePageSHA256: String) throws {
        try PlanLimitsV1.id(pageID)
        try PlanLimitsV1.digest(sourcePageSHA256)
        guard sourcePageOrdinal >= 0, sourcePageOrdinal < PlanLimitsV1.maximumPages,
              presentedPageOrdinal >= 0, presentedPageOrdinal < PlanLimitsV1.maximumPages,
              pixelWidth > 0, pixelWidth <= Int(Int32.max),
              pixelHeight > 0, pixelHeight <= Int(Int32.max) else { throw PlanContractFailureV1.invalidValue }
        self.pageID = pageID
        self.sourcePageOrdinal = sourcePageOrdinal
        self.presentedPageOrdinal = presentedPageOrdinal
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.crop = crop
        self.rotation = rotation
        self.sourcePageSHA256 = sourcePageSHA256
    }

    func validate() throws {
        try PlanLimitsV1.id(pageID)
        try PlanLimitsV1.digest(sourcePageSHA256)
        guard sourcePageOrdinal >= 0, sourcePageOrdinal < PlanLimitsV1.maximumPages,
              presentedPageOrdinal >= 0, presentedPageOrdinal < PlanLimitsV1.maximumPages,
              pixelWidth > 0, pixelWidth <= Int(Int32.max),
              pixelHeight > 0, pixelHeight <= Int(Int32.max),
              crop.minX < crop.maxX, crop.minY < crop.maxY else {
            throw PlanContractFailureV1.invalidValue
        }
    }
}

struct PlanContentBindingV1: Codable, Equatable, Hashable, Sendable {
    let contentID: String
    let byteLength: Int64
    let mediaType: String
    let contentSHA256: String
    let locatorID: String
    let locatorRevision: Int
    let fieldReferenceReleaseID: UUID
    let fieldReferenceReleaseRevision: UInt64
    let fieldReferenceReleaseSHA256: String
    let fieldReferenceManifestSHA256: String

    init(content: ContentReferenceV1, locator: ContentLocatorV1,
         fieldReferenceRelease: FieldReferenceReleaseV1) throws {
        try fieldReferenceRelease.validate()
        try locator.validate(against: content)
        guard let entry = fieldReferenceRelease.manifest.entries.first(where: { $0.contentID == content.contentID }) else {
            throw PlanContractFailureV1.invalidValue
        }
        guard content.workspaceID == fieldReferenceRelease.workspaceID.rawValue.uuidString.lowercased(),
              content.byteRole == .immutableOriginal,
              locator.workspaceID == content.workspaceID,
              entry.expectedByteLength == content.byteLength,
              entry.mediaType == content.mediaType,
              entry.digest == locator.contentDigest,
              entry.expectedLocatorRevision == locator.locatorRevision,
              entry.requiredForOpen else {
            throw PlanContractFailureV1.wrongWorkspace
        }
        contentID = content.contentID
        byteLength = content.byteLength
        mediaType = content.mediaType
        guard let sha256 = content.digests.digest(for: .sha256) else {
            throw PlanContractFailureV1.invalidDigest
        }
        contentSHA256 = sha256.hexadecimalValue
        locatorID = locator.locatorID
        locatorRevision = locator.locatorRevision
        fieldReferenceReleaseID = fieldReferenceRelease.releaseID
        fieldReferenceReleaseRevision = fieldReferenceRelease.revision
        fieldReferenceReleaseSHA256 = fieldReferenceRelease.releaseSHA256
        fieldReferenceManifestSHA256 = fieldReferenceRelease.manifestSHA256
        try validate()
    }

    func validate() throws {
        try PlanLimitsV1.token(contentID)
        try PlanLimitsV1.token(mediaType)
        try PlanLimitsV1.digest(contentSHA256)
        try PlanLimitsV1.token(locatorID)
        try PlanLimitsV1.id(fieldReferenceReleaseID)
        try PlanLimitsV1.revision(fieldReferenceReleaseRevision)
        try PlanLimitsV1.digest(fieldReferenceReleaseSHA256)
        try PlanLimitsV1.digest(fieldReferenceManifestSHA256)
        guard byteLength > 0, locatorRevision >= 0 else { throw PlanContractFailureV1.invalidValue }
    }

    func validate(content: ContentReferenceV1, locator: ContentLocatorV1,
                  release: FieldReferenceReleaseV1) throws {
        try validate()
        try release.validate()
        guard self == (try Self(content: content, locator: locator, fieldReferenceRelease: release)) else {
            throw PlanContractFailureV1.stalePreview
        }
    }
}

struct PlanAssetLocatorBindingV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let locator: AssetLocatorReferenceV1
    let bindingReceiptID: UUID
    let bindingReceiptRevision: UInt64
    let bindingReceiptSHA256: String
    let assetID: UUID

    init(locator value: AssetLocatorV1, receipt: LocatorBindingReceiptV1) throws {
        try value.validate(); try receipt.validateIntrinsic()
        let reference = try value.reference
        guard value.workspaceID == receipt.workspaceID, receipt.after == reference,
              value.assetID != PlanLimitsV1.zeroUUID else { throw PlanContractFailureV1.stalePreview }
        workspaceID = value.workspaceID
        locator = reference
        bindingReceiptID = receipt.receiptID
        bindingReceiptRevision = receipt.revision
        bindingReceiptSHA256 = receipt.receiptSHA256
        assetID = value.assetID
        try validate(locator: value, receipt: receipt)
    }

    func validate() throws {
        try locator.validate()
        try PlanLimitsV1.id(bindingReceiptID)
        try PlanLimitsV1.revision(bindingReceiptRevision)
        try PlanLimitsV1.digest(bindingReceiptSHA256)
        try PlanLimitsV1.id(assetID)
    }

    func validate(locator value: AssetLocatorV1, receipt: LocatorBindingReceiptV1) throws {
        try validate(); try value.validate(); try receipt.validateIntrinsic()
        guard workspaceID == value.workspaceID, workspaceID == receipt.workspaceID,
              locator == (try value.reference), receipt.after == locator,
              bindingReceiptID == receipt.receiptID,
              bindingReceiptRevision == receipt.revision,
              bindingReceiptSHA256 == receipt.receiptSHA256,
              assetID == value.assetID else { throw PlanContractFailureV1.stalePreview }
    }
}

struct PlanPrerequisiteClosureV1: Sendable {
    let content: ContentReferenceV1
    let contentLocator: ContentLocatorV1
    let fieldReferenceRelease: FieldReferenceReleaseV1
    let assetLocators: [AssetLocatorV1]
    let locatorBindingReceipts: [LocatorBindingReceiptV1]

    func validate(revision: PlanRevisionV1, placements: [PlanPlacementV1]) throws {
        try revision.validateIntrinsic()
        try revision.contentBinding.validate(content: content, locator: contentLocator,
                                             release: fieldReferenceRelease)
        var locatorByReference: [AssetLocatorReferenceV1: AssetLocatorV1] = [:]
        for locator in assetLocators {
            try locator.validate()
            let reference = try locator.reference
            guard locator.workspaceID == revision.workspaceID,
                  locatorByReference.updateValue(locator, forKey: reference) == nil else {
                throw PlanContractFailureV1.stalePreview
            }
        }
        var receiptByID: [UUID: LocatorBindingReceiptV1] = [:]
        for receipt in locatorBindingReceipts {
            try receipt.validateIntrinsic()
            guard receipt.workspaceID == revision.workspaceID,
                  receiptByID.updateValue(receipt, forKey: receipt.receiptID) == nil else {
                throw PlanContractFailureV1.stalePreview
            }
        }
        for placement in placements {
            try placement.validate(planRevision: revision)
            if let binding = placement.assetLocatorBinding {
                guard let locator = locatorByReference[binding.locator],
                      let receipt = receiptByID[binding.bindingReceiptID] else {
                    throw PlanContractFailureV1.stalePreview
                }
                try binding.validate(locator: locator, receipt: receipt)
            }
        }
        let requiredReferences = Set(placements.compactMap(\.assetLocatorBinding?.locator))
        let requiredReceiptIDs = Set(placements.compactMap(\.assetLocatorBinding?.bindingReceiptID))
        guard requiredReferences == Set(locatorByReference.keys),
              requiredReceiptIDs == Set(receiptByID.keys) else {
            throw PlanContractFailureV1.stalePreview
        }
    }
}

struct PlanDocumentReferenceV1: Codable, Equatable, Hashable, Sendable {
    let planDocumentID: UUID
    let revision: UInt64
    let documentSHA256: String

    func validate() throws {
        try PlanLimitsV1.id(planDocumentID)
        try PlanLimitsV1.revision(revision)
        try PlanLimitsV1.digest(documentSHA256)
    }
}

struct PlanDocumentV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let planDocumentID: UUID
    let workspaceID: WorkspaceID
    let stablePlanKey: String
    let displayName: String
    let state: PlanDocumentStateV1
    let supersedesDocumentSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedAt: Date
    let documentSHA256: String

    init(planDocumentID: UUID, workspaceID: WorkspaceID, stablePlanKey: String,
         displayName: String, state: PlanDocumentStateV1 = .active,
         supersedesDocumentSHA256: String? = nil, revision: UInt64,
         mutationID: MutationIDV1, recordedAt: Date) throws {
        schemaVersion = Self.schemaVersion
        self.planDocumentID = planDocumentID
        self.workspaceID = workspaceID
        self.stablePlanKey = stablePlanKey
        self.displayName = displayName
        self.state = state
        self.supersedesDocumentSHA256 = supersedesDocumentSHA256
        self.revision = revision
        self.mutationID = mutationID
        self.recordedAt = recordedAt
        documentSHA256 = try PlanCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, planDocumentID: planDocumentID,
            workspaceID: workspaceID, stablePlanKey: stablePlanKey, displayName: displayName,
            state: state, supersedesDocumentSHA256: supersedesDocumentSHA256,
            revision: revision, mutationID: mutationID, recordedAt: recordedAt
        ))
        try validateIntrinsic()
    }

    var reference: PlanDocumentReferenceV1 {
        get throws {
            let value = PlanDocumentReferenceV1(planDocumentID: planDocumentID, revision: revision,
                                                documentSHA256: documentSHA256)
            try value.validate()
            return value
        }
    }

    func validateIntrinsic() throws {
        try PlanLimitsV1.id(planDocumentID)
        try PlanLimitsV1.token(stablePlanKey)
        try PlanLimitsV1.token(displayName)
        try PlanLimitsV1.revision(revision)
        try PlanLimitsV1.instant(recordedAt)
        try supersedesDocumentSHA256.map(PlanLimitsV1.digest)
        guard (revision == 1) == (supersedesDocumentSHA256 == nil),
              documentSHA256 == (try PlanCanonicalCodecV1.sha256(basis)) else {
            throw PlanContractFailureV1.invalidDigest
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try predecessor.validateIntrinsic()
        try validateIntrinsic()
        guard predecessor.revision < UInt64.max,
              planDocumentID == predecessor.planDocumentID,
              workspaceID == predecessor.workspaceID,
              stablePlanKey == predecessor.stablePlanKey,
              revision == predecessor.revision + 1,
              supersedesDocumentSHA256 == predecessor.documentSHA256,
              predecessor.state == .active,
              mutationID != predecessor.mutationID else { throw PlanContractFailureV1.invalidSuccessor }
    }

    func rebound(to workspaceID: WorkspaceID, predecessor: Self?) throws -> Self {
        try .init(planDocumentID: planDocumentID, workspaceID: workspaceID,
                  stablePlanKey: stablePlanKey, displayName: displayName, state: state,
                  supersedesDocumentSHA256: predecessor?.documentSHA256, revision: revision,
                  mutationID: mutationID, recordedAt: recordedAt)
    }

    private var basis: Basis {
        .init(schemaVersion: schemaVersion, planDocumentID: planDocumentID, workspaceID: workspaceID,
              stablePlanKey: stablePlanKey, displayName: displayName, state: state,
              supersedesDocumentSHA256: supersedesDocumentSHA256, revision: revision,
              mutationID: mutationID, recordedAt: recordedAt)
    }
    private struct Basis: Codable {
        let schemaVersion: Int; let planDocumentID: UUID; let workspaceID: WorkspaceID
        let stablePlanKey: String; let displayName: String; let state: PlanDocumentStateV1
        let supersedesDocumentSHA256: String?; let revision: UInt64
        let mutationID: MutationIDV1; let recordedAt: Date
    }
}

struct SpatialReferenceFrameV1: Codable, Equatable, Hashable, Sendable {
    static let coordinateConvention = "NORMALIZED_PAGE_X_RIGHT_Y_DOWN_V1"
    let frameID: UUID
    let pageID: UUID
    let coordinateConvention: String
    let calibrationMicrometresPerNormalizedUnit: Int64?
    let calibrationProvenanceSHA256: String?
    let frameSHA256: String

    init(frameID: UUID, pageID: UUID,
         calibrationMicrometresPerNormalizedUnit: Int64? = nil,
         calibrationProvenanceSHA256: String? = nil) throws {
        self.frameID = frameID
        self.pageID = pageID
        coordinateConvention = Self.coordinateConvention
        self.calibrationMicrometresPerNormalizedUnit = calibrationMicrometresPerNormalizedUnit
        self.calibrationProvenanceSHA256 = calibrationProvenanceSHA256
        frameSHA256 = try PlanCanonicalCodecV1.sha256(Basis(
            frameID: frameID, pageID: pageID, coordinateConvention: Self.coordinateConvention,
            calibrationMicrometresPerNormalizedUnit: calibrationMicrometresPerNormalizedUnit,
            calibrationProvenanceSHA256: calibrationProvenanceSHA256
        ))
        try validate()
    }

    func validate() throws {
        try PlanLimitsV1.id(frameID)
        try PlanLimitsV1.id(pageID)
        try calibrationProvenanceSHA256.map(PlanLimitsV1.digest)
        guard coordinateConvention == Self.coordinateConvention,
              (calibrationMicrometresPerNormalizedUnit == nil) == (calibrationProvenanceSHA256 == nil),
              calibrationMicrometresPerNormalizedUnit.map({ $0 > 0 }) ?? true,
              frameSHA256 == (try PlanCanonicalCodecV1.sha256(basis)) else {
            throw PlanContractFailureV1.invalidDigest
        }
    }

    private var basis: Basis {
        .init(frameID: frameID, pageID: pageID, coordinateConvention: coordinateConvention,
              calibrationMicrometresPerNormalizedUnit: calibrationMicrometresPerNormalizedUnit,
              calibrationProvenanceSHA256: calibrationProvenanceSHA256)
    }
    private struct Basis: Codable {
        let frameID: UUID; let pageID: UUID; let coordinateConvention: String
        let calibrationMicrometresPerNormalizedUnit: Int64?
        let calibrationProvenanceSHA256: String?
    }
}

struct PlanRevisionReferenceV1: Codable, Equatable, Hashable, Sendable {
    let planRevisionID: UUID
    let planDocumentID: UUID
    let revision: UInt64
    let revisionSHA256: String
    func validate() throws {
        try PlanLimitsV1.id(planRevisionID); try PlanLimitsV1.id(planDocumentID)
        try PlanLimitsV1.revision(revision); try PlanLimitsV1.digest(revisionSHA256)
    }
}

struct PlanRevisionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let planRevisionID: UUID
    let workspaceID: WorkspaceID
    let planDocument: PlanDocumentReferenceV1
    let contentBinding: PlanContentBindingV1
    let pages: [PlanPageReferenceV1]
    let spatialFrames: [SpatialReferenceFrameV1]
    let state: PlanRevisionStateV1
    let supersedesPlanRevisionID: UUID?
    let supersedesRevisionSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedBy: ActorSnapshotV1
    let recordedAt: Date
    let revisionSHA256: String

    init(planRevisionID: UUID, workspaceID: WorkspaceID, planDocument: PlanDocumentReferenceV1,
         contentBinding: PlanContentBindingV1, pages: [PlanPageReferenceV1],
         spatialFrames: [SpatialReferenceFrameV1], state: PlanRevisionStateV1,
         predecessor: Self? = nil, revision: UInt64, mutationID: MutationIDV1,
         recordedBy: ActorSnapshotV1, recordedAt: Date) throws {
        schemaVersion = Self.schemaVersion
        self.planRevisionID = planRevisionID
        self.workspaceID = workspaceID
        self.planDocument = planDocument
        self.contentBinding = contentBinding
        self.pages = pages.sorted { ($0.presentedPageOrdinal, $0.pageID.uuidString) < ($1.presentedPageOrdinal, $1.pageID.uuidString) }
        self.spatialFrames = spatialFrames.sorted { $0.frameID.uuidString < $1.frameID.uuidString }
        self.state = state
        supersedesPlanRevisionID = predecessor?.planRevisionID
        supersedesRevisionSHA256 = predecessor?.revisionSHA256
        self.revision = revision
        self.mutationID = mutationID
        self.recordedBy = recordedBy
        self.recordedAt = recordedAt
        revisionSHA256 = try PlanCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, planRevisionID: planRevisionID, workspaceID: workspaceID,
            planDocument: planDocument, contentBinding: contentBinding, pages: self.pages,
            spatialFrames: self.spatialFrames, state: state,
            supersedesPlanRevisionID: predecessor?.planRevisionID,
            supersedesRevisionSHA256: predecessor?.revisionSHA256, revision: revision,
            mutationID: mutationID, recordedBy: recordedBy, recordedAt: recordedAt
        ))
        try validateIntrinsic()
    }

    var reference: PlanRevisionReferenceV1 {
        get throws {
            let value = PlanRevisionReferenceV1(planRevisionID: planRevisionID,
                                                planDocumentID: planDocument.planDocumentID,
                                                revision: revision, revisionSHA256: revisionSHA256)
            try value.validate(); return value
        }
    }

    func validateIntrinsic() throws {
        try PlanLimitsV1.id(planRevisionID); try planDocument.validate(); try contentBinding.validate()
        try PlanLimitsV1.revision(revision); try PlanLimitsV1.instant(recordedAt); try recordedBy.validate()
        try pages.forEach { try $0.validate() }
        try spatialFrames.forEach { try $0.validate() }
        let pageIDs = pages.map(\.pageID)
        guard !pages.isEmpty, pages.count <= PlanLimitsV1.maximumPages,
              Set(pageIDs).count == pageIDs.count,
              Set(pages.map(\.presentedPageOrdinal)).count == pages.count,
              pages == pages.sorted(by: { ($0.presentedPageOrdinal, $0.pageID.uuidString) < ($1.presentedPageOrdinal, $1.pageID.uuidString) }),
              spatialFrames.count == pages.count,
              Set(spatialFrames.map(\.pageID)) == Set(pageIDs),
              Set(spatialFrames.map(\.frameID)).count == spatialFrames.count,
              recordedBy.workspaceID == workspaceID,
              recordedBy.responsibility == .recordedBy,
              (revision == 1) == (supersedesPlanRevisionID == nil && supersedesRevisionSHA256 == nil),
              revisionSHA256 == (try PlanCanonicalCodecV1.sha256(basis)) else {
            throw PlanContractFailureV1.invalidDigest
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try predecessor.validateIntrinsic(); try validateIntrinsic()
        guard predecessor.revision < UInt64.max,
              planRevisionID != predecessor.planRevisionID,
              workspaceID == predecessor.workspaceID,
              planDocument.planDocumentID == predecessor.planDocument.planDocumentID,
              supersedesPlanRevisionID == predecessor.planRevisionID,
              supersedesRevisionSHA256 == predecessor.revisionSHA256,
              revision == predecessor.revision + 1,
              mutationID != predecessor.mutationID else { throw PlanContractFailureV1.invalidSuccessor }
    }

    func rebound(to workspaceID: WorkspaceID, planDocument: PlanDocumentReferenceV1,
                 contentBinding: PlanContentBindingV1, predecessor: Self?,
                 recordedBy: ActorSnapshotV1) throws -> Self {
        try .init(planRevisionID: planRevisionID, workspaceID: workspaceID,
                  planDocument: planDocument, contentBinding: contentBinding, pages: pages,
                  spatialFrames: spatialFrames, state: state, predecessor: predecessor,
                  revision: revision, mutationID: mutationID, recordedBy: recordedBy, recordedAt: recordedAt)
    }

    private var basis: Basis {
        .init(schemaVersion: schemaVersion, planRevisionID: planRevisionID, workspaceID: workspaceID,
              planDocument: planDocument, contentBinding: contentBinding, pages: pages,
              spatialFrames: spatialFrames, state: state,
              supersedesPlanRevisionID: supersedesPlanRevisionID,
              supersedesRevisionSHA256: supersedesRevisionSHA256, revision: revision,
              mutationID: mutationID, recordedBy: recordedBy, recordedAt: recordedAt)
    }
    private struct Basis: Codable {
        let schemaVersion: Int; let planRevisionID: UUID; let workspaceID: WorkspaceID
        let planDocument: PlanDocumentReferenceV1; let contentBinding: PlanContentBindingV1
        let pages: [PlanPageReferenceV1]; let spatialFrames: [SpatialReferenceFrameV1]
        let state: PlanRevisionStateV1; let supersedesPlanRevisionID: UUID?
        let supersedesRevisionSHA256: String?; let revision: UInt64
        let mutationID: MutationIDV1; let recordedBy: ActorSnapshotV1; let recordedAt: Date
    }
}

struct PlanPlacementReferenceV1: Codable, Equatable, Hashable, Sendable {
    let placementID: UUID; let revision: UInt64; let placementSHA256: String
    func validate() throws { try PlanLimitsV1.id(placementID); try PlanLimitsV1.revision(revision); try PlanLimitsV1.digest(placementSHA256) }
}

struct PlanPlacementV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let placementID: UUID
    let workspaceID: WorkspaceID
    let subjectKind: PlanPlacementSubjectKindV1
    let subjectID: UUID
    let planRevision: PlanRevisionReferenceV1
    let spatialFrameID: UUID
    let x: NormalizedPlanCoordinateV1
    let y: NormalizedPlanCoordinateV1
    let assetLocatorBinding: PlanAssetLocatorBindingV1?
    let disposition: PlanPlacementDispositionV1
    let supersedesPlacementSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let recordedAt: Date
    let placementSHA256: String

    init(placementID: UUID, workspaceID: WorkspaceID, subjectKind: PlanPlacementSubjectKindV1,
         subjectID: UUID, planRevision: PlanRevisionReferenceV1, spatialFrameID: UUID,
         x: NormalizedPlanCoordinateV1, y: NormalizedPlanCoordinateV1,
         assetLocatorBinding: PlanAssetLocatorBindingV1? = nil,
         disposition: PlanPlacementDispositionV1 = .accepted,
         predecessor: Self? = nil, revision: UInt64, mutationID: MutationIDV1,
         recordedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.placementID = placementID; self.workspaceID = workspaceID
        self.subjectKind = subjectKind; self.subjectID = subjectID; self.planRevision = planRevision
        self.spatialFrameID = spatialFrameID; self.x = x; self.y = y
        self.assetLocatorBinding = assetLocatorBinding; self.disposition = disposition
        supersedesPlacementSHA256 = predecessor?.placementSHA256; self.revision = revision
        self.mutationID = mutationID; self.recordedAt = recordedAt
        placementSHA256 = try PlanCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, placementID: placementID, workspaceID: workspaceID,
            subjectKind: subjectKind, subjectID: subjectID, planRevision: planRevision,
            spatialFrameID: spatialFrameID, x: x, y: y, assetLocatorBinding: assetLocatorBinding,
            disposition: disposition, supersedesPlacementSHA256: predecessor?.placementSHA256,
            revision: revision, mutationID: mutationID, recordedAt: recordedAt
        ))
        try validateIntrinsic()
    }

    func validateIntrinsic() throws {
        try PlanLimitsV1.id(placementID); try PlanLimitsV1.id(subjectID); try planRevision.validate()
        try PlanLimitsV1.id(spatialFrameID); try assetLocatorBinding?.validate()
        try PlanLimitsV1.revision(revision); try PlanLimitsV1.instant(recordedAt)
        guard (subjectKind == .asset) == (assetLocatorBinding != nil),
              assetLocatorBinding.map({ $0.assetID == subjectID }) ?? true,
              assetLocatorBinding.map({ $0.workspaceID == workspaceID }) ?? true,
              (revision == 1) == (supersedesPlacementSHA256 == nil),
              placementSHA256 == (try PlanCanonicalCodecV1.sha256(basis)) else {
            throw PlanContractFailureV1.invalidDigest
        }
    }

    /// Binds this placement to the exact immutable revision and proves that
    /// its spatial frame is one of that revision's embedded frame values.
    func validate(planRevision value: PlanRevisionV1) throws {
        try validateIntrinsic()
        try value.validateIntrinsic()
        guard workspaceID == value.workspaceID,
              planRevision == (try value.reference),
              value.spatialFrames.contains(where: { $0.frameID == spatialFrameID }) else {
            throw PlanContractFailureV1.stalePreview
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        try predecessor.validateIntrinsic(); try validateIntrinsic()
        guard predecessor.revision < UInt64.max, placementID == predecessor.placementID,
              workspaceID == predecessor.workspaceID, subjectKind == predecessor.subjectKind,
              subjectID == predecessor.subjectID, revision == predecessor.revision + 1,
              supersedesPlacementSHA256 == predecessor.placementSHA256,
              mutationID != predecessor.mutationID else { throw PlanContractFailureV1.invalidSuccessor }
    }

    func rebound(to workspaceID: WorkspaceID, planRevision: PlanRevisionReferenceV1,
                 assetLocatorBinding: PlanAssetLocatorBindingV1?, predecessor: Self?) throws -> Self {
        try .init(placementID: placementID, workspaceID: workspaceID, subjectKind: subjectKind,
                  subjectID: subjectID, planRevision: planRevision, spatialFrameID: spatialFrameID,
                  x: x, y: y, assetLocatorBinding: assetLocatorBinding, disposition: disposition,
                  predecessor: predecessor, revision: revision, mutationID: mutationID,
                  recordedAt: recordedAt)
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, placementID: placementID, workspaceID: workspaceID, subjectKind: subjectKind, subjectID: subjectID, planRevision: planRevision, spatialFrameID: spatialFrameID, x: x, y: y, assetLocatorBinding: assetLocatorBinding, disposition: disposition, supersedesPlacementSHA256: supersedesPlacementSHA256, revision: revision, mutationID: mutationID, recordedAt: recordedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let placementID: UUID; let workspaceID: WorkspaceID; let subjectKind: PlanPlacementSubjectKindV1; let subjectID: UUID; let planRevision: PlanRevisionReferenceV1; let spatialFrameID: UUID; let x, y: NormalizedPlanCoordinateV1; let assetLocatorBinding: PlanAssetLocatorBindingV1?; let disposition: PlanPlacementDispositionV1; let supersedesPlacementSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1; let recordedAt: Date }
}

struct PlanAffineTransformV1: Codable, Equatable, Hashable, Sendable {
    static let maximumCoefficientMagnitude: Int64 = 1_000_000_000_000
    let m11, m12, m21, m22, tx, ty: Int64
    let algorithmVersion: Int
    let transformSHA256: String

    init(m11: Int64, m12: Int64, m21: Int64, m22: Int64, tx: Int64, ty: Int64,
         algorithmVersion: Int = 1) throws {
        self.m11 = m11; self.m12 = m12; self.m21 = m21; self.m22 = m22
        self.tx = tx; self.ty = ty; self.algorithmVersion = algorithmVersion
        transformSHA256 = try PlanCanonicalCodecV1.sha256(Basis(m11: m11, m12: m12, m21: m21, m22: m22, tx: tx, ty: ty, algorithmVersion: algorithmVersion))
        try validate()
    }

    func validate() throws {
        let coefficients = [m11, m12, m21, m22, tx, ty]
        guard algorithmVersion == 1,
              coefficients.allSatisfy({ (-Self.maximumCoefficientMagnitude...Self.maximumCoefficientMagnitude).contains($0) }),
              transformSHA256 == (try PlanCanonicalCodecV1.sha256(basis)) else {
            throw PlanContractFailureV1.invalidDigest
        }
        let (p1, overflow1) = m11.multipliedReportingOverflow(by: m22)
        let (p2, overflow2) = m12.multipliedReportingOverflow(by: m21)
        let (determinant, overflow3) = p1.subtractingReportingOverflow(p2)
        guard !overflow1, !overflow2, !overflow3, determinant > 0 else {
            throw PlanContractFailureV1.invalidValue
        }
    }

    func applying(x: NormalizedPlanCoordinateV1, y: NormalizedPlanCoordinateV1) throws -> (Int64, Int64) {
        func axis(_ a: Int64, _ b: Int64, _ offset: Int64) throws -> Int64 {
            let (ax, o1) = a.multipliedReportingOverflow(by: x.millionths)
            let (by, o2) = b.multipliedReportingOverflow(by: y.millionths)
            let (sum, o3) = ax.addingReportingOverflow(by)
            let (scaledOffset, o4) = offset.multipliedReportingOverflow(by: PlanLimitsV1.transformScale)
            let (translated, o5) = sum.addingReportingOverflow(scaledOffset)
            guard !o1, !o2, !o3, !o4, !o5 else { throw PlanContractFailureV1.invalidValue }
            return translated / PlanLimitsV1.transformScale
        }
        return try (axis(m11, m12, tx), axis(m21, m22, ty))
    }


    func applyingNormalized(x: NormalizedPlanCoordinateV1,
                            y: NormalizedPlanCoordinateV1) throws
        -> (x: NormalizedPlanCoordinateV1?, y: NormalizedPlanCoordinateV1?,
            disposition: PlanPlacementDispositionV1) {
        let transformed = try applying(x: x, y: y)
        guard (0...PlanLimitsV1.normalizedScale).contains(transformed.0),
              (0...PlanLimitsV1.normalizedScale).contains(transformed.1) else {
            return (nil, nil, .outOfBounds)
        }
        return (try .init(millionths: transformed.0),
                try .init(millionths: transformed.1), .accepted)
    }

    private var basis: Basis { .init(m11: m11, m12: m12, m21: m21, m22: m22, tx: tx, ty: ty, algorithmVersion: algorithmVersion) }
    private struct Basis: Codable { let m11, m12, m21, m22, tx, ty: Int64; let algorithmVersion: Int }
}

struct PlanRebaseWarningV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let code: PlanRebaseWarningCodeV1
    let placementID: UUID?
    let componentID: String?
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.code.rawValue, lhs.placementID?.uuidString ?? "", lhs.componentID ?? "") <
        (rhs.code.rawValue, rhs.placementID?.uuidString ?? "", rhs.componentID ?? "")
    }

    func validate() throws {
        try placementID.map(PlanLimitsV1.id)
        try componentID.map(PlanLimitsV1.token)
    }
}

struct PlanRebaseRowV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let placementID: UUID
    let before: PlanPlacementReferenceV1
    let proposedAfter: PlanPlacementV1?
    let disposition: PlanPlacementDispositionV1
    let residualMillionths: UInt64?

    func validate() throws {
        try PlanLimitsV1.id(placementID); try before.validate(); try proposedAfter?.validateIntrinsic()
        let requiresPostImage = disposition != .orphaned
        guard before.placementID == placementID,
              (proposedAfter != nil) == requiresPostImage,
              proposedAfter.map({ $0.placementID == placementID && $0.disposition == disposition }) ?? true,
              residualMillionths.map({ $0 <= UInt64(PlanLimitsV1.normalizedScale) }) ?? true else {
            throw PlanContractFailureV1.invalidValue
        }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.placementID.uuidString < rhs.placementID.uuidString }
}

struct PlanRebaseComponentContextV1: Sendable {
    let workspaceID: WorkspaceID
    let oldRevision: PlanRevisionV1
    let newRevision: PlanRevisionV1
    let transform: PlanAffineTransformV1
    let placements: [PlanPlacementV1]
}

struct PlanRebaseComponentContributionV1: Codable, Equatable, Sendable {
    let componentID: String
    let componentVersion: Int
    let rows: [PlanRebaseRowV1]
    let warnings: [PlanRebaseWarningV1]
    let requiresReview: Bool
    let mutationIntentSHA256: String?
    let contributionSHA256: String

    init(componentID: String, componentVersion: Int, rows: [PlanRebaseRowV1],
         warnings: [PlanRebaseWarningV1], requiresReview: Bool,
         mutationIntentSHA256: String? = nil) throws {
        self.componentID = componentID; self.componentVersion = componentVersion
        self.rows = rows.sorted(); self.warnings = warnings.sorted()
        self.requiresReview = requiresReview; self.mutationIntentSHA256 = mutationIntentSHA256
        contributionSHA256 = try PlanCanonicalCodecV1.sha256(Basis(componentID: componentID,
            componentVersion: componentVersion, rows: self.rows, warnings: self.warnings,
            requiresReview: requiresReview, mutationIntentSHA256: mutationIntentSHA256))
        try validate()
    }

    func validate() throws {
        try PlanLimitsV1.token(componentID); try rows.forEach { try $0.validate() }
        try mutationIntentSHA256.map(PlanLimitsV1.digest)
        guard componentVersion > 0, rows.count <= PlanLimitsV1.maximumComponentRows,
              warnings.count <= PlanLimitsV1.maximumWarnings,
              Set(rows.map(\.placementID)).count == rows.count, rows == rows.sorted(),
              warnings == warnings.sorted(), Set(warnings).count == warnings.count,
              contributionSHA256 == (try PlanCanonicalCodecV1.sha256(basis)) else {
            throw PlanContractFailureV1.invalidDigest
        }
    }
    private var basis: Basis { .init(componentID: componentID, componentVersion: componentVersion, rows: rows, warnings: warnings, requiresReview: requiresReview, mutationIntentSHA256: mutationIntentSHA256) }
    private struct Basis: Codable { let componentID: String; let componentVersion: Int; let rows: [PlanRebaseRowV1]; let warnings: [PlanRebaseWarningV1]; let requiresReview: Bool; let mutationIntentSHA256: String? }
}

protocol PlanRebaseComponentV1: Sendable {
    var componentID: String { get }
    var componentVersion: Int { get }
    var stableSortOrdinal: Int { get }
    func evaluate(_ context: PlanRebaseComponentContextV1) throws -> PlanRebaseComponentContributionV1
}

struct PlanRebaseComponentDescriptorV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let componentID: String; let componentVersion: Int; let stableSortOrdinal: Int
    init(componentID: String, componentVersion: Int, stableSortOrdinal: Int) throws {
        try PlanLimitsV1.token(componentID)
        guard componentVersion > 0, stableSortOrdinal >= 0 else { throw PlanContractFailureV1.invalidValue }
        self.componentID = componentID; self.componentVersion = componentVersion; self.stableSortOrdinal = stableSortOrdinal
    }
    static func < (lhs: Self, rhs: Self) -> Bool { (lhs.stableSortOrdinal, lhs.componentID, lhs.componentVersion) < (rhs.stableSortOrdinal, rhs.componentID, rhs.componentVersion) }
}

struct PlanRebaseComponentRegistryV1: Sendable {
    let registryVersion: Int
    let descriptors: [PlanRebaseComponentDescriptorV1]
    let registrySHA256: String
    private let components: [any PlanRebaseComponentV1]

    init(registryVersion: Int = 1, components: [any PlanRebaseComponentV1]) throws {
        guard registryVersion > 0, !components.isEmpty, components.count <= PlanLimitsV1.maximumComponents else {
            throw PlanContractFailureV1.registryViolation
        }
        let pairs = try components.map { component in
            (try PlanRebaseComponentDescriptorV1(componentID: component.componentID,
                                                  componentVersion: component.componentVersion,
                                                  stableSortOrdinal: component.stableSortOrdinal), component)
        }.sorted { $0.0 < $1.0 }
        let values = pairs.map { $0.0 }
        guard Set(values.map(\.componentID)).count == values.count,
              Set(values.map(\.stableSortOrdinal)).count == values.count else {
            throw PlanContractFailureV1.registryViolation
        }
        self.registryVersion = registryVersion; descriptors = values
        self.components = pairs.map { $0.1 }
        registrySHA256 = try PlanCanonicalCodecV1.sha256(Basis(registryVersion: registryVersion, descriptors: values))
    }

    func evaluate(_ context: PlanRebaseComponentContextV1) throws -> [PlanRebaseComponentContributionV1] {
        var values: [PlanRebaseComponentContributionV1] = []
        for (descriptor, component) in zip(descriptors, components) {
            let contribution = try component.evaluate(context)
            try contribution.validate()
            guard contribution.componentID == descriptor.componentID,
                  contribution.componentVersion == descriptor.componentVersion else {
                throw PlanContractFailureV1.registryViolation
            }
            values.append(contribution)
        }
        return values
    }


    func validate(preview: RebasePreviewV1) throws {
        try preview.validate()
        guard preview.registryVersion == registryVersion,
              preview.registrySHA256 == registrySHA256,
              preview.componentDescriptors == descriptors,
              preview.contributions.count == descriptors.count,
              zip(preview.contributions, descriptors).allSatisfy({ pair in
                  pair.0.componentID == pair.1.componentID &&
                  pair.0.componentVersion == pair.1.componentVersion
              }) else { throw PlanContractFailureV1.registryViolation }
    }
    private struct Basis: Codable { let registryVersion: Int; let descriptors: [PlanRebaseComponentDescriptorV1] }
}

enum PlanRebasePreviewBuilderV1 {
    static func build(previewID: UUID, workspaceID: WorkspaceID,
                      oldRevision: PlanRevisionV1, newRevision: PlanRevisionV1,
                      transform: PlanAffineTransformV1, placements: [PlanPlacementV1],
                      registry: PlanRebaseComponentRegistryV1,
                      expectedRevision: UInt64, generatedAt: Date) throws -> RebasePreviewV1 {
        try oldRevision.validateIntrinsic(); try newRevision.validateIntrinsic(); try transform.validate()
        try placements.forEach { try $0.validate(planRevision: oldRevision) }
        guard oldRevision.workspaceID == workspaceID, newRevision.workspaceID == workspaceID,
              placements.allSatisfy({ $0.workspaceID == workspaceID }),
              placements.allSatisfy({ $0.planRevision.planRevisionID == oldRevision.planRevisionID &&
                                      $0.planRevision.revision == oldRevision.revision &&
                                      $0.planRevision.revisionSHA256 == oldRevision.revisionSHA256 }),
              Set(placements.map(\.placementID)).count == placements.count,
              newRevision.supersedesPlanRevisionID == oldRevision.planRevisionID,
              newRevision.supersedesRevisionSHA256 == oldRevision.revisionSHA256,
              oldRevision.state == .released, newRevision.state == .released else {
            throw PlanContractFailureV1.stalePreview
        }
        let context = PlanRebaseComponentContextV1(workspaceID: workspaceID,
                                                   oldRevision: oldRevision,
                                                   newRevision: newRevision,
                                                   transform: transform,
                                                   placements: placements.sorted { $0.placementID.uuidString < $1.placementID.uuidString })
        let contributions = try registry.evaluate(context)
        for contribution in contributions {
            for row in contribution.rows { try row.proposedAfter?.validate(planRevision: newRevision) }
        }
        let preview = try RebasePreviewV1(previewID: previewID, workspaceID: workspaceID,
                                   oldRevision: oldRevision.reference, newRevision: newRevision.reference,
                                   transform: transform, registrySHA256: registry.registrySHA256,
                                   registryVersion: registry.registryVersion,
                                   componentDescriptors: registry.descriptors,
                                   contributions: contributions, expectedRevision: expectedRevision,
                                   generatedAt: generatedAt)
        try registry.validate(preview: preview)
        return preview
    }

    static func placementSetSHA256(_ placements: [PlanPlacementV1]) throws -> String {
        try placements.forEach { try $0.validateIntrinsic() }
        let ordered = placements.sorted { $0.placementID.uuidString < $1.placementID.uuidString }
        guard Set(ordered.map(\.placementID)).count == ordered.count else {
            throw PlanContractFailureV1.componentConflict
        }
        return try PlanCanonicalCodecV1.sha256(ordered)
    }
}

struct RebasePreviewV1: Codable, Equatable, Sendable {
    let previewID: UUID
    let workspaceID: WorkspaceID
    let oldRevision: PlanRevisionReferenceV1
    let newRevision: PlanRevisionReferenceV1
    let transform: PlanAffineTransformV1
    let registryVersion: Int
    let componentDescriptors: [PlanRebaseComponentDescriptorV1]
    let registrySHA256: String
    let contributions: [PlanRebaseComponentContributionV1]
    let rows: [PlanRebaseRowV1]
    let warnings: [PlanRebaseWarningV1]
    let requiresReview: Bool
    let expectedRevision: UInt64
    let generatedAt: Date
    let previewSHA256: String

    init(previewID: UUID, workspaceID: WorkspaceID, oldRevision: PlanRevisionReferenceV1,
         newRevision: PlanRevisionReferenceV1, transform: PlanAffineTransformV1,
         registrySHA256: String, registryVersion: Int,
         componentDescriptors: [PlanRebaseComponentDescriptorV1],
         contributions: [PlanRebaseComponentContributionV1],
         expectedRevision: UInt64, generatedAt: Date) throws {
        self.previewID = previewID; self.workspaceID = workspaceID; self.oldRevision = oldRevision
        self.newRevision = newRevision; self.transform = transform
        self.registryVersion = registryVersion; self.componentDescriptors = componentDescriptors
        self.registrySHA256 = registrySHA256
        self.contributions = contributions
        let allRows = contributions.flatMap(\.rows)
        var rowsByID: [UUID: PlanRebaseRowV1] = [:]
        for row in allRows {
            if let existing = rowsByID[row.placementID], existing != row { throw PlanContractFailureV1.componentConflict }
            rowsByID[row.placementID] = row
        }
        rows = rowsByID.values.sorted()
        warnings = Array(Set(contributions.flatMap(\.warnings))).sorted()
        requiresReview = contributions.contains(where: \.requiresReview) || rows.contains(where: { $0.disposition != .accepted })
        self.expectedRevision = expectedRevision; self.generatedAt = generatedAt
        previewSHA256 = try PlanCanonicalCodecV1.sha256(Basis(previewID: previewID, workspaceID: workspaceID,
            oldRevision: oldRevision, newRevision: newRevision, transform: transform,
            registryVersion: registryVersion, componentDescriptors: componentDescriptors,
            registrySHA256: registrySHA256, contributions: contributions, rows: rows,
            warnings: warnings, requiresReview: requiresReview,
            expectedRevision: expectedRevision, generatedAt: generatedAt))
        try validate()
    }

    func validate() throws {
        try PlanLimitsV1.id(previewID); try oldRevision.validate(); try newRevision.validate()
        try transform.validate(); try PlanLimitsV1.digest(registrySHA256)
        try contributions.forEach { try $0.validate() }; try rows.forEach { try $0.validate() }
        try warnings.forEach { try $0.validate() }
        try PlanLimitsV1.instant(generatedAt)
        let expectedRegistrySHA = try PlanCanonicalCodecV1.sha256(
            RegistryBasis(registryVersion: registryVersion, descriptors: componentDescriptors)
        )
        var aggregateRows: [UUID: PlanRebaseRowV1] = [:]
        for row in contributions.flatMap(\.rows) {
            if let old = aggregateRows.updateValue(row, forKey: row.placementID), old != row {
                throw PlanContractFailureV1.componentConflict
            }
        }
        let aggregateWarnings = Array(Set(contributions.flatMap(\.warnings))).sorted()
        let aggregateReview = contributions.contains(where: \.requiresReview) ||
            aggregateRows.values.contains(where: { $0.disposition != .accepted })
        guard registryVersion > 0, expectedRevision == oldRevision.revision,
              oldRevision != newRevision, registrySHA256 == expectedRegistrySHA,
              componentDescriptors == componentDescriptors.sorted(),
              Set(componentDescriptors.map(\.componentID)).count == componentDescriptors.count,
              Set(componentDescriptors.map(\.stableSortOrdinal)).count == componentDescriptors.count,
              contributions.count == componentDescriptors.count,
              zip(contributions, componentDescriptors).allSatisfy({ pair in
                  pair.0.componentID == pair.1.componentID &&
                  pair.0.componentVersion == pair.1.componentVersion
              }),
              rows == aggregateRows.values.sorted(), warnings == aggregateWarnings,
              requiresReview == aggregateReview,
              contributions.count <= PlanLimitsV1.maximumComponents,
              Set(contributions.map(\.componentID)).count == contributions.count,
              rows.count <= PlanLimitsV1.maximumPlacements,
              warnings.count <= PlanLimitsV1.maximumWarnings,
              previewSHA256 == (try PlanCanonicalCodecV1.sha256(basis)) else {
            throw PlanContractFailureV1.invalidDigest
        }
    }
    private var basis: Basis { .init(previewID: previewID, workspaceID: workspaceID, oldRevision: oldRevision, newRevision: newRevision, transform: transform, registryVersion: registryVersion, componentDescriptors: componentDescriptors, registrySHA256: registrySHA256, contributions: contributions, rows: rows, warnings: warnings, requiresReview: requiresReview, expectedRevision: expectedRevision, generatedAt: generatedAt) }
    private struct Basis: Codable { let previewID: UUID; let workspaceID: WorkspaceID; let oldRevision, newRevision: PlanRevisionReferenceV1; let transform: PlanAffineTransformV1; let registryVersion: Int; let componentDescriptors: [PlanRebaseComponentDescriptorV1]; let registrySHA256: String; let contributions: [PlanRebaseComponentContributionV1]; let rows: [PlanRebaseRowV1]; let warnings: [PlanRebaseWarningV1]; let requiresReview: Bool; let expectedRevision: UInt64; let generatedAt: Date }
    private struct RegistryBasis: Codable { let registryVersion: Int; let descriptors: [PlanRebaseComponentDescriptorV1] }
}

/// Cycle-free canonical preimage for an approved atomic rebase mutation. The
/// durable receipt stores this value's digest; the generic writer receipt is
/// deliberately outside this preimage and is produced only after commit.
struct PlanRebaseCommandBasisV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let mutationID: MutationIDV1
    let previewID: UUID
    let previewSHA256: String
    let newRevision: PlanRevisionV1
    let predecessorRevision: PlanRevisionV1
    let placements: [PlanPlacementV1]
    let predecessorPlacements: [PlanPlacementV1]
    let receiptID: UUID
    let predecessorReceiptSHA256: String?
    let canonicalPoseEffectsSHA256: String?
    let reviewedBy: ActorSnapshotV1
    let recordedAt: Date

    init(workspaceID: WorkspaceID, mutationID: MutationIDV1, preview: RebasePreviewV1,
         newRevision: PlanRevisionV1, predecessorRevision: PlanRevisionV1,
         placements: [PlanPlacementV1], predecessorPlacements: [PlanPlacementV1],
         receiptID: UUID, predecessorReceipt: RebaseReceiptV1?,
         reviewedBy: ActorSnapshotV1, recordedAt: Date,
         poseEffects: PlacementPoseMutationV1? = nil) throws {
        self.workspaceID = workspaceID; self.mutationID = mutationID
        previewID = preview.previewID; previewSHA256 = preview.previewSHA256
        self.newRevision = newRevision; self.predecessorRevision = predecessorRevision
        self.placements = placements.sorted { $0.placementID.uuidString < $1.placementID.uuidString }
        self.predecessorPlacements = predecessorPlacements.sorted { $0.placementID.uuidString < $1.placementID.uuidString }
        self.receiptID = receiptID; predecessorReceiptSHA256 = predecessorReceipt?.receiptSHA256
        if let poseEffects { try poseEffects.validate() }
        canonicalPoseEffectsSHA256 = try poseEffects.map { try WorkspaceMutationCanonicalV1.sha256($0) }
        self.reviewedBy = reviewedBy; self.recordedAt = recordedAt
        try validate(preview: preview, predecessorReceipt: predecessorReceipt, poseEffects: poseEffects)
    }

    var canonicalSHA256: String { get throws { try PlanCanonicalCodecV1.sha256(self) } }

    func validate(preview: RebasePreviewV1, predecessorReceipt: RebaseReceiptV1?,
                  poseEffects: PlacementPoseMutationV1? = nil) throws {
        try preview.validate(); try newRevision.validateSuccessor(of: predecessorRevision)
        try placements.forEach { try $0.validateIntrinsic() }
        try predecessorPlacements.forEach { try $0.validateIntrinsic() }
        try predecessorReceipt?.validateIntrinsic(); try reviewedBy.validate()
        try PlanLimitsV1.id(receiptID); try PlanLimitsV1.instant(recordedAt)
        let expectedPoseSHA = try poseEffects.map { try WorkspaceMutationCanonicalV1.sha256($0) }
            ?? canonicalPoseEffectsSHA256
        let reviewedPoseIntent = preview.contributions.first {
            $0.componentID == "C37_POSE_FRAME_REBASE"
        }?.mutationIntentSHA256
        let priorByID = Dictionary(grouping: predecessorPlacements, by: \.placementID)
        guard workspaceID == preview.workspaceID, previewID == preview.previewID,
              previewSHA256 == preview.previewSHA256,
              preview.oldRevision == (try predecessorRevision.reference),
              preview.newRevision == (try newRevision.reference),
              newRevision.workspaceID == workspaceID, newRevision.mutationID == mutationID,
              placements.count == predecessorPlacements.count,
              Set(placements.map(\.placementID)) == Set(predecessorPlacements.map(\.placementID)),
              priorByID.values.allSatisfy({ $0.count == 1 }),
              reviewedBy.workspaceID == workspaceID, reviewedBy.responsibility == .reviewedBy,
              predecessorReceiptSHA256 == predecessorReceipt?.receiptSHA256,
              canonicalPoseEffectsSHA256 == expectedPoseSHA,
              reviewedPoseIntent == expectedPoseSHA else {
            throw PlanContractFailureV1.stalePreview
        }
        for placement in placements {
            guard let predecessor = priorByID[placement.placementID]?.first,
                  placement.workspaceID == workspaceID, placement.mutationID == mutationID,
                  placement.planRevision == (try newRevision.reference) else {
                throw PlanContractFailureV1.componentConflict
            }
            try placement.validateSuccessor(of: predecessor)
        }
        let previewRows = Dictionary(grouping: preview.rows, by: \.placementID)
        guard previewRows.values.allSatisfy({ $0.count == 1 }),
              placements.allSatisfy({ placement in previewRows[placement.placementID]?.first?.proposedAfter == placement }) else {
            throw PlanContractFailureV1.stalePreview
        }
    }
}

struct RebaseReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let receiptID: UUID
    let workspaceID: WorkspaceID
    let previewID: UUID
    let previewSHA256: String
    let decision: PlanRebaseDecisionV1
    let resultingRevision: PlanRevisionReferenceV1?
    let resultingPlacementsSHA256: String?
    /// Digest of the canonical PlanMutationV1 command/post-image basis. This
    /// is computable before the writer transaction and therefore introduces
    /// no cycle with the generic MutationReceiptV1 emitted after commit.
    let canonicalPlanMutationSHA256: String?
    let reviewedBy: ActorSnapshotV1
    let recordedAt: Date
    let supersedesReceiptSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let receiptSHA256: String

    init(receiptID: UUID, preview: RebasePreviewV1, decision: PlanRebaseDecisionV1,
         resultingRevision: PlanRevisionReferenceV1?, resultingPlacementsSHA256: String?,
         canonicalPlanMutationSHA256: String?, reviewedBy: ActorSnapshotV1,
         recordedAt: Date, predecessor: Self? = nil, revision: UInt64,
         mutationID: MutationIDV1) throws {
        schemaVersion = Self.schemaVersion; self.receiptID = receiptID; workspaceID = preview.workspaceID
        previewID = preview.previewID; previewSHA256 = preview.previewSHA256; self.decision = decision
        self.resultingRevision = resultingRevision; self.resultingPlacementsSHA256 = resultingPlacementsSHA256
        self.canonicalPlanMutationSHA256 = canonicalPlanMutationSHA256; self.reviewedBy = reviewedBy
        self.recordedAt = recordedAt; supersedesReceiptSHA256 = predecessor?.receiptSHA256
        self.revision = revision; self.mutationID = mutationID
        receiptSHA256 = try PlanCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            receiptID: receiptID, workspaceID: preview.workspaceID, previewID: preview.previewID,
            previewSHA256: preview.previewSHA256, decision: decision, resultingRevision: resultingRevision,
            resultingPlacementsSHA256: resultingPlacementsSHA256,
            canonicalPlanMutationSHA256: canonicalPlanMutationSHA256, reviewedBy: reviewedBy,
            recordedAt: recordedAt, supersedesReceiptSHA256: predecessor?.receiptSHA256,
            revision: revision, mutationID: mutationID))
        try validate(preview: preview)
    }

    func validateIntrinsic() throws {
        try PlanLimitsV1.id(receiptID); try PlanLimitsV1.id(previewID); try PlanLimitsV1.digest(previewSHA256)
        try resultingRevision?.validate(); try resultingPlacementsSHA256.map(PlanLimitsV1.digest)
        try canonicalPlanMutationSHA256.map(PlanLimitsV1.digest); try reviewedBy.validate()
        try PlanLimitsV1.instant(recordedAt); try supersedesReceiptSHA256.map(PlanLimitsV1.digest)
        let approved = decision == .approved
        guard schemaVersion == Self.schemaVersion, revision > 0,
              (revision == 1) == (supersedesReceiptSHA256 == nil),
              reviewedBy.workspaceID == workspaceID, reviewedBy.responsibility == .reviewedBy,
              approved == (resultingRevision != nil && resultingPlacementsSHA256 != nil && canonicalPlanMutationSHA256 != nil),
              !approved == (resultingRevision == nil && resultingPlacementsSHA256 == nil && canonicalPlanMutationSHA256 == nil),
              receiptSHA256 == (try PlanCanonicalCodecV1.sha256(basis)) else {
            throw PlanContractFailureV1.invalidDigest
        }
    }

    func validate(preview: RebasePreviewV1) throws {
        try validateIntrinsic(); try preview.validate()
        guard workspaceID == preview.workspaceID, previewID == preview.previewID,
              previewSHA256 == preview.previewSHA256,
              decision != .approved || resultingRevision == preview.newRevision else {
            throw PlanContractFailureV1.stalePreview
        }
    }

    func validate(preview: RebasePreviewV1, commandBasis: PlanRebaseCommandBasisV1,
                  predecessor: Self?) throws {
        try validate(preview: preview)
        try commandBasis.validate(preview: preview, predecessorReceipt: predecessor)
        guard receiptID == commandBasis.receiptID, workspaceID == commandBasis.workspaceID,
              mutationID == commandBasis.mutationID,
              reviewedBy == commandBasis.reviewedBy, recordedAt == commandBasis.recordedAt,
              supersedesReceiptSHA256 == predecessor?.receiptSHA256,
              resultingRevision == (try commandBasis.newRevision.reference),
              resultingPlacementsSHA256 == (try PlanRebasePreviewBuilderV1.placementSetSHA256(commandBasis.placements)),
              canonicalPlanMutationSHA256 == (try commandBasis.canonicalSHA256) else {
            throw PlanContractFailureV1.stalePreview
        }
    }

    func validateSuccessor(of predecessor: Self, preview: RebasePreviewV1) throws {
        try predecessor.validateIntrinsic(); try validate(preview: preview)
        guard predecessor.revision < UInt64.max, receiptID != predecessor.receiptID,
              workspaceID == predecessor.workspaceID, revision == predecessor.revision + 1,
              supersedesReceiptSHA256 == predecessor.receiptSHA256,
              mutationID != predecessor.mutationID else { throw PlanContractFailureV1.invalidSuccessor }
    }

    func rebound(to workspaceID: WorkspaceID, preview: RebasePreviewV1,
                 resultingRevision: PlanRevisionReferenceV1?,
                 resultingPlacementsSHA256: String?, canonicalPlanMutationSHA256: String?,
                 reviewedBy: ActorSnapshotV1, predecessor: Self?) throws -> Self {
        guard preview.workspaceID == workspaceID else { throw PlanContractFailureV1.wrongWorkspace }
        return try .init(receiptID: receiptID, preview: preview, decision: decision,
                         resultingRevision: resultingRevision,
                         resultingPlacementsSHA256: resultingPlacementsSHA256,
                         canonicalPlanMutationSHA256: canonicalPlanMutationSHA256,
                         reviewedBy: reviewedBy, recordedAt: recordedAt,
                         predecessor: predecessor, revision: revision, mutationID: mutationID)
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, receiptID: receiptID, workspaceID: workspaceID, previewID: previewID, previewSHA256: previewSHA256, decision: decision, resultingRevision: resultingRevision, resultingPlacementsSHA256: resultingPlacementsSHA256, canonicalPlanMutationSHA256: canonicalPlanMutationSHA256, reviewedBy: reviewedBy, recordedAt: recordedAt, supersedesReceiptSHA256: supersedesReceiptSHA256, revision: revision, mutationID: mutationID) }
    private struct Basis: Codable { let schemaVersion: Int; let receiptID: UUID; let workspaceID: WorkspaceID; let previewID: UUID; let previewSHA256: String; let decision: PlanRebaseDecisionV1; let resultingRevision: PlanRevisionReferenceV1?; let resultingPlacementsSHA256: String?; let canonicalPlanMutationSHA256: String?; let reviewedBy: ActorSnapshotV1; let recordedAt: Date; let supersedesReceiptSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1 }
}

struct PlanLifecycleClosureV1: Sendable {
    let documentHistory: [PlanDocumentV1]
    let revisionHistory: [PlanRevisionV1]
    let placementHistory: [PlanPlacementV1]
    let receipts: [RebaseReceiptV1]

    func validate() throws {
        guard documentHistory.count <= PlanLimitsV1.maximumPlacements,
              revisionHistory.count <= PlanLimitsV1.maximumPlacements,
              placementHistory.count <= PlanLimitsV1.maximumPlacements else {
            throw PlanContractFailureV1.limitExceeded
        }
        try Self.validateChains(documentHistory, id: \.planDocumentID, revision: \.revision) { try $1.validateSuccessor(of: $0) }
        try Self.validateChains(revisionHistory, id: { $0.planDocument.planDocumentID }, revision: \.revision) { try $1.validateSuccessor(of: $0) }
        try Self.validateChains(placementHistory, id: \.placementID, revision: \.revision) { try $1.validateSuccessor(of: $0) }
        try documentHistory.forEach { try $0.validateIntrinsic() }
        try revisionHistory.forEach { try $0.validateIntrinsic() }
        try placementHistory.forEach { try $0.validateIntrinsic() }
        try receipts.forEach { try $0.validateIntrinsic() }
        let revisions = Dictionary(grouping: revisionHistory, by: { try? $0.reference })
        guard revisions.values.allSatisfy({ $0.count == 1 }),
              placementHistory.allSatisfy({ revisions[$0.planRevision]?.count == 1 }) else {
            throw PlanContractFailureV1.invalidValue
        }
    }

    private static func validateChains<T>(_ values: [T], id: (T) -> UUID,
                                          revision: (T) -> UInt64,
                                          successor: (T, T) throws -> Void) throws {
        for group in Dictionary(grouping: values, by: id).values {
            let ordered = group.sorted { revision($0) < revision($1) }
            guard ordered.first.map({ revision($0) == 1 }) ?? true,
                  Set(ordered.map(revision)).count == ordered.count else {
                throw PlanContractFailureV1.invalidSuccessor
            }
            for index in ordered.indices.dropFirst() { try successor(ordered[index - 1], ordered[index]) }
        }
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Plans_PlanContractsV1_swift {
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
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_Plans_PlanContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Plans/PlanContractsV1.swift", role: .plan)
}

enum C31LightingPlanBoundaryV1 {
    static let measurementPlanReferenceIsFrozen = true
    static let criterionMetadataRequiresExplicitReleaseBinding = true
    static let rebaseDoesNotRewriteHistoricLightingDisplay = true
}
// MARK: - C32 assistance plan boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Plans_PlanContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalCannotMutatePlanWithoutAcceptance = true

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

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Domain_Plans_PlanContractsV1_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row156 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Plans_PlanContractsV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}
