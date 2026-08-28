import Foundation

struct ReportSemanticNodeV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let semanticID: String
    let sectionID: String
    let role: String
    let label: String
    let value: String
    let outputReferenceID: String?

    static func < (lhs: ReportSemanticNodeV1, rhs: ReportSemanticNodeV1) -> Bool {
        lhs.semanticID < rhs.semanticID
    }

    init(
        semanticID: String,
        sectionID: String,
        role: String,
        label: String,
        value: String,
        outputReferenceID: String? = nil
    ) throws {
        guard [semanticID, sectionID, role].allSatisfy(SnapshotProjectionValidationV1.validID),
              SnapshotProjectionValidationV1.validText(label),
              SnapshotProjectionValidationV1.validText(value),
              outputReferenceID.map(SnapshotProjectionValidationV1.validID) ?? true else {
            throw SnapshotProjectionFailureV1.hostileText
        }
        self.semanticID = semanticID
        self.sectionID = sectionID
        self.role = role
        self.label = label
        self.value = value
        self.outputReferenceID = outputReferenceID
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case semanticID, sectionID, role, label, value, outputReferenceID
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            semanticID: values.decode(String.self, forKey: .semanticID),
            sectionID: values.decode(String.self, forKey: .sectionID),
            role: values.decode(String.self, forKey: .role),
            label: values.decode(String.self, forKey: .label),
            value: values.decode(String.self, forKey: .value),
            outputReferenceID: ClosedContractDecodingV1.decodeOptional(
                String.self, from: values, forKey: .outputReferenceID
            )
        )
    }
}

struct ReportSemanticProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let projectionVersion: String
    let snapshotID: String
    let snapshotSHA256: String
    let manifestSHA256: String
    let profileBindingSHA256: String
    let nodes: [ReportSemanticNodeV1]
    let semanticSHA256: String

    private struct DigestPayload: Codable {
        let projectionVersion: String
        let snapshotID: String
        let snapshotSHA256: String
        let manifestSHA256: String
        let profileBindingSHA256: String
        let nodes: [ReportSemanticNodeV1]
    }

    init(
        projectionVersion: String,
        snapshotID: String,
        snapshotSHA256: String,
        manifestSHA256: String,
        profileBindingSHA256: String,
        nodes: [ReportSemanticNodeV1]
    ) throws {
        guard SnapshotProjectionValidationV1.validID(projectionVersion),
              SnapshotProjectionValidationV1.validID(snapshotID),
              [snapshotSHA256, manifestSHA256, profileBindingSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),
              !nodes.isEmpty, nodes == nodes.sorted(), Set(nodes.map(\.semanticID)).count == nodes.count else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        let payload = DigestPayload(
            projectionVersion: projectionVersion,
            snapshotID: snapshotID,
            snapshotSHA256: snapshotSHA256,
            manifestSHA256: manifestSHA256,
            profileBindingSHA256: profileBindingSHA256,
            nodes: nodes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(payload)
        schemaVersion = Self.schemaVersion
        self.projectionVersion = projectionVersion
        self.snapshotID = snapshotID
        self.snapshotSHA256 = snapshotSHA256
        self.manifestSHA256 = manifestSHA256
        self.profileBindingSHA256 = profileBindingSHA256
        self.nodes = nodes
        semanticSHA256 = KernelCanonicalHashV1.sha256(bytes)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, projectionVersion, snapshotID, snapshotSHA256
        case manifestSHA256, profileBindingSHA256, nodes, semanticSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        let claimedDigest = try values.decode(String.self, forKey: .semanticSHA256)
        let rebuilt = try Self(
            projectionVersion: values.decode(String.self, forKey: .projectionVersion),
            snapshotID: values.decode(String.self, forKey: .snapshotID),
            snapshotSHA256: values.decode(String.self, forKey: .snapshotSHA256),
            manifestSHA256: values.decode(String.self, forKey: .manifestSHA256),
            profileBindingSHA256: values.decode(String.self, forKey: .profileBindingSHA256),
            nodes: values.decode([ReportSemanticNodeV1].self, forKey: .nodes)
        )
        guard claimedDigest == rebuilt.semanticSHA256 else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        self = rebuilt
    }

    func recursivelyValidated() throws -> ReportSemanticProjectionV1 {
        let rebuiltNodes = try nodes.map {
            try ReportSemanticNodeV1(
                semanticID: $0.semanticID,
                sectionID: $0.sectionID,
                role: $0.role,
                label: $0.label,
                value: $0.value,
                outputReferenceID: $0.outputReferenceID
            )
        }
        let rebuilt = try Self(
            projectionVersion: projectionVersion,
            snapshotID: snapshotID,
            snapshotSHA256: snapshotSHA256,
            manifestSHA256: manifestSHA256,
            profileBindingSHA256: profileBindingSHA256,
            nodes: rebuiltNodes
        )
        guard schemaVersion == Self.schemaVersion, semanticSHA256 == rebuilt.semanticSHA256 else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        return rebuilt
    }
}

struct ReportProjectionOutputV1: Equatable, Sendable {
    let format: ReportProjectionFormatV1
    let data: Data
    let sha256: String
    let semanticSHA256: String
    let orderedSemanticIDs: [String]
    let taggedPDFAccessibilityEvidence: Bool
}

enum ReportSemanticProjectorV1 {
    static let rendererVersion = "report-semantic-projector-v1"

    static func project(
        snapshot: CompletedActivitySnapshotV1,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        try project(
            activity: snapshot.payload,
            snapshotSHA256: snapshot.snapshotSHA256,
            locationComposition: nil,
            manifest: manifest
        )
    }

    static func project(
        snapshot: CompletedActivitySnapshotV2,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        try project(
            activity: snapshot.payload.activity,
            snapshotSHA256: snapshot.snapshotSHA256,
            locationComposition: snapshot.payload.locationComposition,
            accountability: nil,
            manifest: manifest
        )
    }

    static func project(
        snapshot: CompletedActivitySnapshotV3,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        try project(
            activity: snapshot.payload.activity.activity,
            snapshotSHA256: snapshot.snapshotSHA256,
            locationComposition: snapshot.payload.activity.locationComposition,
            accountability: snapshot.payload.accountability,
            manifest: manifest
        )
    }

    static func project(
        snapshot: CompletedActivitySnapshotV4,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        try project(
            activity: snapshot.payload.activity.activity.activity,
            snapshotSHA256: snapshot.snapshotSHA256,
            locationComposition: snapshot.payload.activity.activity.locationComposition,
            accountability: snapshot.payload.activity.accountability,
            assetSemantics: snapshot.payload.assetSemantics,
            manifest: manifest
        )
    }

    static func project(
        snapshot: CompletedActivitySnapshotV5,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        try project(
            activity: snapshot.payload.activity.activity.activity.activity,
            snapshotSHA256: snapshot.snapshotSHA256,
            locationComposition: snapshot.payload.activity.activity.activity.locationComposition,
            accountability: snapshot.payload.activity.activity.accountability,
            assetSemantics: snapshot.payload.activity.assetSemantics,
            authorityCriterion: snapshot.payload.authorityCriterion,
            manifest: manifest
        )
    }

    static func project(
        snapshot: CompletedActivitySnapshotV6,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        try project(
            activity: snapshot.payload.activity.activity.activity.activity.activity,
            snapshotSHA256: snapshot.snapshotSHA256,
            locationComposition: snapshot.payload.activity.activity.activity.activity.locationComposition,
            accountability: snapshot.payload.activity.activity.activity.accountability,
            assetSemantics: snapshot.payload.activity.activity.assetSemantics,
            authorityCriterion: snapshot.payload.activity.authorityCriterion,
            functionalRelationships: snapshot.payload.functionalRelationships,
            manifest: manifest
        )
    }

    /// C13's additive report boundary. The inner V6 digest is the immutable
    /// source bound by the preview; the outer V7 digest remains the encoded
    /// completed-snapshot identity exposed by the semantic projection.
    static func project(
        snapshot: CompletedActivitySnapshotV7,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        let activity = snapshot.payload.activity
        return try project(
            activity: activity.payload.activity.activity.activity.activity.activity,
            snapshotSHA256: snapshot.snapshotSHA256,
            locationComposition: activity.payload.activity.activity.activity.activity.locationComposition,
            accountability: activity.payload.activity.activity.activity.accountability,
            assetSemantics: activity.payload.activity.activity.assetSemantics,
            authorityCriterion: activity.payload.activity.authorityCriterion,
            functionalRelationships: activity.payload.functionalRelationships,
            assurance: snapshot.payload.assurance,
            assuranceSnapshotSHA256: activity.snapshotSHA256,
            manifest: manifest
        )
    }

    /// C14's additive report boundary. The complete review/change/action
    /// history remains frozen in V8; the semantic renderer emits only typed
    /// states, revisions/identities, and digests so actor/private detail and
    /// unverified claims cannot enter open JSON or structured text.
    static func project(
        snapshot: CompletedActivitySnapshotV8,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        let v7 = snapshot.payload.activity
        let v6 = v7.payload.activity
        return try project(
            activity: v6.payload.activity.activity.activity.activity.activity,
            snapshotSHA256: snapshot.snapshotSHA256,
            locationComposition: v6.payload.activity.activity.activity.activity.locationComposition,
            accountability: v6.payload.activity.activity.activity.accountability,
            assetSemantics: v6.payload.activity.assetSemantics,
            authorityCriterion: v6.payload.authorityCriterion,
            functionalRelationships: v6.payload.functionalRelationships,
            assurance: v7.payload.assurance,
            assuranceSnapshotSHA256: v6.snapshotSHA256,
            inspectionReviewHistory: snapshot.payload.inspectionReviewHistory,
            manifest: manifest
        )
    }

    private static func project(
        activity: CompletedActivitySnapshotPayloadV1,
        snapshotSHA256: String,
        locationComposition: CompletedLocationCompositionSnapshotV1?,
        accountability: CompletedAccountabilitySnapshotV1? = nil,
        assetSemantics: CompletedAssetSemanticsSnapshotV1? = nil,
        authorityCriterion: CompletedAuthorityCriterionSnapshotV1? = nil,
        functionalRelationships: CompletedFunctionalRelationshipSnapshotV1? = nil,
        assurance: ReportEvidenceAssuranceProjectionV1? = nil,
        assuranceSnapshotSHA256: String? = nil,
        inspectionReviewHistory: CompletedInspectionReviewHistorySnapshotV1? = nil,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestBytes = try encoder.encode(manifest)
        let bindingBytes = try encoder.encode(activity.profileBinding)
        let binding = activity.profileBinding
        typealias DraftNode = (section: String, role: String, label: String, value: String, referenceID: String?)
        var drafts: [DraftNode] = []

        func append(_ section: String, _ role: String, _ label: String, _ value: String, _ ref: String? = nil) throws {
            guard binding.sectionIDs.contains(section) else { return }
            guard SnapshotProjectionValidationV1.validID(section),
                  SnapshotProjectionValidationV1.validID(role),
                  SnapshotProjectionValidationV1.validText(label),
                  SnapshotProjectionValidationV1.validText(value),
                  ref.map(SnapshotProjectionValidationV1.validID) ?? true else {
                throw SnapshotProjectionFailureV1.hostileText
            }
            drafts.append((section, role, label, value, ref))
        }

        func visibleID(_ kind: String, _ value: String) -> String {
            guard binding.audience == .customerSafe else { return value }
            let hash = KernelCanonicalHashV1.sha256(Data("\(binding.outputScopeID)|\(kind)|\(value)".utf8))
            return "out-\(kind)-\(hash.prefix(16))"
        }

        func visibleDigest(_ kind: String, _ value: String) -> String {
            guard binding.audience == .customerSafe else { return value }
            return KernelCanonicalHashV1.sha256(Data("\(binding.outputScopeID)|\(kind)|\(value)".utf8))
        }

        try append("identity", "heading", "Report", visibleID("report", activity.reportID))
        try append("identity", "fact", "Snapshot", visibleID("snapshot", activity.snapshotID))
        try append("identity", "fact", "Snapshot revision", String(activity.snapshotRevision))
        try append("identity", "fact", "Package release", visibleID("package", activity.packageReleaseID))
        try append("identity", "fact", "Projection version", binding.projectionVersion)
        try append("identity", "fact", "Generated", activity.generatedAt)
        try append("identity", "fact", "Completed", activity.completedAt)
        if let locationComposition {
            let path = ([locationComposition.locationPath.siteDisplay]
                + locationComposition.locationPath.nodes.map(\.label)).joined(separator: " / ")
            try append("identity", "fact", "Completed location", path)
            try append(
                "identity", "digest", "Location and composition snapshot SHA-256",
                visibleDigest("location-composition-digest", locationComposition.snapshotSHA256)
            )
            for edge in locationComposition.compositionEdges {
                try append(
                    "service", "composition", "Component relationship",
                    "\(visibleID("asset", edge.childAssetID.uuidString.lowercased())) component of \(visibleID("asset", edge.parentAssetID.uuidString.lowercased()))"
                )
            }
        }
        if let accountability {
            try appendAccountability(
                accountability,
                binding: binding,
                append: append,
                visibleID: visibleID
            )
        }
        if let assetSemantics {
            try appendAssetSemantics(
                assetSemantics,
                binding: binding,
                append: append,
                visibleID: visibleID
            )
        }
        if let authorityCriterion {
            try appendAuthorityCriterion(
                authorityCriterion,
                append: append,
                visibleID: visibleID,
                visibleDigest: visibleDigest
            )
        }
        if let functionalRelationships {
            try appendFunctionalRelationships(
                functionalRelationships,
                binding: binding,
                append: append,
                visibleID: visibleID,
                visibleDigest: visibleDigest
            )
        }
        if let assurance {
            try appendAssurance(
                assurance,
                binding: binding,
                expectedSnapshotSHA256: assuranceSnapshotSHA256,
                append: append,
                visibleID: visibleID,
                visibleDigest: visibleDigest
            )
        }
        if let inspectionReviewHistory {
            try appendInspectionReviewHistory(
                inspectionReviewHistory,
                binding: binding,
                append: append,
                visibleID: visibleID,
                visibleDigest: visibleDigest
            )
        }
        for fact in activity.serviceFacts where binding.audience == .internalUse || fact.privacyClass != .internalOnly {
            try append("service", "fact", fact.label, fact.value)
        }
        var assuranceLinksByEvidenceID: [String: ClaimEvidenceLinkV1] = [:]
        if let assurance {
            for link in assurance.preview.includedLinks + assurance.preview.excludedLinks {
                guard let evidenceID = link.evidenceID else { continue }
                guard assuranceLinksByEvidenceID[evidenceID] == nil else {
                    throw SnapshotProjectionFailureV1.duplicateIdentity
                }
                assuranceLinksByEvidenceID[evidenceID] = link
            }
        }
        for card in activity.evidenceCards {
            if let assurance {
                guard let link = assuranceLinksByEvidenceID[card.evidenceID],
                      link.decision.disposition == .included else {
                    let limitation = assuranceLinksByEvidenceID[card.evidenceID]?
                        .decision.limitation.rawValue ?? EvidenceLimitationV1.evidenceUnavailable.rawValue
                    try append(
                        "evidence", "omitted", "Evidence omitted",
                        "Evidence omitted: \(limitation)"
                    )
                    try append(
                        "limitations", "limitation", "Evidence limitation",
                        "Evidence omitted: \(limitation)"
                    )
                    continue
                }
                try EvidenceDetailAssuranceProjectionGuardV1.validateIncludedCard(
                    card, link: link,
                    audience: assurance.audience
                )
            }
            try append("evidence", "heading", "Evidence", visibleID("evidence", card.cardID))
            for field in card.fields {
                try append("evidence", "fact", field.label, field.value)
            }
            for reference in card.outputReferences {
                try append("evidence", "media", "Output reference", reference.outputReferenceID, reference.outputReferenceID)
            }
            for annotation in card.annotations {
                try append("evidence", "annotation", "Reviewed annotation", annotation)
            }
            try append("limitations", "limitation", "Evidence limitation", card.limitationsText)
        }
        for limitation in activity.limitations {
            try append("limitations", "limitation", "Limitation", limitation)
        }
        try append(
            "provenance",
            "digest",
            binding.audience == .customerSafe ? "Output-scoped snapshot digest" : "Snapshot SHA-256",
            visibleDigest("snapshot-digest", snapshotSHA256)
        )
        if let superseded = activity.supersedesSnapshotID {
            try append("supersession", "fact", "Supersedes snapshot", visibleID("snapshot", superseded))
        } else {
            try append("supersession", "fact", "Supersession", "Original immutable snapshot")
        }
        try append("manifest", "digest", "Contract manifest SHA-256", KernelCanonicalHashV1.sha256(manifestBytes))

        let sectionOrder = Dictionary(uniqueKeysWithValues: binding.sectionIDs.enumerated().map { ($1, $0) })
        let orderedDrafts = drafts.enumerated().sorted { lhs, rhs in
            let leftOrder = sectionOrder[lhs.element.section] ?? Int.max
            let rightOrder = sectionOrder[rhs.element.section] ?? Int.max
            return leftOrder == rightOrder ? lhs.offset < rhs.offset : leftOrder < rightOrder
        }.map { $0.element }
        let nodes = try orderedDrafts.enumerated().map { index, draft in
            try ReportSemanticNodeV1(
                semanticID: "node-\(String(format: "%05d", index))",
                sectionID: draft.section,
                role: draft.role,
                label: draft.label,
                value: draft.value,
                outputReferenceID: draft.referenceID
            )
        }
        guard manifest.reportSectionRegistry.requiredSectionIDs.isSubset(of: Set(nodes.map(\.sectionID))) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }

        return try ReportSemanticProjectionV1(
            projectionVersion: activity.profileBinding.projectionVersion,
            snapshotID: visibleID("snapshot", activity.snapshotID),
            snapshotSHA256: visibleDigest("snapshot-digest", snapshotSHA256),
            manifestSHA256: KernelCanonicalHashV1.sha256(manifestBytes),
            profileBindingSHA256: visibleDigest(
                "profile-binding-digest",
                KernelCanonicalHashV1.sha256(bindingBytes)
            ),
            nodes: nodes
        )
    }

    private static func appendAuthorityCriterion(
        _ snapshot: CompletedAuthorityCriterionSnapshotV1,
        append: (_ section: String, _ role: String, _ label: String, _ value: String, _ ref: String?) throws -> Void,
        visibleID: (_ kind: String, _ value: String) -> String,
        visibleDigest: (_ kind: String, _ value: String) -> String
    ) throws {
        let section = ReportAuthorityCriterionProjectionPolicyV1.sectionID
        let facts = snapshot.aggregate
        let heading = try localizedAuthorityCriterion(.heading)
        let authoritySource = try localizedAuthorityCriterion(.authoritySource)
        let applicability = try localizedAuthorityCriterion(.applicability)
        let criterionResult = try localizedAuthorityCriterion(.criterionResult)
        let severity = try localizedAuthorityCriterion(.severity)
        let measurementProtocol = try localizedAuthorityCriterion(.measurementProtocol)
        let technicalBasis = try localizedAuthorityCriterion(.technicalBasis)
        let nextStep = try localizedAuthorityCriterion(.nextStep)
        let assessedAgainst = try localizedAuthorityCriterion(.assessedAgainst)

        let projectedText = facts.sourceReleases.flatMap {
            [$0.designation, $0.editionOrRevision, $0.publisherDisplay].compactMap { $0 }
        }
            + facts.applicabilityContexts.compactMap(\.dispositionReason)
            + facts.classificationBindings.flatMap { [$0.criterionID, $0.severityLevelID].compactMap { $0 } }
            + facts.measurementProtocolReleases.flatMap { [$0.designation, $0.normativeUnitID] }
        guard !AuthorityCriterionClaimVocabularyV1.containsProhibitedClaim(in: projectedText),
              !AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(in: projectedText) else {
            throw SnapshotProjectionFailureV1.hostileText
        }

        try append(section, "heading", heading, assessedAgainst, nil)
        for source in facts.sourceReleases {
            let metadata = [source.designation, source.editionOrRevision, source.publisherDisplay]
                .compactMap { $0 }.joined(separator: " — ")
            try append(section, "fact", authoritySource, metadata,
                       visibleID("authority-release", source.releaseID.uuidString.lowercased()))
            try append(section, "digest", technicalBasis,
                       visibleDigest("authority-release-digest", source.releaseSHA256), nil)
        }
        for context in facts.applicabilityContexts {
            let disposition = try localizedAuthorityCriterion(
                ReportAuthorityCriterionProjectionPolicyV1.applicabilityLocalizationKey(context.disposition)
            )
            try append(section, "fact", applicability, disposition,
                       visibleID("applicability", context.snapshotID.uuidString.lowercased()))
            if let reason = context.dispositionReason {
                try append(section, "limitation", nextStep, reason, nil)
            }
        }
        for classification in facts.classificationBindings {
            let result = try localizedAuthorityCriterion(
                ReportAuthorityCriterionProjectionPolicyV1.resultLocalizationKey(classification.result)
            )
            try append(section, "fact", criterionResult, result,
                       visibleID("classification", classification.bindingID.uuidString.lowercased()))
            try append(section, "fact", technicalBasis, classification.criterionID, nil)
            if let level = classification.severityLevelID {
                try append(section, "fact", severity, level, nil)
            }
        }
        for measurement in facts.measurementProtocolReleases {
            try append(section, "fact", measurementProtocol,
                       "\(measurement.designation) — \(measurement.normativeUnitID)",
                       visibleID("measurement-protocol", measurement.releaseID.uuidString.lowercased()))
        }
        for fact in facts.derivedFacts {
            // Derived-fact dispositions have no C40 shipping label. Preserve
            // the provenance digest while withholding the raw enum token.
            try append(section, "digest", technicalBasis,
                       visibleDigest("derived-fact-digest", fact.provenanceSHA256), nil)
        }
    }

    private static func localizedAuthorityCriterion(
        _ key: AuthorityCriterionLocalizationKeyV1
    ) throws -> String {
        guard let bundledKey = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        return BundledLocalizationCatalogV1.localized(bundledKey)
    }

    /// Resolve through the typed C41 key enum and the repository's bundled
    /// catalog. The raw-value fallback is unreachable for the closed catalog
    /// but keeps this pre-S10 renderer fail-closed and deterministic if a
    /// future catalog omits a key.
    private static func localizedFunctionalRelationship(
        _ key: FunctionalRelationshipLocalizationKeyV1
    ) -> String {
        guard let bundledKey = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
            return key.rawValue
        }
        return BundledLocalizationCatalogV1.localized(bundledKey)
    }

    private static func appendAssurance(
        _ assurance: ReportEvidenceAssuranceProjectionV1,
        binding: FinalizedReportProfileBindingV1,
        expectedSnapshotSHA256: String?,
        append: (
            _ section: String,
            _ role: String,
            _ label: String,
            _ value: String,
            _ ref: String?
        ) throws -> Void,
        visibleID: (_ kind: String, _ value: String) -> String,
        visibleDigest: (_ kind: String, _ value: String) -> String
    ) throws {
        let section = ReportEvidenceAssuranceProjectionPolicyV1.sectionID
        guard binding.sectionIDs.contains(section),
              let expectedAudience = ReportEvidenceAssuranceProjectionPolicyV1
                .evidenceAudience(for: binding.audience) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        try assurance.validate(
            expectedSnapshotSHA256: expectedSnapshotSHA256,
            expectedProjectionVersion: binding.projectionVersion,
            expectedAudience: expectedAudience
        )

        try append(section, "heading", "Evidence assurance", "Evidence assurance", nil)
        try append(
            section,
            "status",
            "Publication status",
            ReportEvidenceAssuranceProjectionPolicyV1.publicationDisposition,
            nil
        )
        try append(section, "fact", "Projection version", assurance.projectionVersion, nil)
        try append(
            section,
            "fact",
            "Included evidence",
            String(assurance.preview.includedLinks.count),
            nil
        )
        try append(
            section,
            "fact",
            "Excluded evidence",
            String(assurance.preview.excludedLinks.count),
            nil
        )
        try append(
            section,
            "digest",
            "Preview SHA-256",
            visibleDigest("assurance-preview", assurance.preview.previewSHA256),
            visibleID("assurance-preview", assurance.preview.previewID.uuidString.lowercased())
        )
        if let manifest = assurance.manifest {
            try append(
                section,
                "digest",
                "Manifest SHA-256",
                visibleDigest("assurance-manifest", manifest.manifestSHA256),
                visibleID("assurance-manifest", manifest.manifestID.uuidString.lowercased())
            )
            try append(section, "fact", "Attestations", String(assurance.attestations.count), nil)
        }
        for link in assurance.preview.includedLinks {
            guard let evidenceID = link.evidenceID else {
                throw SnapshotProjectionFailureV1.missingBinding
            }
            try append(
                section,
                "included",
                "Included evidence",
                visibleID("assurance-evidence", evidenceID),
                visibleID("assurance-link", link.linkID.uuidString.lowercased())
            )
        }
        for link in assurance.preview.excludedLinks {
            try append(
                section,
                "omitted",
                "Evidence omitted",
                EvidenceDetailAssuranceProjectionGuardV1.omissionLabel(for: link),
                nil
            )
        }
    }

    private static func appendInspectionReviewHistory(
        _ history: CompletedInspectionReviewHistorySnapshotV1,
        binding: FinalizedReportProfileBindingV1,
        append: (
            _ section: String,
            _ role: String,
            _ label: String,
            _ value: String,
            _ ref: String?
        ) throws -> Void,
        visibleID: (_ kind: String, _ value: String) -> String,
        visibleDigest: (_ kind: String, _ value: String) -> String
    ) throws {
        try history.validate()
        let section = ReportInspectionReviewHistoryProjectionPolicyV1.sectionID
        guard binding.sectionIDs.contains(section) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        let projection = try ReportInspectionReviewHistoryProjectionV1(history: history)
        try append(section, "heading", "Review and change history", "Review and change history", nil)
        try append(section, "fact", "Review transitions", String(projection.reviewTransitionIDs.count), nil)
        try append(section, "fact", "Review dispositions", String(projection.reviewDispositionIDs.count), nil)
        try append(section, "fact", "Change requests", String(projection.changeRequestRevisionIDs.count), nil)
        try append(section, "fact", "Corrective actions", String(projection.actionEventIDs.count), nil)
        try append(
            section,
            "digest",
            "Completed snapshot SHA-256",
            visibleDigest("review-source-snapshot", history.sourceSnapshotSHA256),
            nil
        )
        try append(
            section,
            "digest",
            "History snapshot SHA-256",
            visibleDigest("review-history-snapshot", history.snapshotSHA256),
            nil
        )
        try append(
            section,
            "digest",
            "History binding SHA-256",
            visibleDigest("review-history-binding", projection.bindingSHA256),
            nil
        )
        for (id, state) in zip(projection.reviewTransitionIDs, projection.reviewStateLabels) {
            try append(section, "state", "Review state", state, visibleID("review-transition", id))
        }
        for (id, state) in zip(projection.reviewDispositionIDs, projection.reviewDispositionLabels) {
            try append(section, "state", "Review disposition", state, visibleID("review-disposition", id))
        }
        for (id, state) in zip(projection.changeRequestRevisionIDs, projection.changeStateLabels) {
            try append(section, "state", "Change request state", state, visibleID("change-request", id))
        }
        for (id, state) in zip(projection.actionEventIDs, projection.actionStateLabels) {
            try append(section, "state", "Corrective action state", state, visibleID("corrective-action", id))
        }
    }

    private static func appendFunctionalRelationships(
        _ snapshot: CompletedFunctionalRelationshipSnapshotV1,
        binding: FinalizedReportProfileBindingV1,
        append: (
            _ section: String,
            _ role: String,
            _ label: String,
            _ value: String,
            _ ref: String?
        ) throws -> Void,
        visibleID: (_ kind: String, _ value: String) -> String,
        visibleDigest: (_ kind: String, _ value: String) -> String
    ) throws {
        try snapshot.validate()
        let sectionID = ReportFunctionalRelationshipsProjectionPolicyV1.sectionID
        let heading = localizedFunctionalRelationship(.heading)
        let descriptorLabel = localizedFunctionalRelationship(.descriptor)
        let typeLabel = localizedFunctionalRelationship(.type)
        let boundsLabel = localizedFunctionalRelationship(.bounds)
        let siteLabel = localizedFunctionalRelationship(.site)
        let stateLabel = localizedFunctionalRelationship(.activeState)
        let projectedValues = snapshot.descriptorReleases.flatMap { descriptor in
            [descriptor.semanticID, descriptor.displayNameLocalizationKey,
             descriptor.sourceRoleLocalizationKey, descriptor.targetRoleLocalizationKey]
        } + snapshot.relationships.flatMap { event in
            [event.action.rawValue, event.provenance]
        }
        guard !FunctionalRelationshipClaimVocabularyV1.containsProhibitedClaim(in: projectedValues),
              !AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(in: projectedValues) else {
            throw SnapshotProjectionFailureV1.hostileText
        }

        try append(sectionID, "heading", heading, heading, nil)
        try append(
            sectionID,
            "digest",
            descriptorLabel,
            visibleDigest("functional-relationship-snapshot", snapshot.snapshotSHA256),
            nil
        )
        let descriptors = Dictionary(uniqueKeysWithValues: snapshot.descriptorReleases.map {
            ($0.descriptorReleaseID, $0)
        })
        for descriptor in snapshot.descriptorReleases.sorted(by: {
            ($0.semanticID, $0.descriptorReleaseID.uuidString)
                < ($1.semanticID, $1.descriptorReleaseID.uuidString)
        }) {
            let releaseID = visibleID("functional-descriptor", descriptor.descriptorReleaseID.uuidString.lowercased())
            let directionKey = ReportFunctionalRelationshipsProjectionPolicyV1.directionLocalizationKey(
                descriptor.direction
            )
            let symmetryKey = ReportFunctionalRelationshipsProjectionPolicyV1.symmetryLocalizationKey(
                descriptor.symmetry
            )
            let siteKey = ReportFunctionalRelationshipsProjectionPolicyV1.siteLocalizationKey(
                descriptor.sitePolicy
            )
            try append(sectionID, "heading", typeLabel, descriptor.semanticID, releaseID)
            try append(sectionID, "fact", typeLabel, localizedFunctionalRelationship(directionKey), nil)
            if descriptor.symmetry == .symmetric {
                try append(sectionID, "fact", typeLabel, localizedFunctionalRelationship(symmetryKey), nil)
            }
            try append(
                sectionID,
                "fact",
                boundsLabel,
                "source \(descriptor.sourceCardinality.minimum)…\(descriptor.sourceCardinality.maximum); target \(descriptor.targetCardinality.minimum)…\(descriptor.targetCardinality.maximum)",
                nil
            )
            try append(sectionID, "fact", siteLabel, localizedFunctionalRelationship(siteKey), nil)
            try append(
                sectionID,
                "digest",
                descriptorLabel,
                visibleDigest("functional-descriptor", descriptor.descriptorSHA256),
                releaseID
            )
        }
        for event in snapshot.relationships.sorted(by: {
            ($0.relationshipID.uuidString, $0.revision) < ($1.relationshipID.uuidString, $1.revision)
        }) {
            guard let descriptor = descriptors[event.descriptor.descriptorReleaseID],
                  descriptor.descriptorSHA256 == event.descriptor.descriptorSHA256 else {
                throw SnapshotProjectionFailureV1.digestMismatch
            }
            let relationshipID = visibleID("functional-relationship", event.relationshipID.uuidString.lowercased())
            let state = localizedFunctionalRelationship(
                ReportFunctionalRelationshipsProjectionPolicyV1.eventStateLocalizationKey(event.action)
            )
            let direction = localizedFunctionalRelationship(
                ReportFunctionalRelationshipsProjectionPolicyV1.directionLocalizationKey(descriptor.direction)
            )
            let endpoints = "\(visibleID("asset", event.sourceAssetID.uuidString.lowercased())) → \(visibleID("asset", event.targetAssetID.uuidString.lowercased()))"
            try append(sectionID, "fact", descriptorLabel, descriptor.semanticID, relationshipID)
            try append(sectionID, "status", stateLabel, "\(state) · \(direction)", nil)
            try append(sectionID, "fact", typeLabel, endpoints, nil)
            try append(
                sectionID,
                "digest",
                descriptorLabel,
                visibleDigest("functional-event", event.eventSHA256),
                relationshipID
            )
        }
    }

    private static func appendAssetSemantics(
        _ semantics: CompletedAssetSemanticsSnapshotV1,
        binding: FinalizedReportProfileBindingV1,
        append: (
            _ section: String,
            _ role: String,
            _ label: String,
            _ value: String,
            _ ref: String?
        ) throws -> Void,
        visibleID: (_ kind: String, _ value: String) -> String
    ) throws {
        let sectionID = ReportAssetSemanticsProjectionPolicyV1.sectionID
        try append(
            sectionID,
            "heading",
            BundledLocalizationCatalogV1.localized(.assetSemanticHeading),
            BundledLocalizationCatalogV1.localized(.assetSemanticHeading)
        )
        for bindingValue in semantics.kindBindings {
            try append(
                sectionID,
                "fact",
                BundledLocalizationCatalogV1.localized(.assetSemanticKind),
                bindingValue.semanticID,
                visibleID("asset-kind", bindingValue.eventID.uuidString.lowercased())
            )
        }
        for capabilityBinding in semantics.workflowCapabilityBindings {
            let capabilities = capabilityBinding.capabilityIDs.map(\.rawValue).joined(separator: " ")
            if !capabilities.isEmpty {
                try append(
                    sectionID,
                    "fact",
                    BundledLocalizationCatalogV1.localized(.assetSemanticKind),
                    capabilities,
                    visibleID("asset-capability", capabilityBinding.eventID.uuidString.lowercased())
                )
            }
        }
        for identity in semantics.productIdentities {
            for identifier in identity.identifiers {
                let state: String
                switch identifier.reviewState {
                case .unknownRecorded:
                    state = BundledLocalizationCatalogV1.localized(.assetSemanticUnknownState)
                case .duplicateRecorded:
                    state = BundledLocalizationCatalogV1.localized(.assetSemanticDuplicateState)
                case .reviewedAsRecorded, .unreviewed:
                    state = BundledLocalizationCatalogV1.localized(.assetSemanticRecordedState)
                }
                // Product identifier values and issuers are deliberately
                // omitted from this audience-safe projection.
                try append(
                    sectionID,
                    "status",
                    BundledLocalizationCatalogV1.localized(.assetSemanticProductIdentity),
                    "\(identifier.kind.rawValue): \(state)",
                    visibleID("product-identity", identity.identityID.uuidString.lowercased())
                )
            }
        }
        for event in semantics.lifecycleEvents {
            let state: String
            switch event.kind {
            case .retiredRecorded:
                state = BundledLocalizationCatalogV1.localized(.assetSemanticRetiredState)
            case .replacedRecorded:
                state = BundledLocalizationCatalogV1.localized(.assetSemanticReplacedState)
            default:
                state = BundledLocalizationCatalogV1.localized(.assetSemanticRecordedState)
            }
            try append(
                sectionID,
                "fact",
                BundledLocalizationCatalogV1.localized(.assetSemanticLifecycle),
                "\(event.kind.rawValue): \(state)",
                visibleID("lifecycle", event.record.eventID.uuidString.lowercased())
            )
        }
        for link in semantics.successorLinks {
            try append(
                sectionID,
                "fact",
                BundledLocalizationCatalogV1.localized(.assetSemanticLifecycle),
                "\(visibleID("asset", link.predecessorAssetID.uuidString.lowercased())) -> \(visibleID("asset", link.successorAssetID.uuidString.lowercased()))",
                visibleID("successor-link", link.linkID.uuidString.lowercased())
            )
        }
        for scope in semantics.workSubjectScopes {
            let scopeID = visibleID("work-subject-scope", scope.snapshotID.uuidString.lowercased())
            try append(
                sectionID,
                "heading",
                BundledLocalizationCatalogV1.localized(.assetSemanticWorkSubjectScope),
                scopeID,
                scopeID
            )
            for subject in scope.subjects {
                try append(
                    sectionID,
                    "fact",
                    BundledLocalizationCatalogV1.localized(.assetSemanticWorkSubjectScope),
                    "\(subject.kind.rawValue): \(visibleID("subject", subject.subjectID.uuidString.lowercased()))"
                )
            }
            for semanticBinding in scope.semanticBindings {
                try append(
                    sectionID,
                    "fact",
                    BundledLocalizationCatalogV1.localized(.assetSemanticKind),
                    semanticBinding.semanticID,
                    visibleID("asset", semanticBinding.assetID.uuidString.lowercased())
                )
            }
        }
    }

    private static func appendAccountability(
        _ accountability: CompletedAccountabilitySnapshotV1,
        binding: FinalizedReportProfileBindingV1,
        append: (
            _ section: String,
            _ role: String,
            _ label: String,
            _ value: String,
            _ ref: String?
        ) throws -> Void,
        visibleID: (_ kind: String, _ value: String) -> String
    ) throws {
        let sectionID = ReportAccountabilityProjectionPolicyV1.sectionID
        try append(
            sectionID,
            "heading",
            BundledLocalizationCatalogV1.localized(.accountabilityHeading),
            BundledLocalizationCatalogV1.localized(.accountabilityHeading)
        )
        for party in accountability.parties {
            let partyID = visibleID("party", party.partyID.uuidString.lowercased())
            try append(sectionID, "heading", BundledLocalizationCatalogV1.localized(.accountabilityParty),
                       "\(partyID): \(party.displayName)", partyID)
            try append(sectionID, "fact", "Party kind", party.kind.rawValue)
            try append(sectionID, "fact", "Party provenance", party.provenance.rawValue)
            try append(sectionID, "status", "Party state", party.state.rawValue)
            if binding.audience == .internalUse, let descriptor = party.profileDescriptor {
                try append(sectionID, "fact", "Party context", descriptor)
            }
        }
        for event in accountability.roleEvents {
            let partyID = visibleID("party", event.partyID.uuidString.lowercased())
            let siteID = visibleID("site", event.siteID.uuidString.lowercased())
            try append(
                sectionID, "fact", BundledLocalizationCatalogV1.localized(.accountabilityRole),
                "\(partyID) \(event.role.rawValue) at \(siteID)"
            )
            try append(sectionID, "fact", "Role source", event.source.rawValue)
        }
        for actor in accountability.actors {
            let actorID = visibleID("actor", actor.snapshotID.uuidString.lowercased())
            try append(sectionID, "fact", BundledLocalizationCatalogV1.localized(.accountabilityActor),
                       actor.displayNameAtTime, actorID)
            try append(sectionID, "fact", "Responsibility", actor.responsibility.rawValue)
        }
        for qualification in accountability.qualifications {
            try append(sectionID, "fact", BundledLocalizationCatalogV1.localized(.accountabilityQualification),
                       qualification.declaredScope)
            try append(sectionID, "fact", "Qualification provenance", qualification.provenance.rawValue)
            if let issuer = qualification.issuerDisplay {
                try append(sectionID, "fact", "Qualification issuer", issuer)
            }
            if binding.audience == .internalUse, let locator = qualification.credentialLocator {
                try append(sectionID, "fact", "Credential reference", locator)
            }
        }
        for signoff in accountability.signoffs {
            let signoffID = visibleID("signoff", signoff.snapshotID.uuidString.lowercased())
            try append(sectionID, "heading", BundledLocalizationCatalogV1.localized(.accountabilitySignoff),
                       signoff.purpose, signoffID)
            try append(sectionID, "fact", "Response disposition", signoff.disposition.rawValue)
            try append(sectionID, "fact", "Response method", signoff.method.rawValue)
            if let role = signoff.roleAssertion {
                try append(sectionID, "fact", "Claimed role", role.claimedRole)
                if let relationship = role.claimedRelationship {
                    try append(sectionID, "fact", "Claimed relationship", relationship.rawValue)
                }
                try append(
                    sectionID, "annotation",
                    "Disclosure", role.disclosureRelease.disclosureText
                )
            }
        }
    }
}

enum DeterministicOpenJSONRendererV1 {
    static let rendererVersion = "open-json-renderer-v1"

    private static let structuredTextMagic = "ASSETROUNDS-STRUCTURED-REPORT-V1"
    private static let structuredTextEnd = "END-ASSETROUNDS-STRUCTURED-REPORT-V1"

    private struct StructuredTextHeader: Codable, Equatable {
        let projectionVersion: String
        let snapshotID: String
        let snapshotSHA256: String
        let manifestSHA256: String
        let profileBindingSHA256: String
        let semanticSHA256: String
    }

    private static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func reopen(_ data: Data) throws -> ReportSemanticProjectionV1 {
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let decoded = try JSONDecoder().decode(ReportSemanticProjectionV1.self, from: data)
        let validated = try decoded.recursivelyValidated()
        guard try canonicalEncoder().encode(validated) == data else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return validated
    }

    static func render(_ projection: ReportSemanticProjectionV1) throws -> ReportProjectionOutputV1 {
        let validated = try projection.recursivelyValidated()
        let encoder = canonicalEncoder()
        let data = try encoder.encode(validated)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let decoded = try reopen(data)
        guard decoded == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: projection.semanticSHA256,
            orderedSemanticIDs: projection.nodes.map(\.semanticID),
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func renderStructuredText(_ projection: ReportSemanticProjectionV1) throws -> ReportProjectionOutputV1 {
        let validated = try projection.recursivelyValidated()
        let encoder = canonicalEncoder()
        let header = StructuredTextHeader(
            projectionVersion: validated.projectionVersion,
            snapshotID: validated.snapshotID,
            snapshotSHA256: validated.snapshotSHA256,
            manifestSHA256: validated.manifestSHA256,
            profileBindingSHA256: validated.profileBindingSHA256,
            semanticSHA256: validated.semanticSHA256
        )
        var lines = [structuredTextMagic, "header\t" + (String(data: try encoder.encode(header), encoding: .utf8) ?? "")]
        for node in validated.nodes {
            guard let record = String(data: try encoder.encode(node), encoding: .utf8) else {
                throw SnapshotProjectionFailureV1.projectionDisagreement
            }
            lines.append("node\t\(record)")
        }
        lines.append(structuredTextEnd)
        lines.append("")
        let data = Data(lines.joined(separator: "\n").utf8)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        guard try reopenStructuredText(data) == validated else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .structuredText,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: projection.semanticSHA256,
            orderedSemanticIDs: projection.nodes.map(\.semanticID),
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenStructuredText(_ data: Data) throws -> ReportSemanticProjectionV1 {
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              let text = String(data: data, encoding: .utf8),
              text.hasSuffix("\n") else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.last == "" else { throw SnapshotProjectionFailureV1.projectionDisagreement }
        lines.removeLast()
        guard lines.first == structuredTextMagic, lines.last == structuredTextEnd, lines.count >= 3,
              lines[1].hasPrefix("header\t") else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        let decoder = JSONDecoder()
        let headerBytes = Data(lines[1].dropFirst("header\t".count).utf8)
        let header = try decoder.decode(StructuredTextHeader.self, from: headerBytes)
        guard try canonicalEncoder().encode(header) == headerBytes else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        let nodes = try lines.dropFirst(2).dropLast().map { line -> ReportSemanticNodeV1 in
            guard line.hasPrefix("node\t") else { throw SnapshotProjectionFailureV1.projectionDisagreement }
            let bytes = Data(line.dropFirst("node\t".count).utf8)
            let node = try decoder.decode(ReportSemanticNodeV1.self, from: bytes)
            guard try canonicalEncoder().encode(node) == bytes else {
                throw SnapshotProjectionFailureV1.projectionDisagreement
            }
            return node
        }
        let projection = try ReportSemanticProjectionV1(
            projectionVersion: header.projectionVersion,
            snapshotID: header.snapshotID,
            snapshotSHA256: header.snapshotSHA256,
            manifestSHA256: header.manifestSHA256,
            profileBindingSHA256: header.profileBindingSHA256,
            nodes: nodes
        )
        guard projection.semanticSHA256 == header.semanticSHA256 else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        return projection
    }
}
