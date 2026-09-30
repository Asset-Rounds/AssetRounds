import Foundation

enum AuthorityCriterionFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case incompatibleVersion
    case wrongWorkspace
    case duplicateIdentity
    case invalidTransition
    case unknownRelease
    case unsupportedEvaluator
    case insufficientSamples
    case duplicateSample
    case dimensionMismatch
    case arithmeticFailure
    case digestMismatch
}

enum AuthorityCriterionValidationV1 {
    static let zeroUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    static func requireID(_ value: UUID) throws {
        guard value != zeroUUID else { throw AuthorityCriterionFailureV1.invalidValue }
    }

    static func requireText(_ value: String, maximumBytes: Int = 512) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= maximumBytes else {
            throw AuthorityCriterionFailureV1.invalidValue
        }
    }

    static func requireSHA256(_ value: String) throws {
        guard value.count == 64,
              value.unicodeScalars.allSatisfy({
                  (48...57).contains($0.value) || (97...102).contains($0.value)
              }) else { throw AuthorityCriterionFailureV1.invalidValue }
    }

    static func requireURL(_ value: String) throws {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.utf8.count <= 2_048,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw AuthorityCriterionFailureV1.invalidValue
        }
    }

    static func requireWorkspace(_ workspaceID: WorkspaceID) throws {
        guard workspaceID.rawValue != zeroUUID else { throw AuthorityCriterionFailureV1.invalidValue }
    }

    static func requireMutationID(_ mutationID: MutationIDV1) throws {
        try requireID(mutationID.rawValue)
    }

    static func sameWorkspaceString(_ value: String, as workspaceID: WorkspaceID) -> Bool {
        value.caseInsensitiveCompare(workspaceID.rawValue.uuidString) == .orderedSame
    }

    static func requireUnique<T: Hashable>(_ values: [T]) throws {
        guard Set(values).count == values.count else {
            throw AuthorityCriterionFailureV1.duplicateIdentity
        }
    }
}

/// Compatibility defaults keep pre-C40 construction sites source-compatible while
/// remaining deterministic. Canonical writers should always provide their own
/// mutation identity.
enum AuthorityCriterionDefaultsV1 {
    static let mutationID: MutationIDV1 = {
        try! MutationIDV1(rawValue: UUID(uuidString: "00000000-0000-0000-0000-00000000c040")!)
    }()
}

private enum AuthorityCriterionValidationContextV1 {
    private static let sourceBindingKey = "FieldEvidence.AuthorityCriterion.sourceBindingValidation"

    static var isValidatingSourceBinding: Bool {
        get { Thread.current.threadDictionary[sourceBindingKey] as? Bool ?? false }
        set { Thread.current.threadDictionary[sourceBindingKey] = newValue }
    }
}

/// Rebinds the workspace-owned C23/accountability snapshots used by the
/// authority records without changing their stable identities or content.
/// These helpers stay local to this contract file so the shared C23 models do
/// not acquire a second lifecycle surface.
private enum AuthorityCriterionEmbeddedV1 {
    static func rebound(_ actor: ActorSnapshotV1, to workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        let localActor = try LocalActorReferenceV1(
            actorReferenceID: actor.actor.actorReferenceID,
            workspaceID: workspaceID,
            partyID: actor.actor.partyID,
            displayName: actor.actor.displayName
        )
        return try ActorSnapshotV1(
            snapshotID: actor.snapshotID,
            workspaceID: workspaceID,
            actor: localActor,
            responsibility: actor.responsibility,
            displayNameAtTime: actor.displayNameAtTime,
            capturedAt: actor.capturedAt
        )
    }

    static func rebound(_ qualification: QualificationSnapshotV1, to workspaceID: WorkspaceID) throws -> QualificationSnapshotV1 {
        try QualificationSnapshotV1(
            snapshotID: qualification.snapshotID,
            workspaceID: workspaceID,
            declaredScope: qualification.declaredScope,
            issuerDisplay: qualification.issuerDisplay,
            credentialLocator: qualification.credentialLocator,
            effectiveAt: qualification.effectiveAt,
            expiresAt: qualification.expiresAt,
            provenance: qualification.provenance,
            capturedAt: qualification.capturedAt
        )
    }

    static func rebound(_ reference: ContentReferenceV1, to workspaceID: WorkspaceID) throws -> ContentReferenceV1 {
        try ContentReferenceV1(
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: reference.contentID,
            byteLength: reference.byteLength,
            mediaType: reference.mediaType,
            digests: reference.digests,
            byteRole: reference.byteRole,
            createdAt: reference.createdAt
        )
    }

    static func rebound(_ locator: ContentLocatorV1, to workspaceID: WorkspaceID) throws -> ContentLocatorV1 {
        try ContentLocatorV1(
            locatorID: locator.locatorID,
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: locator.contentID,
            locatorRevision: locator.locatorRevision,
            contentDigest: locator.contentDigest,
            expectedByteLength: locator.expectedByteLength
        )
    }
}

enum AuthoritySourceTypeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case guidance = "GUIDANCE"
    case voluntaryStandard = "VOLUNTARY_STANDARD"
    case adoptedRule = "ADOPTED_RULE"
    case manufacturerInstruction = "MANUFACTURER_INSTRUCTION"
    case contractOrInsurer = "CONTRACT_OR_INSURER"
    case ownerPolicy = "OWNER_POLICY"
}

enum LicenseStorageDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case metadataAndLocatorOnly = "METADATA_AND_LOCATOR_ONLY"
    case lawfulContentReference = "LAWFUL_CONTENT_REFERENCE"
    case externalLocatorOnly = "EXTERNAL_LOCATOR_ONLY"
    case notStored = "NOT_STORED"
}

struct AuthoritySourceReleaseV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let releaseID: UUID
    let workspaceID: WorkspaceID
    let sourceID: UUID
    let sourceType: AuthoritySourceTypeV1
    let designation: String
    let editionOrRevision: String
    let publisherDisplay: String?
    let publicationAt: Date?
    let effectiveFrom: Date?
    let effectiveUntil: Date?
    let addenda: String?
    let corrigenda: String?
    let sourceURL: String?
    let retrievedAt: Date
    let sourceDigestSHA256: String?
    let licenseStorageDisposition: LicenseStorageDispositionV1
    /// Optional lawful C23 content bytes; C40 never owns a second byte store.
    let lawfulContentReference: ContentReferenceV1?
    /// Optional C23 locator. This is intentionally distinct from `sourceURL`.
    let contentLocator: ContentLocatorV1?
    let supersedesReleaseID: UUID?
    let retiredAt: Date?
    let recordedAt: Date
    let revision: UInt64
    let mutationID: MutationIDV1
    let releaseSHA256: String

    init(
        releaseID: UUID,
        workspaceID: WorkspaceID,
        sourceID: UUID,
        sourceType: AuthoritySourceTypeV1,
        designation: String,
        editionOrRevision: String,
        publisherDisplay: String? = nil,
        publicationAt: Date? = nil,
        effectiveFrom: Date? = nil,
        effectiveUntil: Date? = nil,
        addenda: String? = nil,
        corrigenda: String? = nil,
        sourceURL: String? = nil,
        retrievedAt: Date? = nil,
        sourceDigestSHA256: String? = nil,
        licenseStorageDisposition: LicenseStorageDispositionV1,
        lawfulContentReference: ContentReferenceV1? = nil,
        contentLocator: ContentLocatorV1? = nil,
        supersedesReleaseID: UUID? = nil,
        retiredAt: Date? = nil,
        recordedAt: Date,
        revision: UInt64 = 1,
        mutationID: MutationIDV1 = AuthorityCriterionDefaultsV1.mutationID
    ) throws {
        schemaVersion = Self.schemaVersion
        self.releaseID = releaseID
        self.workspaceID = workspaceID
        self.sourceID = sourceID
        self.sourceType = sourceType
        self.designation = designation
        self.editionOrRevision = editionOrRevision
        self.publisherDisplay = publisherDisplay
        self.publicationAt = publicationAt
        self.effectiveFrom = effectiveFrom
        self.effectiveUntil = effectiveUntil
        self.addenda = addenda
        self.corrigenda = corrigenda
        self.sourceURL = sourceURL
        self.retrievedAt = retrievedAt ?? recordedAt
        self.sourceDigestSHA256 = sourceDigestSHA256
        self.licenseStorageDisposition = licenseStorageDisposition
        self.lawfulContentReference = lawfulContentReference
        self.contentLocator = contentLocator
        self.supersedesReleaseID = supersedesReleaseID
        self.retiredAt = retiredAt
        self.recordedAt = recordedAt
        self.revision = revision
        self.mutationID = mutationID
        releaseSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, releaseID: releaseID, workspaceID: workspaceID,
            sourceID: sourceID, sourceType: sourceType, designation: designation,
            editionOrRevision: editionOrRevision, publisherDisplay: publisherDisplay,
            publicationAt: publicationAt, effectiveFrom: effectiveFrom, effectiveUntil: effectiveUntil,
            addenda: addenda, corrigenda: corrigenda, sourceURL: sourceURL,
            retrievedAt: retrievedAt ?? recordedAt, sourceDigestSHA256: sourceDigestSHA256,
            licenseStorageDisposition: licenseStorageDisposition,
            lawfulContentReference: lawfulContentReference, contentLocator: contentLocator,
            supersedesReleaseID: supersedesReleaseID, retiredAt: retiredAt, recordedAt: recordedAt,
            revision: revision, mutationID: mutationID
        ))
        try validate()
    }

    func validate() throws {
        try AuthorityCriterionValidationV1.requireID(releaseID)
        try AuthorityCriterionValidationV1.requireID(sourceID)
        try AuthorityCriterionValidationV1.requireWorkspace(workspaceID)
        try AuthorityCriterionValidationV1.requireText(designation)
        try AuthorityCriterionValidationV1.requireText(editionOrRevision, maximumBytes: 256)
        if let publisherDisplay { try AuthorityCriterionValidationV1.requireText(publisherDisplay, maximumBytes: 256) }
        if let addenda { try AuthorityCriterionValidationV1.requireText(addenda, maximumBytes: 1_024) }
        if let corrigenda { try AuthorityCriterionValidationV1.requireText(corrigenda, maximumBytes: 1_024) }
        if let sourceURL {
            try AuthorityCriterionValidationV1.requireURL(sourceURL)
        }
        if let sourceDigestSHA256 {
            try AuthorityCriterionValidationV1.requireSHA256(sourceDigestSHA256)
        }
        if let supersedesReleaseID { try AuthorityCriterionValidationV1.requireID(supersedesReleaseID) }
        guard schemaVersion == Self.schemaVersion, revision > 0,
              supersedesReleaseID != releaseID,
              publicationAt.map { $0 <= retrievedAt } ?? true,
              effectiveUntil.map { until in effectiveFrom.map { $0 <= until } ?? true } ?? true,
              retiredAt.map { $0 >= recordedAt } ?? true,
              recordedAt >= retrievedAt else {
            throw AuthorityCriterionFailureV1.invalidValue
        }
        switch licenseStorageDisposition {
        case .lawfulContentReference:
            guard lawfulContentReference != nil else { throw AuthorityCriterionFailureV1.invalidValue }
        case .externalLocatorOnly:
            guard contentLocator != nil, lawfulContentReference == nil else { throw AuthorityCriterionFailureV1.invalidValue }
        case .metadataAndLocatorOnly, .notStored:
            guard lawfulContentReference == nil else { throw AuthorityCriterionFailureV1.invalidValue }
        }
        if let lawfulContentReference {
            guard AuthorityCriterionValidationV1.sameWorkspaceString(
                lawfulContentReference.workspaceID,
                as: workspaceID
            ) else {
                throw AuthorityCriterionFailureV1.wrongWorkspace
            }
        }
        if let contentLocator {
            guard AuthorityCriterionValidationV1.sameWorkspaceString(contentLocator.workspaceID, as: workspaceID) else {
                throw AuthorityCriterionFailureV1.wrongWorkspace
            }
        }
        if !AuthorityCriterionValidationContextV1.isValidatingSourceBinding {
            AuthorityCriterionValidationContextV1.isValidatingSourceBinding = true
            defer { AuthorityCriterionValidationContextV1.isValidatingSourceBinding = false }
            if let lawfulContentReference {
                try lawfulContentReference.validateAuthoritySourceBinding(self)
            }
            if let contentLocator {
                try contentLocator.validateAuthoritySourceBinding(self)
            }
        }
        try AuthorityCriterionValidationV1.requireMutationID(mutationID)
        let expected = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: schemaVersion, releaseID: releaseID, workspaceID: workspaceID,
            sourceID: sourceID, sourceType: sourceType, designation: designation,
            editionOrRevision: editionOrRevision, publisherDisplay: publisherDisplay,
            publicationAt: publicationAt, effectiveFrom: effectiveFrom, effectiveUntil: effectiveUntil,
            addenda: addenda, corrigenda: corrigenda, sourceURL: sourceURL,
            retrievedAt: retrievedAt, sourceDigestSHA256: sourceDigestSHA256,
            licenseStorageDisposition: licenseStorageDisposition,
            lawfulContentReference: lawfulContentReference, contentLocator: contentLocator,
            supersedesReleaseID: supersedesReleaseID, retiredAt: retiredAt, recordedAt: recordedAt,
            revision: revision, mutationID: mutationID
        ))
        guard expected == releaseSHA256 else { throw AuthorityCriterionFailureV1.digestMismatch }
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        try AuthorityCriterionValidationV1.requireWorkspace(workspaceID)
        let reference: ContentReferenceV1?
        if let lawfulContentReference {
            reference = try AuthorityCriterionEmbeddedV1.rebound(lawfulContentReference, to: workspaceID)
        } else {
            reference = nil
        }
        let locator: ContentLocatorV1?
        if let contentLocator {
            locator = try AuthorityCriterionEmbeddedV1.rebound(contentLocator, to: workspaceID)
        } else {
            locator = nil
        }
        return try Self(
            releaseID: releaseID,
            workspaceID: workspaceID,
            sourceID: sourceID,
            sourceType: sourceType,
            designation: designation,
            editionOrRevision: editionOrRevision,
            publisherDisplay: publisherDisplay,
            publicationAt: publicationAt,
            effectiveFrom: effectiveFrom,
            effectiveUntil: effectiveUntil,
            addenda: addenda,
            corrigenda: corrigenda,
            sourceURL: sourceURL,
            retrievedAt: retrievedAt,
            sourceDigestSHA256: sourceDigestSHA256,
            licenseStorageDisposition: licenseStorageDisposition,
            lawfulContentReference: reference,
            contentLocator: locator,
            supersedesReleaseID: supersedesReleaseID,
            retiredAt: retiredAt,
            recordedAt: recordedAt,
            revision: revision,
            mutationID: mutationID
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int; let releaseID: UUID; let workspaceID: WorkspaceID; let sourceID: UUID
        let sourceType: AuthoritySourceTypeV1; let designation: String; let editionOrRevision: String
        let publisherDisplay: String?; let publicationAt: Date?; let effectiveFrom: Date?; let effectiveUntil: Date?
        let addenda: String?; let corrigenda: String?; let sourceURL: String?; let retrievedAt: Date
        let sourceDigestSHA256: String?
        let licenseStorageDisposition: LicenseStorageDispositionV1
        let lawfulContentReference: ContentReferenceV1?; let contentLocator: ContentLocatorV1?
        let supersedesReleaseID: UUID?; let retiredAt: Date?; let recordedAt: Date
        let revision: UInt64; let mutationID: MutationIDV1
    }
}

enum RequirementBasisKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case adoptedRequirement = "ADOPTED_REQUIREMENT"
    case contractRequirement = "CONTRACT_REQUIREMENT"
    case ownerPolicy = "OWNER_POLICY"
    case declaredScreeningBasis = "DECLARED_SCREENING_BASIS"
}

struct RequirementBasisBindingV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let bindingID: UUID
    let workspaceID: WorkspaceID
    let basisKind: RequirementBasisKindV1
    let authorityReleaseID: UUID
    let criterionID: String
    let clauseLocator: String?
    let selectedBy: ActorSnapshotV1
    let selectedAt: Date
    let supersedesBindingID: UUID?
    let revision: UInt64
    let mutationID: MutationIDV1
    let bindingSHA256: String

    init(bindingID: UUID, workspaceID: WorkspaceID, basisKind: RequirementBasisKindV1,
         authorityReleaseID: UUID, criterionID: String, clauseLocator: String? = nil,
         selectedBy: ActorSnapshotV1, selectedAt: Date, supersedesBindingID: UUID? = nil,
         revision: UInt64 = 1, mutationID: MutationIDV1 = AuthorityCriterionDefaultsV1.mutationID) throws {
        schemaVersion = Self.schemaVersion; self.bindingID = bindingID; self.workspaceID = workspaceID
        self.basisKind = basisKind; self.authorityReleaseID = authorityReleaseID; self.criterionID = criterionID
        self.clauseLocator = clauseLocator; self.selectedBy = selectedBy; self.selectedAt = selectedAt
        self.supersedesBindingID = supersedesBindingID; self.revision = revision; self.mutationID = mutationID
        bindingSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, bindingID: bindingID, workspaceID: workspaceID,
            basisKind: basisKind, authorityReleaseID: authorityReleaseID, criterionID: criterionID,
            clauseLocator: clauseLocator, selectedBy: selectedBy, selectedAt: selectedAt,
            supersedesBindingID: supersedesBindingID, revision: revision, mutationID: mutationID
        ))
        try validate()
    }

    func validate() throws {
        try AuthorityCriterionValidationV1.requireID(bindingID)
        try AuthorityCriterionValidationV1.requireID(authorityReleaseID)
        try AuthorityCriterionValidationV1.requireWorkspace(workspaceID)
        try AuthorityCriterionValidationV1.requireText(criterionID, maximumBytes: 256)
        if let clauseLocator { try AuthorityCriterionValidationV1.requireText(clauseLocator) }
        try selectedBy.validate()
        try AuthorityCriterionValidationV1.requireMutationID(mutationID)
        guard schemaVersion == Self.schemaVersion, revision > 0, selectedBy.workspaceID == workspaceID,
              supersedesBindingID != bindingID else { throw AuthorityCriterionFailureV1.wrongWorkspace }
        let expected = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: schemaVersion, bindingID: bindingID, workspaceID: workspaceID,
            basisKind: basisKind, authorityReleaseID: authorityReleaseID, criterionID: criterionID,
            clauseLocator: clauseLocator, selectedBy: selectedBy, selectedAt: selectedAt,
            supersedesBindingID: supersedesBindingID, revision: revision, mutationID: mutationID
        ))
        guard expected == bindingSHA256 else { throw AuthorityCriterionFailureV1.digestMismatch }
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        let reboundActor = try AuthorityCriterionEmbeddedV1.rebound(selectedBy, to: workspaceID)
        return try Self(
            bindingID: bindingID,
            workspaceID: workspaceID,
            basisKind: basisKind,
            authorityReleaseID: authorityReleaseID,
            criterionID: criterionID,
            clauseLocator: clauseLocator,
            selectedBy: reboundActor,
            selectedAt: selectedAt,
            supersedesBindingID: supersedesBindingID,
            revision: revision,
            mutationID: mutationID
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int; let bindingID: UUID; let workspaceID: WorkspaceID
        let basisKind: RequirementBasisKindV1; let authorityReleaseID: UUID; let criterionID: String
        let clauseLocator: String?; let selectedBy: ActorSnapshotV1; let selectedAt: Date
        let supersedesBindingID: UUID?; let revision: UInt64; let mutationID: MutationIDV1
    }
}

enum ApplicabilityDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case applicable = "APPLICABLE"
    case notApplicableWithReason = "NOT_APPLICABLE_WITH_REASON"
    case unknown = "UNKNOWN"
    case conflictReviewRequired = "CONFLICT_REVIEW_REQUIRED"
    case unsupported = "UNSUPPORTED"
}

struct ApplicabilityContextSnapshotV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let snapshotID: UUID
    let workspaceID: WorkspaceID
    let siteID: UUID
    let activityID: UUID
    let workSubjectScope: WorkSubjectScopeSnapshotV1
    let packageReleases: [PackageReleaseIdentityV1]
    let actor: ActorSnapshotV1
    let qualification: QualificationSnapshotV1?
    let effectiveAt: Date
    let basisBindings: [RequirementBasisBindingV1]
    let disposition: ApplicabilityDispositionV1
    let dispositionReason: String?
    let supersedesSnapshotID: UUID?
    let recordedAt: Date
    let revision: UInt64
    let mutationID: MutationIDV1
    let snapshotSHA256: String

    init(snapshotID: UUID, workspaceID: WorkspaceID, siteID: UUID, activityID: UUID,
         workSubjectScope: WorkSubjectScopeSnapshotV1, packageReleases: [PackageReleaseIdentityV1],
         actor: ActorSnapshotV1, qualification: QualificationSnapshotV1? = nil,
         effectiveAt: Date, basisBindings: [RequirementBasisBindingV1],
         disposition: ApplicabilityDispositionV1, dispositionReason: String? = nil,
         supersedesSnapshotID: UUID? = nil, recordedAt: Date, revision: UInt64 = 1,
         mutationID: MutationIDV1 = AuthorityCriterionDefaultsV1.mutationID) throws {
        schemaVersion = Self.schemaVersion; self.snapshotID = snapshotID; self.workspaceID = workspaceID
        self.siteID = siteID; self.activityID = activityID; self.workSubjectScope = workSubjectScope
        self.packageReleases = packageReleases.sorted(); self.actor = actor; self.qualification = qualification
        self.effectiveAt = effectiveAt; self.basisBindings = basisBindings.sorted { $0.bindingID.uuidString < $1.bindingID.uuidString }
        self.disposition = disposition; self.dispositionReason = dispositionReason
        self.supersedesSnapshotID = supersedesSnapshotID; self.recordedAt = recordedAt
        self.revision = revision; self.mutationID = mutationID
        snapshotSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, snapshotID: snapshotID, workspaceID: workspaceID,
            siteID: siteID, activityID: activityID, workSubjectScope: workSubjectScope,
            packageReleases: self.packageReleases, actor: actor, qualification: qualification,
            effectiveAt: effectiveAt, basisBindings: self.basisBindings,
            disposition: disposition, dispositionReason: dispositionReason,
            supersedesSnapshotID: supersedesSnapshotID, recordedAt: recordedAt,
            revision: revision, mutationID: mutationID
        ))
        try validate()
    }

    func validate() throws {
        try AuthorityCriterionValidationV1.requireID(snapshotID); try AuthorityCriterionValidationV1.requireID(siteID)
        try AuthorityCriterionValidationV1.requireID(activityID); try AuthorityCriterionValidationV1.requireWorkspace(workspaceID)
        try actor.validateAuthoritySelection(workspaceID: workspaceID)
        try qualification?.validateDeclaredApplicability(at: effectiveAt, workspaceID: workspaceID)
        try workSubjectScope.validateAuthorityAssessmentScope(
            workspaceID: workspaceID,
            siteID: siteID,
            packageReleases: packageReleases
        )
        for binding in basisBindings { try binding.validate() }
        try AuthorityCriterionValidationV1.requireUnique(packageReleases)
        try AuthorityCriterionValidationV1.requireUnique(basisBindings.map(\.bindingID))
        let needsReason: Bool = disposition == .notApplicableWithReason || disposition == .conflictReviewRequired || disposition == .unsupported
        if needsReason { try AuthorityCriterionValidationV1.requireText(dispositionReason ?? "") }
        if let supersedesSnapshotID { try AuthorityCriterionValidationV1.requireID(supersedesSnapshotID) }
        try AuthorityCriterionValidationV1.requireMutationID(mutationID)
        guard schemaVersion == Self.schemaVersion, revision > 0, recordedAt >= effectiveAt,
              supersedesSnapshotID != snapshotID,
              workSubjectScope.workspaceID == workspaceID, workSubjectScope.siteID == siteID,
              actor.workspaceID == workspaceID,
              qualification.map { $0.workspaceID == workspaceID } ?? true,
              basisBindings.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw AuthorityCriterionFailureV1.wrongWorkspace
        }
        let expected = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: schemaVersion, snapshotID: snapshotID, workspaceID: workspaceID,
            siteID: siteID, activityID: activityID, workSubjectScope: workSubjectScope,
            packageReleases: packageReleases, actor: actor, qualification: qualification,
            effectiveAt: effectiveAt, basisBindings: basisBindings,
            disposition: disposition, dispositionReason: dispositionReason,
            supersedesSnapshotID: supersedesSnapshotID, recordedAt: recordedAt,
            revision: revision, mutationID: mutationID
        ))
        guard expected == snapshotSHA256 else { throw AuthorityCriterionFailureV1.digestMismatch }
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        let reboundScope = try workSubjectScope.rebound(to: workspaceID)
        let reboundActor = try AuthorityCriterionEmbeddedV1.rebound(actor, to: workspaceID)
        let reboundQualification: QualificationSnapshotV1?
        if let qualification {
            reboundQualification = try AuthorityCriterionEmbeddedV1.rebound(qualification, to: workspaceID)
        } else {
            reboundQualification = nil
        }
        let reboundBindings = try basisBindings.map { try $0.rebound(to: workspaceID) }
        return try Self(
            snapshotID: snapshotID,
            workspaceID: workspaceID,
            siteID: siteID,
            activityID: activityID,
            workSubjectScope: reboundScope,
            packageReleases: packageReleases,
            actor: reboundActor,
            qualification: reboundQualification,
            effectiveAt: effectiveAt,
            basisBindings: reboundBindings,
            disposition: disposition,
            dispositionReason: dispositionReason,
            supersedesSnapshotID: supersedesSnapshotID,
            recordedAt: recordedAt,
            revision: revision,
            mutationID: mutationID
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID
        let siteID: UUID; let activityID: UUID; let workSubjectScope: WorkSubjectScopeSnapshotV1
        let packageReleases: [PackageReleaseIdentityV1]; let actor: ActorSnapshotV1
        let qualification: QualificationSnapshotV1?; let effectiveAt: Date
        let basisBindings: [RequirementBasisBindingV1]; let disposition: ApplicabilityDispositionV1
        let dispositionReason: String?; let supersedesSnapshotID: UUID?; let recordedAt: Date
        let revision: UInt64; let mutationID: MutationIDV1
    }
}

struct AssessmentScopeSnapshotV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let snapshotID: UUID
    let workspaceID: WorkspaceID
    let applicabilityContextID: UUID
    let workSubjectScope: WorkSubjectScopeSnapshotV1
    let includedCriterionIDs: [String]
    let excludedCriterionReasons: [String: String]
    let supersedesSnapshotID: UUID?
    let recordedAt: Date
    let revision: UInt64
    let mutationID: MutationIDV1
    let snapshotSHA256: String

    init(snapshotID: UUID, workspaceID: WorkspaceID, applicabilityContextID: UUID,
         workSubjectScope: WorkSubjectScopeSnapshotV1, includedCriterionIDs: [String],
         excludedCriterionReasons: [String: String] = [:], supersedesSnapshotID: UUID? = nil, recordedAt: Date,
         revision: UInt64 = 1, mutationID: MutationIDV1 = AuthorityCriterionDefaultsV1.mutationID) throws {
        schemaVersion = Self.schemaVersion; self.snapshotID = snapshotID; self.workspaceID = workspaceID
        self.applicabilityContextID = applicabilityContextID; self.workSubjectScope = workSubjectScope
        self.includedCriterionIDs = includedCriterionIDs.sorted(); self.excludedCriterionReasons = excludedCriterionReasons
        self.supersedesSnapshotID = supersedesSnapshotID; self.recordedAt = recordedAt
        self.revision = revision; self.mutationID = mutationID
        snapshotSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, snapshotID: snapshotID, workspaceID: workspaceID,
            applicabilityContextID: applicabilityContextID, workSubjectScope: workSubjectScope,
            includedCriterionIDs: self.includedCriterionIDs, excludedCriterionReasons: excludedCriterionReasons,
            supersedesSnapshotID: supersedesSnapshotID,
            recordedAt: recordedAt, revision: revision, mutationID: mutationID
        ))
        try validate()
    }

    func validate() throws {
        try AuthorityCriterionValidationV1.requireID(snapshotID); try AuthorityCriterionValidationV1.requireID(applicabilityContextID)
        try AuthorityCriterionValidationV1.requireWorkspace(workspaceID); try workSubjectScope.validate()
        try AuthorityCriterionValidationV1.requireUnique(includedCriterionIDs)
        for value in includedCriterionIDs { try AuthorityCriterionValidationV1.requireText(value, maximumBytes: 256) }
        for (key, value) in excludedCriterionReasons { try AuthorityCriterionValidationV1.requireText(key, maximumBytes: 256); try AuthorityCriterionValidationV1.requireText(value) }
        if let supersedesSnapshotID { try AuthorityCriterionValidationV1.requireID(supersedesSnapshotID) }
        try AuthorityCriterionValidationV1.requireMutationID(mutationID)
        guard schemaVersion == Self.schemaVersion, revision > 0, workSubjectScope.workspaceID == workspaceID,
              supersedesSnapshotID != snapshotID,
              Set(includedCriterionIDs).isDisjoint(with: Set(excludedCriterionReasons.keys)) else {
            throw AuthorityCriterionFailureV1.invalidValue
        }
        let expected = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: schemaVersion, snapshotID: snapshotID, workspaceID: workspaceID,
            applicabilityContextID: applicabilityContextID, workSubjectScope: workSubjectScope,
            includedCriterionIDs: includedCriterionIDs, excludedCriterionReasons: excludedCriterionReasons,
            supersedesSnapshotID: supersedesSnapshotID,
            recordedAt: recordedAt, revision: revision, mutationID: mutationID
        ))
        guard expected == snapshotSHA256 else { throw AuthorityCriterionFailureV1.digestMismatch }
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        try Self(
            snapshotID: snapshotID,
            workspaceID: workspaceID,
            applicabilityContextID: applicabilityContextID,
            workSubjectScope: try workSubjectScope.rebound(to: workspaceID),
            includedCriterionIDs: includedCriterionIDs,
            excludedCriterionReasons: excludedCriterionReasons,
            supersedesSnapshotID: supersedesSnapshotID,
            recordedAt: recordedAt,
            revision: revision,
            mutationID: mutationID
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int; let snapshotID: UUID; let workspaceID: WorkspaceID
        let applicabilityContextID: UUID; let workSubjectScope: WorkSubjectScopeSnapshotV1
        let includedCriterionIDs: [String]; let excludedCriterionReasons: [String: String]
        let supersedesSnapshotID: UUID?
        let recordedAt: Date; let revision: UInt64; let mutationID: MutationIDV1
    }
}

enum ScreeningCriterionResultV1: String, CaseIterable, Codable, Hashable, Sendable {
    case meetsScreeningCriterion = "MEETS_SCREENING_CRITERION"
    case doesNotMeet = "DOES_NOT_MEET"
    case inconclusive = "INCONCLUSIVE"
    case notEvaluated = "NOT_EVALUATED"
}

struct SeverityLevelDefinitionV1: Codable, Equatable, Hashable, Sendable {
    let levelID: String
    let localizedLabelKey: String
    let descriptionKey: String
    init(levelID: String, localizedLabelKey: String, descriptionKey: String) throws {
        try AuthorityCriterionValidationV1.requireText(levelID, maximumBytes: 128)
        try AuthorityCriterionValidationV1.requireText(localizedLabelKey, maximumBytes: 256)
        try AuthorityCriterionValidationV1.requireText(descriptionKey, maximumBytes: 256)
        self.levelID = levelID; self.localizedLabelKey = localizedLabelKey; self.descriptionKey = descriptionKey
    }
}

struct SeverityScaleReleaseV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let releaseID: UUID
    let workspaceID: WorkspaceID
    let scaleID: UUID
    let designation: String
    let levels: [SeverityLevelDefinitionV1]
    let supersedesReleaseID: UUID?
    let recordedAt: Date
    let revision: UInt64
    let mutationID: MutationIDV1
    let releaseSHA256: String

    init(releaseID: UUID, workspaceID: WorkspaceID, scaleID: UUID, designation: String,
         levels: [SeverityLevelDefinitionV1], supersedesReleaseID: UUID? = nil, recordedAt: Date,
         revision: UInt64 = 1, mutationID: MutationIDV1 = AuthorityCriterionDefaultsV1.mutationID) throws {
        schemaVersion = Self.schemaVersion; self.releaseID = releaseID; self.workspaceID = workspaceID; self.scaleID = scaleID
        self.designation = designation; self.levels = levels; self.supersedesReleaseID = supersedesReleaseID; self.recordedAt = recordedAt
        self.revision = revision; self.mutationID = mutationID
        releaseSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, releaseID: releaseID, workspaceID: workspaceID,
            scaleID: scaleID, designation: designation, levels: levels,
            supersedesReleaseID: supersedesReleaseID, recordedAt: recordedAt,
            revision: revision, mutationID: mutationID
        ))
        try validate()
    }

    func validate() throws {
        try AuthorityCriterionValidationV1.requireID(releaseID); try AuthorityCriterionValidationV1.requireID(scaleID)
        try AuthorityCriterionValidationV1.requireWorkspace(workspaceID); try AuthorityCriterionValidationV1.requireText(designation)
        try AuthorityCriterionValidationV1.requireUnique(levels.map(\.levelID))
        try AuthorityCriterionValidationV1.requireMutationID(mutationID)
        guard schemaVersion == Self.schemaVersion, revision > 0, !levels.isEmpty, levels.count <= 64,
              supersedesReleaseID != releaseID else { throw AuthorityCriterionFailureV1.invalidValue }
        let expected = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: schemaVersion, releaseID: releaseID, workspaceID: workspaceID,
            scaleID: scaleID, designation: designation, levels: levels,
            supersedesReleaseID: supersedesReleaseID, recordedAt: recordedAt,
            revision: revision, mutationID: mutationID
        ))
        guard expected == releaseSHA256 else { throw AuthorityCriterionFailureV1.digestMismatch }
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        try Self(
            releaseID: releaseID,
            workspaceID: workspaceID,
            scaleID: scaleID,
            designation: designation,
            levels: levels,
            supersedesReleaseID: supersedesReleaseID,
            recordedAt: recordedAt,
            revision: revision,
            mutationID: mutationID
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int; let releaseID: UUID; let workspaceID: WorkspaceID
        let scaleID: UUID; let designation: String; let levels: [SeverityLevelDefinitionV1]
        let supersedesReleaseID: UUID?; let recordedAt: Date
        let revision: UInt64; let mutationID: MutationIDV1
    }
}

struct SeverityScaleMappingEntryV1: Codable, Equatable, Hashable, Sendable {
    let sourceLevelID: String; let destinationLevelID: String
    init(sourceLevelID: String, destinationLevelID: String) throws {
        try AuthorityCriterionValidationV1.requireText(sourceLevelID, maximumBytes: 128)
        try AuthorityCriterionValidationV1.requireText(destinationLevelID, maximumBytes: 128)
        self.sourceLevelID = sourceLevelID; self.destinationLevelID = destinationLevelID
    }
}

struct SeverityScaleMappingReleaseV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let releaseID: UUID; let workspaceID: WorkspaceID
    let sourceScaleReleaseID: UUID; let destinationScaleReleaseID: UUID
    let entries: [SeverityScaleMappingEntryV1]; let recordedAt: Date
    let supersedesReleaseID: UUID?
    let revision: UInt64
    let mutationID: MutationIDV1
    let releaseSHA256: String
    init(releaseID: UUID, workspaceID: WorkspaceID, sourceScaleReleaseID: UUID,
         destinationScaleReleaseID: UUID, entries: [SeverityScaleMappingEntryV1], recordedAt: Date,
         supersedesReleaseID: UUID? = nil, revision: UInt64 = 1,
         mutationID: MutationIDV1 = AuthorityCriterionDefaultsV1.mutationID) throws {
        schemaVersion = Self.schemaVersion; self.releaseID = releaseID; self.workspaceID = workspaceID
        self.sourceScaleReleaseID = sourceScaleReleaseID; self.destinationScaleReleaseID = destinationScaleReleaseID
        self.entries = entries.sorted {
            if $0.sourceLevelID != $1.sourceLevelID { return $0.sourceLevelID < $1.sourceLevelID }
            return $0.destinationLevelID < $1.destinationLevelID
        }; self.recordedAt = recordedAt; self.supersedesReleaseID = supersedesReleaseID
        self.revision = revision; self.mutationID = mutationID
        releaseSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, releaseID: releaseID, workspaceID: workspaceID,
            sourceScaleReleaseID: sourceScaleReleaseID, destinationScaleReleaseID: destinationScaleReleaseID,
            entries: self.entries, recordedAt: recordedAt, supersedesReleaseID: supersedesReleaseID,
            revision: revision, mutationID: mutationID
        ))
        try validate()
    }

    func validate() throws {
        try AuthorityCriterionValidationV1.requireID(releaseID)
        try AuthorityCriterionValidationV1.requireWorkspace(workspaceID)
        try AuthorityCriterionValidationV1.requireID(sourceScaleReleaseID)
        try AuthorityCriterionValidationV1.requireID(destinationScaleReleaseID)
        if let supersedesReleaseID { try AuthorityCriterionValidationV1.requireID(supersedesReleaseID) }
        try AuthorityCriterionValidationV1.requireUnique(entries.map(\.sourceLevelID))
        try AuthorityCriterionValidationV1.requireUnique(entries.map(\.destinationLevelID))
        guard schemaVersion == Self.schemaVersion, revision > 0,
              sourceScaleReleaseID != destinationScaleReleaseID,
              !entries.isEmpty,
              entries.count <= 64,
              entries == entries.sorted(by: {
                  if $0.sourceLevelID != $1.sourceLevelID { return $0.sourceLevelID < $1.sourceLevelID }
                  return $0.destinationLevelID < $1.destinationLevelID
              }),
              supersedesReleaseID != releaseID else {
            throw AuthorityCriterionFailureV1.invalidValue
        }
        let expected = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: schemaVersion, releaseID: releaseID, workspaceID: workspaceID,
            sourceScaleReleaseID: sourceScaleReleaseID, destinationScaleReleaseID: destinationScaleReleaseID,
            entries: entries, recordedAt: recordedAt, supersedesReleaseID: supersedesReleaseID,
            revision: revision, mutationID: mutationID
        ))
        try AuthorityCriterionValidationV1.requireMutationID(mutationID)
        guard expected == releaseSHA256 else { throw AuthorityCriterionFailureV1.digestMismatch }
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        try Self(
            releaseID: releaseID,
            workspaceID: workspaceID,
            sourceScaleReleaseID: sourceScaleReleaseID,
            destinationScaleReleaseID: destinationScaleReleaseID,
            entries: entries,
            recordedAt: recordedAt,
            supersedesReleaseID: supersedesReleaseID,
            revision: revision,
            mutationID: mutationID
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int; let releaseID: UUID; let workspaceID: WorkspaceID
        let sourceScaleReleaseID: UUID; let destinationScaleReleaseID: UUID
        let entries: [SeverityScaleMappingEntryV1]; let recordedAt: Date
        let supersedesReleaseID: UUID?; let revision: UInt64; let mutationID: MutationIDV1
    }
}

struct FindingClassificationBindingV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let bindingID: UUID; let workspaceID: WorkspaceID; let findingID: UUID
    let criterionID: String; let result: ScreeningCriterionResultV1
    let severityScaleReleaseID: UUID?; let severityLevelID: String?
    let applicabilityContextID: UUID; let assessmentScopeID: UUID
    let recordedAt: Date; let supersedesBindingID: UUID?
    let revision: UInt64
    let mutationID: MutationIDV1
    let bindingSHA256: String
    init(bindingID: UUID, workspaceID: WorkspaceID, findingID: UUID, criterionID: String,
         result: ScreeningCriterionResultV1, severityScaleReleaseID: UUID? = nil,
         severityLevelID: String? = nil, applicabilityContextID: UUID, assessmentScopeID: UUID,
         recordedAt: Date, supersedesBindingID: UUID? = nil, revision: UInt64 = 1,
         mutationID: MutationIDV1 = AuthorityCriterionDefaultsV1.mutationID) throws {
        schemaVersion = Self.schemaVersion; self.bindingID = bindingID; self.workspaceID = workspaceID; self.findingID = findingID
        self.criterionID = criterionID; self.result = result; self.severityScaleReleaseID = severityScaleReleaseID
        self.severityLevelID = severityLevelID; self.applicabilityContextID = applicabilityContextID
        self.assessmentScopeID = assessmentScopeID; self.recordedAt = recordedAt; self.supersedesBindingID = supersedesBindingID
        self.revision = revision; self.mutationID = mutationID
        bindingSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, bindingID: bindingID, workspaceID: workspaceID,
            findingID: findingID, criterionID: criterionID, result: result,
            severityScaleReleaseID: severityScaleReleaseID, severityLevelID: severityLevelID,
            applicabilityContextID: applicabilityContextID, assessmentScopeID: assessmentScopeID,
            recordedAt: recordedAt, supersedesBindingID: supersedesBindingID,
            revision: revision, mutationID: mutationID
        ))
        try validate()
    }
    func validate() throws {
        try AuthorityCriterionValidationV1.requireID(bindingID); try AuthorityCriterionValidationV1.requireID(findingID)
        try AuthorityCriterionValidationV1.requireID(applicabilityContextID); try AuthorityCriterionValidationV1.requireID(assessmentScopeID)
        try AuthorityCriterionValidationV1.requireWorkspace(workspaceID); try AuthorityCriterionValidationV1.requireText(criterionID, maximumBytes: 256)
        try AuthorityCriterionValidationV1.requireMutationID(mutationID)
        guard (severityScaleReleaseID == nil) == (severityLevelID == nil), supersedesBindingID != bindingID else {
            throw AuthorityCriterionFailureV1.invalidValue
        }
        if let severityScaleReleaseID { try AuthorityCriterionValidationV1.requireID(severityScaleReleaseID) }
        if let severityLevelID { try AuthorityCriterionValidationV1.requireText(severityLevelID, maximumBytes: 128) }
        guard schemaVersion == Self.schemaVersion, revision > 0 else {
            throw AuthorityCriterionFailureV1.invalidValue
        }
        let expected = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: schemaVersion, bindingID: bindingID, workspaceID: workspaceID,
            findingID: findingID, criterionID: criterionID, result: result,
            severityScaleReleaseID: severityScaleReleaseID, severityLevelID: severityLevelID,
            applicabilityContextID: applicabilityContextID, assessmentScopeID: assessmentScopeID,
            recordedAt: recordedAt, supersedesBindingID: supersedesBindingID,
            revision: revision, mutationID: mutationID
        ))
        guard expected == bindingSHA256 else { throw AuthorityCriterionFailureV1.digestMismatch }
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        try Self(
            bindingID: bindingID,
            workspaceID: workspaceID,
            findingID: findingID,
            criterionID: criterionID,
            result: result,
            severityScaleReleaseID: severityScaleReleaseID,
            severityLevelID: severityLevelID,
            applicabilityContextID: applicabilityContextID,
            assessmentScopeID: assessmentScopeID,
            recordedAt: recordedAt,
            supersedesBindingID: supersedesBindingID,
            revision: revision,
            mutationID: mutationID
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int; let bindingID: UUID; let workspaceID: WorkspaceID
        let findingID: UUID; let criterionID: String; let result: ScreeningCriterionResultV1
        let severityScaleReleaseID: UUID?; let severityLevelID: String?
        let applicabilityContextID: UUID; let assessmentScopeID: UUID
        let recordedAt: Date; let supersedesBindingID: UUID?
        let revision: UInt64; let mutationID: MutationIDV1
    }
}

enum MeasurementSamplingPolicyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case single = "SINGLE"; case orderedSeries = "ORDERED_SERIES"; case boundedSet = "BOUNDED_SET"
}
enum MeasurementMissingSamplePolicyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case failClosed = "FAIL_CLOSED"; case inconclusive = "INCONCLUSIVE"
}
enum MeasurementOutlierPolicyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case retainAll = "RETAIN_ALL"; case rejectEvaluation = "REJECT_EVALUATION"
}
enum MeasurementDuplicatePolicyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case reject = "REJECT"; case retainDistinctIdentities = "RETAIN_DISTINCT_IDENTITIES"
}

struct MeasurementProtocolReleaseV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let releaseID: UUID; let workspaceID: WorkspaceID; let protocolID: UUID
    let designation: String; let dimension: MeasurementDimensionV1; let normativeUnitID: String
    let samplingPolicy: MeasurementSamplingPolicyV1; let minimumSampleCount: Int; let maximumSampleCount: Int
    let missingSamplePolicy: MeasurementMissingSamplePolicyV1; let outlierPolicy: MeasurementOutlierPolicyV1
    let duplicatePolicy: MeasurementDuplicatePolicyV1; let requiresUncertainty: Bool
    let roundingPolicyVersion: String; let evaluatorDescriptorID: UUID; let supersedesReleaseID: UUID?; let recordedAt: Date
    let revision: UInt64
    let mutationID: MutationIDV1
    let releaseSHA256: String
    init(releaseID: UUID, workspaceID: WorkspaceID, protocolID: UUID, designation: String,
         dimension: MeasurementDimensionV1, normativeUnitID: String,
         samplingPolicy: MeasurementSamplingPolicyV1, minimumSampleCount: Int, maximumSampleCount: Int,
         missingSamplePolicy: MeasurementMissingSamplePolicyV1, outlierPolicy: MeasurementOutlierPolicyV1,
         duplicatePolicy: MeasurementDuplicatePolicyV1, requiresUncertainty: Bool,
         roundingPolicyVersion: String = "TIES_TO_EVEN_V1", evaluatorDescriptorID: UUID,
         supersedesReleaseID: UUID? = nil, recordedAt: Date, revision: UInt64 = 1,
         mutationID: MutationIDV1 = AuthorityCriterionDefaultsV1.mutationID) throws {
        schemaVersion = Self.schemaVersion; self.releaseID = releaseID; self.workspaceID = workspaceID; self.protocolID = protocolID
        self.designation = designation; self.dimension = dimension; self.normativeUnitID = normativeUnitID
        self.samplingPolicy = samplingPolicy; self.minimumSampleCount = minimumSampleCount; self.maximumSampleCount = maximumSampleCount
        self.missingSamplePolicy = missingSamplePolicy; self.outlierPolicy = outlierPolicy; self.duplicatePolicy = duplicatePolicy
        self.requiresUncertainty = requiresUncertainty; self.roundingPolicyVersion = roundingPolicyVersion
        self.evaluatorDescriptorID = evaluatorDescriptorID; self.supersedesReleaseID = supersedesReleaseID; self.recordedAt = recordedAt
        self.revision = revision; self.mutationID = mutationID
        releaseSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, releaseID: releaseID, workspaceID: workspaceID,
            protocolID: protocolID, designation: designation, dimension: dimension,
            normativeUnitID: normativeUnitID, samplingPolicy: samplingPolicy,
            minimumSampleCount: minimumSampleCount, maximumSampleCount: maximumSampleCount,
            missingSamplePolicy: missingSamplePolicy, outlierPolicy: outlierPolicy,
            duplicatePolicy: duplicatePolicy, requiresUncertainty: requiresUncertainty,
            roundingPolicyVersion: roundingPolicyVersion, evaluatorDescriptorID: evaluatorDescriptorID,
            supersedesReleaseID: supersedesReleaseID, recordedAt: recordedAt,
            revision: revision, mutationID: mutationID
        ))
        try validate()
    }
    func validate() throws {
        try AuthorityCriterionValidationV1.requireID(releaseID); try AuthorityCriterionValidationV1.requireID(protocolID)
        try AuthorityCriterionValidationV1.requireID(evaluatorDescriptorID); try AuthorityCriterionValidationV1.requireWorkspace(workspaceID)
        try AuthorityCriterionValidationV1.requireText(designation); try AuthorityCriterionValidationV1.requireText(normativeUnitID, maximumBytes: 128)
        try AuthorityCriterionValidationV1.requireText(roundingPolicyVersion, maximumBytes: 128)
        try AuthorityCriterionValidationV1.requireMutationID(mutationID)
        let unit = try KernelUnitRegistryV1.definition(unitID: normativeUnitID)
        guard schemaVersion == Self.schemaVersion, revision > 0, unit.dimension == dimension, minimumSampleCount > 0,
              maximumSampleCount >= minimumSampleCount, maximumSampleCount <= 10_000,
              supersedesReleaseID != releaseID,
              roundingPolicyVersion == "TIES_TO_EVEN_V1" else { throw AuthorityCriterionFailureV1.invalidValue }
        let expected = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: schemaVersion, releaseID: releaseID, workspaceID: workspaceID,
            protocolID: protocolID, designation: designation, dimension: dimension,
            normativeUnitID: normativeUnitID, samplingPolicy: samplingPolicy,
            minimumSampleCount: minimumSampleCount, maximumSampleCount: maximumSampleCount,
            missingSamplePolicy: missingSamplePolicy, outlierPolicy: outlierPolicy,
            duplicatePolicy: duplicatePolicy, requiresUncertainty: requiresUncertainty,
            roundingPolicyVersion: roundingPolicyVersion, evaluatorDescriptorID: evaluatorDescriptorID,
            supersedesReleaseID: supersedesReleaseID, recordedAt: recordedAt,
            revision: revision, mutationID: mutationID
        ))
        guard expected == releaseSHA256 else { throw AuthorityCriterionFailureV1.digestMismatch }
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        try Self(
            releaseID: releaseID,
            workspaceID: workspaceID,
            protocolID: protocolID,
            designation: designation,
            dimension: dimension,
            normativeUnitID: normativeUnitID,
            samplingPolicy: samplingPolicy,
            minimumSampleCount: minimumSampleCount,
            maximumSampleCount: maximumSampleCount,
            missingSamplePolicy: missingSamplePolicy,
            outlierPolicy: outlierPolicy,
            duplicatePolicy: duplicatePolicy,
            requiresUncertainty: requiresUncertainty,
            roundingPolicyVersion: roundingPolicyVersion,
            evaluatorDescriptorID: evaluatorDescriptorID,
            supersedesReleaseID: supersedesReleaseID,
            recordedAt: recordedAt,
            revision: revision,
            mutationID: mutationID
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int; let releaseID: UUID; let workspaceID: WorkspaceID; let protocolID: UUID
        let designation: String; let dimension: MeasurementDimensionV1; let normativeUnitID: String
        let samplingPolicy: MeasurementSamplingPolicyV1; let minimumSampleCount: Int; let maximumSampleCount: Int
        let missingSamplePolicy: MeasurementMissingSamplePolicyV1; let outlierPolicy: MeasurementOutlierPolicyV1
        let duplicatePolicy: MeasurementDuplicatePolicyV1; let requiresUncertainty: Bool
        let roundingPolicyVersion: String; let evaluatorDescriptorID: UUID
        let supersedesReleaseID: UUID?; let recordedAt: Date
        let revision: UInt64; let mutationID: MutationIDV1
    }
}

enum DerivedFactEvaluatorKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case identityCanonical = "IDENTITY_CANONICAL"
    case arithmeticMeanCanonical = "ARITHMETIC_MEAN_CANONICAL"
    case ratioPercent = "RATIO_PERCENT"
}

struct DerivedFactEvaluatorDescriptorV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let descriptorID: UUID; let workspaceID: WorkspaceID
    let evaluatorID: String; let evaluatorVersion: String; let implementationSHA256: String
    let kind: DerivedFactEvaluatorKindV1; let inputDimension: MeasurementDimensionV1
    let outputDimension: MeasurementDimensionV1; let supersedesDescriptorID: UUID?; let recordedAt: Date
    let revision: UInt64
    let mutationID: MutationIDV1
    let descriptorSHA256: String
    init(descriptorID: UUID, workspaceID: WorkspaceID, evaluatorID: String, evaluatorVersion: String,
         implementationSHA256: String, kind: DerivedFactEvaluatorKindV1,
         inputDimension: MeasurementDimensionV1, outputDimension: MeasurementDimensionV1,
         supersedesDescriptorID: UUID? = nil, recordedAt: Date, revision: UInt64 = 1,
         mutationID: MutationIDV1 = AuthorityCriterionDefaultsV1.mutationID) throws {
        schemaVersion = Self.schemaVersion; self.descriptorID = descriptorID; self.workspaceID = workspaceID
        self.evaluatorID = evaluatorID; self.evaluatorVersion = evaluatorVersion; self.implementationSHA256 = implementationSHA256
        self.kind = kind; self.inputDimension = inputDimension; self.outputDimension = outputDimension
        self.supersedesDescriptorID = supersedesDescriptorID; self.recordedAt = recordedAt
        self.revision = revision; self.mutationID = mutationID
        descriptorSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, descriptorID: descriptorID, workspaceID: workspaceID,
            evaluatorID: evaluatorID, evaluatorVersion: evaluatorVersion,
            implementationSHA256: implementationSHA256, kind: kind,
            inputDimension: inputDimension, outputDimension: outputDimension,
            supersedesDescriptorID: supersedesDescriptorID, recordedAt: recordedAt,
            revision: revision, mutationID: mutationID
        ))
        try validate()
    }
    func validate() throws {
        try AuthorityCriterionValidationV1.requireID(descriptorID); try AuthorityCriterionValidationV1.requireWorkspace(workspaceID)
        try AuthorityCriterionValidationV1.requireText(evaluatorID, maximumBytes: 128)
        try AuthorityCriterionValidationV1.requireText(evaluatorVersion, maximumBytes: 64)
        try AuthorityCriterionValidationV1.requireSHA256(implementationSHA256)
        try AuthorityCriterionValidationV1.requireMutationID(mutationID)
        guard schemaVersion == Self.schemaVersion, revision > 0, supersedesDescriptorID != descriptorID,
              kind != .ratioPercent || outputDimension == .dimensionless else {
            throw AuthorityCriterionFailureV1.invalidValue
        }
        let expected = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: schemaVersion, descriptorID: descriptorID, workspaceID: workspaceID,
            evaluatorID: evaluatorID, evaluatorVersion: evaluatorVersion,
            implementationSHA256: implementationSHA256, kind: kind,
            inputDimension: inputDimension, outputDimension: outputDimension,
            supersedesDescriptorID: supersedesDescriptorID, recordedAt: recordedAt,
            revision: revision, mutationID: mutationID
        ))
        guard expected == descriptorSHA256 else { throw AuthorityCriterionFailureV1.digestMismatch }
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        try Self(
            descriptorID: descriptorID,
            workspaceID: workspaceID,
            evaluatorID: evaluatorID,
            evaluatorVersion: evaluatorVersion,
            implementationSHA256: implementationSHA256,
            kind: kind,
            inputDimension: inputDimension,
            outputDimension: outputDimension,
            supersedesDescriptorID: supersedesDescriptorID,
            recordedAt: recordedAt,
            revision: revision,
            mutationID: mutationID
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int; let descriptorID: UUID; let workspaceID: WorkspaceID
        let evaluatorID: String; let evaluatorVersion: String; let implementationSHA256: String
        let kind: DerivedFactEvaluatorKindV1; let inputDimension: MeasurementDimensionV1
        let outputDimension: MeasurementDimensionV1; let supersedesDescriptorID: UUID?
        let recordedAt: Date; let revision: UInt64; let mutationID: MutationIDV1
    }
}

enum DerivedFactDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case evaluated = "EVALUATED"; case inconclusive = "INCONCLUSIVE"; case notEvaluated = "NOT_EVALUATED"
}

enum DerivedFactSampleStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case present = "PRESENT"
    case missing = "MISSING"
    case outlier = "OUTLIER"
}

struct DerivedFactInputV1: Codable, Equatable, Hashable, Sendable {
    let sampleID: UUID
    let sampleOrdinal: Int
    let state: DerivedFactSampleStateV1
    let measurement: ExactMeasurementV1?

    init(
        sampleID: UUID,
        sampleOrdinal: Int = 1,
        state: DerivedFactSampleStateV1 = .present,
        measurement: ExactMeasurementV1? = nil
    ) throws {
        try AuthorityCriterionValidationV1.requireID(sampleID)
        guard sampleOrdinal > 0 else { throw AuthorityCriterionFailureV1.invalidValue }
        switch state {
        case .missing:
            guard measurement == nil else { throw AuthorityCriterionFailureV1.invalidValue }
        case .present, .outlier:
            guard let measurement else { throw AuthorityCriterionFailureV1.invalidValue }
            try measurement.validate()
        }
        self.sampleID = sampleID
        self.sampleOrdinal = sampleOrdinal
        self.state = state
        self.measurement = measurement
    }

    func validate() throws {
        _ = try Self(
            sampleID: sampleID,
            sampleOrdinal: sampleOrdinal,
            state: state,
            measurement: measurement
        )
    }
}

struct DerivedFactProvenanceV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let provenanceID: UUID; let workspaceID: WorkspaceID
    let protocolReleaseID: UUID; let evaluatorDescriptorID: UUID; let inputs: [DerivedFactInputV1]
    let result: ExactMeasurementV1?; let disposition: DerivedFactDispositionV1
    let uncertaintyCanonical: ExactDecimalV1?; let predecessorProvenanceID: UUID?; let recordedAt: Date
    let revision: UInt64
    let mutationID: MutationIDV1
    let provenanceSHA256: String
    init(provenanceID: UUID, workspaceID: WorkspaceID, protocolReleaseID: UUID,
         evaluatorDescriptorID: UUID, inputs: [DerivedFactInputV1], result: ExactMeasurementV1?,
         disposition: DerivedFactDispositionV1, uncertaintyCanonical: ExactDecimalV1? = nil,
         predecessorProvenanceID: UUID? = nil, recordedAt: Date, revision: UInt64 = 1,
         mutationID: MutationIDV1 = AuthorityCriterionDefaultsV1.mutationID) throws {
        let ordered = inputs.sorted {
            if $0.sampleOrdinal != $1.sampleOrdinal { return $0.sampleOrdinal < $1.sampleOrdinal }
            return $0.sampleID.uuidString < $1.sampleID.uuidString
        }
        schemaVersion = Self.schemaVersion; self.provenanceID = provenanceID; self.workspaceID = workspaceID
        self.protocolReleaseID = protocolReleaseID; self.evaluatorDescriptorID = evaluatorDescriptorID; self.inputs = ordered
        self.result = result; self.disposition = disposition; self.uncertaintyCanonical = uncertaintyCanonical
        self.predecessorProvenanceID = predecessorProvenanceID; self.recordedAt = recordedAt
        self.revision = revision; self.mutationID = mutationID
        provenanceSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion, provenanceID: provenanceID, workspaceID: workspaceID,
            protocolReleaseID: protocolReleaseID, evaluatorDescriptorID: evaluatorDescriptorID,
            inputs: ordered, result: result, disposition: disposition,
            uncertaintyCanonical: uncertaintyCanonical, predecessorProvenanceID: predecessorProvenanceID, recordedAt: recordedAt,
            revision: revision, mutationID: mutationID
        )); try validate()
    }
    func validate() throws {
        try AuthorityCriterionValidationV1.requireID(provenanceID); try AuthorityCriterionValidationV1.requireID(protocolReleaseID)
        try AuthorityCriterionValidationV1.requireID(evaluatorDescriptorID); try AuthorityCriterionValidationV1.requireWorkspace(workspaceID)
        try AuthorityCriterionValidationV1.requireUnique(inputs.map(\.sampleID))
        try AuthorityCriterionValidationV1.requireUnique(inputs.map(\.sampleOrdinal))
        let canonicalOrder = inputs.sorted {
            if $0.sampleOrdinal != $1.sampleOrdinal { return $0.sampleOrdinal < $1.sampleOrdinal }
            return $0.sampleID.uuidString < $1.sampleID.uuidString
        }
        guard inputs == canonicalOrder else { throw AuthorityCriterionFailureV1.invalidValue }
        for input in inputs { try input.validate() }; try result?.validate()
        if let predecessorProvenanceID { try AuthorityCriterionValidationV1.requireID(predecessorProvenanceID) }
        try AuthorityCriterionValidationV1.requireMutationID(mutationID)
        guard schemaVersion == Self.schemaVersion, revision > 0, predecessorProvenanceID != provenanceID,
              (disposition == .evaluated) == (result != nil), uncertaintyCanonical.map({ $0.mantissa >= 0 }) ?? true else {
            throw AuthorityCriterionFailureV1.invalidValue
        }
        let expected = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(
            schemaVersion: schemaVersion, provenanceID: provenanceID, workspaceID: workspaceID,
            protocolReleaseID: protocolReleaseID, evaluatorDescriptorID: evaluatorDescriptorID,
            inputs: inputs, result: result, disposition: disposition,
            uncertaintyCanonical: uncertaintyCanonical, predecessorProvenanceID: predecessorProvenanceID, recordedAt: recordedAt,
            revision: revision, mutationID: mutationID
        ))
        guard provenanceSHA256 == expected else { throw AuthorityCriterionFailureV1.digestMismatch }
    }

    func rebound(to workspaceID: WorkspaceID) throws -> Self {
        try Self(
            provenanceID: provenanceID,
            workspaceID: workspaceID,
            protocolReleaseID: protocolReleaseID,
            evaluatorDescriptorID: evaluatorDescriptorID,
            inputs: inputs,
            result: result,
            disposition: disposition,
            uncertaintyCanonical: uncertaintyCanonical,
            predecessorProvenanceID: predecessorProvenanceID,
            recordedAt: recordedAt,
            revision: revision,
            mutationID: mutationID
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int; let provenanceID: UUID; let workspaceID: WorkspaceID
        let protocolReleaseID: UUID; let evaluatorDescriptorID: UUID; let inputs: [DerivedFactInputV1]
        let result: ExactMeasurementV1?; let disposition: DerivedFactDispositionV1
        let uncertaintyCanonical: ExactDecimalV1?; let predecessorProvenanceID: UUID?; let recordedAt: Date
        let revision: UInt64; let mutationID: MutationIDV1
    }
}

struct AuthorityCriterionAggregateV1: Codable, Equatable, Hashable, Sendable {
    let sourceReleases: [AuthoritySourceReleaseV1]
    let basisBindings: [RequirementBasisBindingV1]
    let applicabilityContexts: [ApplicabilityContextSnapshotV1]
    let assessmentScopes: [AssessmentScopeSnapshotV1]
    let severityScaleReleases: [SeverityScaleReleaseV1]
    let severityMappingReleases: [SeverityScaleMappingReleaseV1]
    let classificationBindings: [FindingClassificationBindingV1]
    let measurementProtocolReleases: [MeasurementProtocolReleaseV1]
    let evaluatorDescriptors: [DerivedFactEvaluatorDescriptorV1]
    let derivedFacts: [DerivedFactProvenanceV1]
}

enum AuthorityCriterionRegistryV1 {
    static func validate(_ aggregate: AuthorityCriterionAggregateV1, workspaceID: WorkspaceID) throws {
        try AuthorityCriterionValidationV1.requireWorkspace(workspaceID)
        try AuthorityCriterionValidationV1.requireUnique(aggregate.sourceReleases.map(\.releaseID))
        try AuthorityCriterionValidationV1.requireUnique(aggregate.basisBindings.map(\.bindingID))
        try AuthorityCriterionValidationV1.requireUnique(aggregate.applicabilityContexts.map(\.snapshotID))
        try AuthorityCriterionValidationV1.requireUnique(aggregate.assessmentScopes.map(\.snapshotID))
        try AuthorityCriterionValidationV1.requireUnique(aggregate.severityScaleReleases.map(\.releaseID))
        try AuthorityCriterionValidationV1.requireUnique(aggregate.severityMappingReleases.map(\.releaseID))
        try AuthorityCriterionValidationV1.requireUnique(aggregate.classificationBindings.map(\.bindingID))
        try AuthorityCriterionValidationV1.requireUnique(aggregate.measurementProtocolReleases.map(\.releaseID))
        try AuthorityCriterionValidationV1.requireUnique(aggregate.evaluatorDescriptors.map(\.descriptorID))
        try AuthorityCriterionValidationV1.requireUnique(aggregate.derivedFacts.map(\.provenanceID))
        for value in aggregate.sourceReleases { try value.validate(); guard value.workspaceID == workspaceID else { throw AuthorityCriterionFailureV1.wrongWorkspace } }
        for value in aggregate.basisBindings { try value.validate(); guard value.workspaceID == workspaceID else { throw AuthorityCriterionFailureV1.wrongWorkspace } }
        for value in aggregate.applicabilityContexts { try value.validate(); guard value.workspaceID == workspaceID else { throw AuthorityCriterionFailureV1.wrongWorkspace } }
        for value in aggregate.assessmentScopes { try value.validate(); guard value.workspaceID == workspaceID else { throw AuthorityCriterionFailureV1.wrongWorkspace } }
        for value in aggregate.severityScaleReleases { try value.validate(); guard value.workspaceID == workspaceID else { throw AuthorityCriterionFailureV1.wrongWorkspace } }
        for value in aggregate.severityMappingReleases { try value.validate(); guard value.workspaceID == workspaceID else { throw AuthorityCriterionFailureV1.wrongWorkspace } }
        for value in aggregate.classificationBindings { try value.validate(); guard value.workspaceID == workspaceID else { throw AuthorityCriterionFailureV1.wrongWorkspace } }
        for value in aggregate.measurementProtocolReleases { try value.validate(); guard value.workspaceID == workspaceID else { throw AuthorityCriterionFailureV1.wrongWorkspace } }
        for value in aggregate.evaluatorDescriptors { try value.validate(); guard value.workspaceID == workspaceID else { throw AuthorityCriterionFailureV1.wrongWorkspace } }
        for value in aggregate.derivedFacts { try value.validate(); guard value.workspaceID == workspaceID else { throw AuthorityCriterionFailureV1.wrongWorkspace } }
    }

    /// Validates the C20 privacy authority at the same workspace boundary as
    /// the other criterion releases. This is an explicit projection check;
    /// it does not create a criterion, classify content, or infer compliance.
    static func c20ValidateReviewedDerivative(
        policy: PrivacyTransformPolicyV1,
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at now: Date,
        workspaceID: WorkspaceID
    ) throws -> ContentReferenceV1 {
        try AuthorityCriterionValidationV1.requireWorkspace(workspaceID)
        try policy.validate()
        guard policy.workspaceID == workspaceID,
              manifest.workspaceID == workspaceID else {
            throw PrivacyTransformFailureV1.wrongWorkspace
        }
        return try C20PrivacyProjectionBridgeV1.requireAllowed(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: now
        )
    }
}

extension RequirementBasisBindingV1 {
    /// Stable C40 criterion identity consumed by C13 assurance links. This is
    /// a reference only and does not reinterpret the authority or criterion.
    var assuranceCriterionID: String { criterionID }
}

extension RequirementBasisBindingV1 {
    func inspectionReviewItemReference() throws -> ChangeRequestItemReferenceV1 {
        try validate()
        return try .init(kind: .criterion, itemID: criterionID,
                         itemRevision: revision, itemSHA256: bindingSHA256)
    }
}

extension FindingClassificationBindingV1 {
    var assuranceCriterionID: String { criterionID }
    var assuranceClaimID: String {
        "finding:\(findingID.uuidString.lowercased()):classification:\(revision)"
    }
}

// MARK: - C19 measurement protocol bindings

extension MeasurementProtocolReleaseV1 {
    /// Binds a local capture to the immutable protocol release. Unit
    /// conversion remains owned by the exact-measurement kernel; this seam
    /// checks only the protocol's dimension, canonical unit, and uncertainty
    /// requirement.
    func c19ValidateCapture(_ capture: MeasurementCaptureV1) throws {
        try validate()
        try capture.validate()
        let normativeUnit = try KernelUnitRegistryV1.definition(unitID: normativeUnitID)
        guard capture.workspaceID == workspaceID,
              capture.measurement.dimension == dimension,
              capture.measurement.canonicalUnitID == normativeUnit.canonicalUnitID,
              !requiresUncertainty || capture.measurement.uncertaintyCanonical != nil else {
            throw MeasurementIntegrityFailureV1.staleReference
        }
    }

    /// Verifies the ordered capture references and immutable protocol
    /// identity before a series is projected or finalized.
    func c19ValidateSeries(
        _ series: MeasurementSeriesV1,
        captures: [MeasurementCaptureV1]
    ) throws {
        try validate()
        try series.validateClosure(captures: captures, protocolRelease: self)
        guard series.workspaceID == workspaceID,
              series.protocolReference.releaseID == releaseID,
              series.protocolReference.revision == revision,
              series.protocolReference.releaseSHA256 == releaseSHA256,
              series.expectedSampleCount >= minimumSampleCount,
              series.expectedSampleCount <= maximumSampleCount else {
            throw MeasurementIntegrityFailureV1.staleReference
        }
        if samplingPolicy == .single {
            guard series.expectedSampleCount == 1 else {
                throw MeasurementIntegrityFailureV1.incompleteSeries
            }
        }
    }
}

enum C53SharedAuthorityCriterionBoundaryV1 {
    static let subjectType: ServiceReliabilitySubjectV1.Type = ServiceReliabilitySubjectV1.self
    static let intervalType: ServiceReliabilityClosedIntervalV1.Type = ServiceReliabilityClosedIntervalV1.self
    static let reliabilityInputsBindToFrozenSubjectContext = true
    static let causeAndRestorationAreRecordedProvenance = true
    static let verifiedIdentityOrResponsibilityIsInferred = false
    static let releaseToServiceOrComplianceIsInferred = false
    static let metricOutputIsOwnedByDownstreamProjection = true
    static let sourceContractNames = C53SharedServiceReliabilitySemanticBoundaryV1.contractNames
}
