import Foundation

enum GuidedSurveyOpenJSONBoundaryV1 {
    static func validate(_ projection: SurveyPublicationReportProjectionV1) throws {
        try projection.validate()
    }
    static let emitsPassFail = false
}

struct SurveyPublicationOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let projection: SurveyPublicationReportProjectionV1

    init(projection: SurveyPublicationReportProjectionV1) throws {
        try projection.validate()
        schemaVersion = 1
        self.projection = projection
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderSurveyPublication(
        _ projection: SurveyPublicationReportProjectionV1
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(
            SurveyPublicationOpenJSONEnvelopeV1(projection: projection)
        )
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SurveyPublicationOpenJSONEnvelopeV1.self, from: data)
        guard decoded.projection == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return data
    }
}

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

extension DeterministicOpenJSONRendererV1{
    static func renderAccessibleSemanticTree(_ tree:AccessibleDocumentSemanticTreeV1)throws->AccessibleDocumentRenderOutputV1{try tree.validate();let data=try AccessibleDocumentCanonicalCodecV1.encode(tree);return try .init(bytes:data,mediaType:"application/vnd.assetrounds.accessible-semantic-tree+json",rendererID:"deterministic-open-json-renderer",rendererVersion:"v1")}
}

enum AccessibleDocumentReportSemanticTreeBuilderV1{
    static func build(snapshot:CompletedActivitySnapshotV1,projection:ReportSemanticProjectionV1,manifest:ContractManifestV1,layoutProfile:ReportLayoutProfileV1,workspaceID:WorkspaceID,brandProfileID:String,brandProfileRelease:Int,brandProfileSHA256:String,evidenceReferences:[OutputScopedContentReferenceV1]=[])throws->AccessibleDocumentSemanticTreeV1{
        try snapshot.validate();let validated=try projection.recursivelyValidated();try manifest.validate();try layoutProfile.validate(against:manifest.reportSectionRegistry)
        let manifestSHA=try manifest.accessibleDocumentManifestSHA256();guard validated.snapshotSHA256==snapshot.snapshotSHA256,validated.manifestSHA256==manifestSHA else{throw AccessibleDocumentFailureV1.staleAssessment}
        try evidenceReferences.forEach{$0.validate()};guard Set(evidenceReferences.map(\.outputReferenceID)).count==evidenceReferences.count else{throw AccessibleDocumentFailureV1.duplicateIdentity};let referenceByID=Dictionary(uniqueKeysWithValues:evidenceReferences.map{($0.outputReferenceID,$0)});let referencedIDs=Set(validated.nodes.compactMap(\.outputReferenceID));guard referencedIDs==Set(referenceByID.keys)else{throw AccessibleDocumentFailureV1.missingEvidence}
        let profileSHA=try WorkspaceMutationCanonicalV1.sha256(layoutProfile);let publication=try AccessibleDocumentPublicationBindingV1(snapshotSHA256:snapshot.snapshotSHA256,manifestID:manifest.manifestID,manifestVersion:manifest.manifestVersion,manifestSHA256:manifestSHA,localeIdentifier:layoutProfile.localeIdentifier,profileID:layoutProfile.profileID,profileRelease:layoutProfile.profileRelease,profileSHA256:profileSHA,brandProfileID:brandProfileID,brandProfileRelease:brandProfileRelease,brandProfileSHA256:brandProfileSHA256)
        let sensitivity:AccessibleDocumentSensitivityV1=layoutProfile.audience == .customerSafe ? .customerSafe:.internalOnly
        var nodes=[try AccessibleDocumentNodeV1(nodeID:"c24.document",role:.document,parentNodeID:nil,order:0,sensitivity:sensitivity)]
        let sectionIDs=Array(Set(validated.nodes.map(\.sectionID))).sorted();for(sectionOrder,sectionID)in sectionIDs.enumerated(){let sectionNodeID="c24.section.\(sectionID)";nodes.append(try .init(nodeID:sectionNodeID,role:.section,parentNodeID:"c24.document",order:sectionOrder,sensitivity:sensitivity));nodes.append(try .init(nodeID:"\(sectionNodeID).heading",role:.heading,parentNodeID:sectionNodeID,order:0,headingLevel:1,localizedText:sectionID,sensitivity:sensitivity));let values=validated.nodes.filter{$0.sectionID==sectionID}.sorted();for(index,value)in values.enumerated(){let links=try value.outputReferenceID.map{referenceID->[AccessibleEvidenceLinkV1] in guard let reference=referenceByID[referenceID]else{throw AccessibleDocumentFailureV1.missingEvidence};return[try AccessibleEvidenceLinkV1(outputReference:reference)]} ?? [];nodes.append(try .init(nodeID:"c24.semantic.\(value.semanticID)",role:.paragraph,parentNodeID:sectionNodeID,order:index+1,localizedText:"\(value.label): \(value.value)",evidenceLinks:links,sensitivity:sensitivity))}}
        let input=AccessibleDocumentTreeBuildInputV1(workspaceID:workspaceID,audience:layoutProfile.audience,publication:publication,nodes:nodes,projectionVersion:validated.projectionVersion)
        return try AccessibleDocumentAudienceProjectorV1.project(input)
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

    /// C15's additive report boundary. The V8 snapshot remains immutable;
    /// packet history is represented by a bounded report projection whose
    /// source and manifest digests are retained for exact provenance.
    static func project(
        snapshot: CompletedActivitySnapshotV9,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        let v8 = snapshot.payload.activity
        let v7 = v8.payload.activity
        let v6 = v7.payload.activity
        let packetProjection = try ReportWorkPacketProjectionV1(
            snapshot: snapshot.payload.workPacket,
            sourceSnapshotSHA256: snapshot.snapshotSHA256
        )
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
            inspectionReviewHistory: v8.payload.inspectionReviewHistory,
            workPacket: packetProjection,
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
        workPacket: ReportWorkPacketProjectionV1? = nil,
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
        if let workPacket {
            try appendWorkPacket(
                workPacket,
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

    private static func appendWorkPacket(
        _ packet: ReportWorkPacketProjectionV1,
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
        try packet.validate()
        let section = ReportWorkPacketProjectionPolicyV1.sectionID
        guard binding.sectionIDs.contains(section),
              ReportWorkPacketProjectionPolicyV1.supports(.openJSON),
              ReportWorkPacketProjectionPolicyV1.supports(.structuredText) else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        try append(
            section,
            "heading",
            BundledLocalizationCatalogV1.localized(.packetHeading),
            BundledLocalizationCatalogV1.localized(.packetHeading),
            nil
        )
        try append(
            section,
            "fact",
            BundledLocalizationCatalogV1.localized(.packetManifest),
            visibleID("work-packet", packet.packetID.uuidString.lowercased()),
            nil
        )
        try append(
            section,
            "digest",
            "Packet manifest SHA-256",
            visibleDigest("work-packet-manifest", packet.manifestSHA256),
            nil
        )
        try append(section, "fact", "Packet items", String(packet.itemCount), nil)
        try append(section, "fact", "Packet history events", String(packet.historyEventCount), nil)
        try append(section, "fact", "Preserved results", String(packet.preservedResultCount), nil)
        try append(section, "status", "Collisions", String(packet.collisionCount), nil)
        try append(
            section,
            "digest",
            "Packet source snapshot SHA-256",
            visibleDigest("work-packet-source", packet.sourceSnapshotSHA256),
            nil
        )
        for (itemID, state) in zip(packet.itemIDs, packet.itemStateLabels) {
            guard let itemState = CompletedWorkPacketItemStateV1(rawValue: state) else {
                throw SnapshotProjectionFailureV1.invalidValue
            }
            let localizedState: String
            switch itemState {
            case .unclaimed:
                localizedState = BundledLocalizationCatalogV1.localized(.workPacketClaimUnclaimed)
            case .claimed:
                localizedState = BundledLocalizationCatalogV1.localized(.workPacketClaimClaimed)
            case .leased:
                localizedState = BundledLocalizationCatalogV1.localized(.workPacketLeaseActive)
            case .released:
                localizedState = BundledLocalizationCatalogV1.localized(.workPacketReleaseRecorded)
            case .handedOff:
                localizedState = BundledLocalizationCatalogV1.localized(.workPacketHandoffCompleted)
            case .conflicted:
                localizedState = BundledLocalizationCatalogV1.localized(.workPacketConflictReviewRequired)
            case .expired:
                localizedState = BundledLocalizationCatalogV1.localized(.workPacketExpiryExpired)
            }
            try append(
                section,
                "state",
                BundledLocalizationCatalogV1.localized(.packetItem),
                localizedState,
                visibleID("work-packet-item", itemID)
            )
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

/// Deterministic, metadata-only Open JSON for a promoted package report. The
/// canonical package and draft bytes remain in the lifecycle store; this
/// envelope is safe to reopen as historical report evidence.
struct PackageEvolutionOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let schema = "PACKAGE_EVOLUTION_REPORT_OPEN_JSON_V1"

    let schemaVersion: Int
    let schema: String
    let locale: String
    let report: PackageEvolutionReportProjectionV1

    init(report: PackageEvolutionReportProjectionV1, locale: String = "en") throws {
        try report.validate()
        guard locale == "en" else { throw PackageEvolutionConsumerFailureV1.invalidMetadata }
        schemaVersion = Self.schemaVersion
        schema = Self.schema
        self.locale = locale
        self.report = report
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, schema == Self.schema,
              locale == "en" else {
            throw PackageEvolutionConsumerFailureV1.invalidMetadata
        }
        try report.validate()
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderPackageEvolution(
        _ report: PackageEvolutionReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        let envelope = try PackageEvolutionOpenJSONEnvelopeV1(report: report)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        let semanticData = try PackageEvolutionCanonicalCodecV1.encode(report)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              try reopenPackageEvolution(data) == report else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: KernelCanonicalHashV1.sha256(semanticData),
            orderedSemanticIDs: [
                "package.evolution.\(report.metadata.packageID)",
                "package.evolution.release.\(report.metadata.packageReleaseID)",
            ],
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenPackageEvolution(
        _ data: Data
    ) throws -> PackageEvolutionReportProjectionV1 {
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let envelope = try JSONDecoder().decode(
            PackageEvolutionOpenJSONEnvelopeV1.self,
            from: data
        )
        try envelope.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(envelope) == data else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return envelope.report
    }
}

// MARK: - C21 client capability and package lifecycle open JSON

struct ClientCapabilityOpenJSONLabelsV1: Codable, Equatable, Sendable {
    let heading: String
    let admission: String
    let admissionState: String
    let lifecycle: String
    let lifecycleState: String
    let operation: String
    let reason: String
    let historicExport: String?
    let withdrawal: String?
    let blocked: String?
    let nextStep: String

    init(projection: ClientCapabilityReportProjectionV1) {
        func localized(_ key: ClientCapabilityLocalizationKeyV1) -> String {
            guard let bundled = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
                return key.englishDefaultValue
            }
            return BundledLocalizationCatalogV1.localized(bundled)
        }
        heading = localized(.heading)
        admission = localized(.admission)
        admissionState = localized(
            ClientCapabilityLocalizationKeyV1.admissionKey(projection.admission)
        )
        lifecycle = localized(.lifecycleHeading)
        lifecycleState = localized(
            ClientCapabilityLocalizationKeyV1.stateKey(projection.lifecycleState)
        )
        operation = localized(
            ClientCapabilityLocalizationKeyV1.operationKey(projection.operation)
        )
        reason = localized(
            ClientCapabilityLocalizationKeyV1.reasonKey(
                projection.reasons.first ?? .operationBlocked
            )
        )
        historicExport = projection.historicExportAllowed
            ? localized(.historicExport) : nil
        withdrawal = projection.lifecycleState == .withdrawn
            ? localized(.withdrawal) : nil
        blocked = projection.operationAllowed ? nil : localized(.blocked)
        nextStep = localized(.nextStep)
    }

    func validate() throws {
        let values = [
            heading, admission, admissionState, lifecycle, lifecycleState,
            operation, reason, historicExport, withdrawal, blocked, nextStep,
        ].compactMap { $0 }
        guard values.allSatisfy({ !$0.isEmpty }),
              !ClientCapabilityLocalizationPolicyV1.containsProhibitedClaim(
                  in: values
              ),
              !ClientCapabilityLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(
                  in: values
              ) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
    }
}

struct ClientCapabilityOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schema = "CLIENT_CAPABILITY_PACKAGE_LIFECYCLE_OPEN_JSON_V1"
    static let schemaVersion = 1

    let schemaVersion: Int
    let schema: String
    let locale: String
    let projection: ClientCapabilityReportProjectionV1
    let labels: ClientCapabilityOpenJSONLabelsV1

    init(
        projection: ClientCapabilityReportProjectionV1,
        locale: String = BundledLocalizationCatalogV1.runtimeLanguage
    ) throws {
        try projection.validate()
        guard locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        schemaVersion = Self.schemaVersion
        schema = Self.schema
        self.locale = locale
        self.projection = projection
        labels = ClientCapabilityOpenJSONLabelsV1(projection: projection)
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              schema == Self.schema,
              locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try projection.validate()
        try labels.validate()
        guard labels == ClientCapabilityOpenJSONLabelsV1(projection: projection) else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderClientCapability(
        _ projection: ClientCapabilityReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        try ClientCapabilityReportConsumerPolicyV1.validate(
            projection,
            format: .openJSON
        )
        let envelope = try ClientCapabilityOpenJSONEnvelopeV1(projection: projection)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              try reopenClientCapability(data) == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: projection.projectionSHA256,
            orderedSemanticIDs: [
                ClientCapabilityAccessibilityIDV1.heading.rawValue,
                ClientCapabilityAccessibilityIDV1.admission.rawValue,
                ClientCapabilityAccessibilityIDV1.admissionReadOnly.rawValue,
                ClientCapabilityAccessibilityIDV1.lifecycleState.rawValue,
                ClientCapabilityAccessibilityIDV1.lifecycleOperation.rawValue,
                ClientCapabilityAccessibilityIDV1.reason.rawValue,
                ClientCapabilityAccessibilityIDV1.nextStep.rawValue,
            ],
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenClientCapability(
        _ data: Data
    ) throws -> ClientCapabilityReportProjectionV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ClientCapabilityOpenJSONEnvelopeV1.self, from: data)
        try envelope.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(envelope) == data else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return envelope.projection
    }
}

/// C19's Open JSON companion keeps the exact recorded projection alongside
/// typed English labels. Labels are presentation only: they never replace a
/// unit identifier or turn a quality disposition into a compliance claim.
struct MeasurementIntegrityOpenJSONLabelsV1: Codable, Equatable, Sendable {
    let heading: String
    let captureValue: String
    let captureUnit: String
    let captureSource: String
    let captureSourceValue: String
    let instrumentKind: String?
    let instrumentLifecycle: String?
    let calibrationStatus: String?
    let calibrationBasis: String?
    let seriesState: String?
    let qualityResult: String?
    let qualityReasons: [String]
    let nextStep: String

    init(projection: MeasurementIntegrityReportProjectionV1) {
        heading = MeasurementIntegrityLocalizationKeyV1.heading.englishDefaultValue
        captureValue = MeasurementIntegrityLocalizationKeyV1.captureValue.englishDefaultValue
        captureUnit = MeasurementIntegrityLocalizationKeyV1.captureUnit.englishDefaultValue
        captureSource = MeasurementIntegrityLocalizationKeyV1.captureSource.englishDefaultValue
        captureSourceValue = MeasurementIntegrityLocalizationKeyV1.captureSourceKey(projection.sourceMode)
            .englishDefaultValue
        instrumentKind = projection.instrumentKind.map {
            MeasurementIntegrityLocalizationKeyV1.instrumentKindKey($0).englishDefaultValue
        }
        instrumentLifecycle = projection.instrumentLifecycleState.map {
            MeasurementIntegrityLocalizationKeyV1.instrumentLifecycleKey($0).englishDefaultValue
        }
        calibrationStatus = projection.calibrationStatus.map {
            MeasurementIntegrityLocalizationKeyV1.calibrationStatusKey($0).englishDefaultValue
        }
        calibrationBasis = projection.calibrationBasis.map {
            MeasurementIntegrityLocalizationKeyV1.calibrationBasisKey($0).englishDefaultValue
        }
        seriesState = projection.seriesState.map {
            MeasurementIntegrityLocalizationKeyV1.seriesStateKey($0).englishDefaultValue
        }
        qualityResult = projection.qualityResult.map {
            MeasurementIntegrityLocalizationKeyV1.qualityResultKey($0).englishDefaultValue
        }
        qualityReasons = projection.qualityReasonCodes.map {
            MeasurementIntegrityLocalizationKeyV1.qualityReasonKey($0).englishDefaultValue
        }
        nextStep = MeasurementIntegrityLocalizationKeyV1.nextStep.englishDefaultValue
    }

    func validate() throws {
        let values = [heading, captureValue, captureUnit, captureSource, captureSourceValue, nextStep]
            + [instrumentKind, instrumentLifecycle, calibrationStatus, calibrationBasis,
               seriesState, qualityResult]
                .compactMap { $0 }
            + qualityReasons
        guard values.allSatisfy({ !$0.isEmpty }),
              !MeasurementIntegrityLocalizationPolicyV1.containsProhibitedClaim(in: values),
              !MeasurementIntegrityLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(in: values) else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
    }
}

struct MeasurementIntegrityOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let schema = "MEASUREMENT_INTEGRITY_REPORT_OPEN_JSON_V1"

    let schemaVersion: Int
    let schema: String
    let locale: String
    let projection: MeasurementIntegrityReportProjectionV1
    let labels: MeasurementIntegrityOpenJSONLabelsV1

    init(
        projection: MeasurementIntegrityReportProjectionV1,
        locale: String = "en"
    ) throws {
        try projection.validate()
        guard locale == "en" else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        schemaVersion = Self.schemaVersion
        schema = Self.schema
        self.locale = locale
        self.projection = projection
        labels = MeasurementIntegrityOpenJSONLabelsV1(projection: projection)
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, schema == Self.schema,
              locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try projection.validate()
        try labels.validate()
        guard labels == MeasurementIntegrityOpenJSONLabelsV1(projection: projection) else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderMeasurementIntegrity(
        _ projection: MeasurementIntegrityReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        let envelope = try MeasurementIntegrityOpenJSONEnvelopeV1(projection: projection)
        let data = try measurementIntegrityEncoder().encode(envelope)
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              try reopenMeasurementIntegrity(data) == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        let semanticData = try measurementIntegrityEncoder().encode(projection)
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: KernelCanonicalHashV1.sha256(semanticData),
            orderedSemanticIDs: [
                MeasurementIntegrityAccessibilityIDV1.heading.rawValue,
                "\(MeasurementIntegrityAccessibilityIDV1.capture.rawValue).\(projection.captureID.uuidString.lowercased())",
            ],
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenMeasurementIntegrity(
        _ data: Data
    ) throws -> MeasurementIntegrityReportProjectionV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(
            MeasurementIntegrityOpenJSONEnvelopeV1.self,
            from: data
        )
        try envelope.validate()
        guard try measurementIntegrityEncoder().encode(envelope) == data else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return envelope.projection
    }

    private static func measurementIntegrityEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}

// MARK: - C23 version-bound field-reference open JSON

struct FieldReferenceOpenJSONLabelsV1: Codable, Equatable, Sendable {
    let heading: String
    let provenance: String
    let provenanceValue: String
    let licenseScope: String
    let licenseScopeValue: String
    let pack: String
    let kind: String
    let kindValue: String
    let semanticVersion: String
    let release: String
    let releaseValue: String
    let binding: String
    let subject: String
    let subjectValue: String
    let availability: String
    let availabilityValue: String
    let requiredContent: String
    let missingContent: String
    let nextStep: String

    init(projection: FieldReferenceReportProjectionV1) {
        func display(_ key: FieldReferenceLocalizationKeyV1) -> String {
            BundledLocalizationCatalogV1.fieldReferenceDisplayLabel(for: key)
        }
        heading = display(.heading)
        provenance = display(.provenance)
        provenanceValue = display(
            FieldReferenceLocalizationKeyV1.provenanceKindKey(projection.provenanceKind)
        )
        licenseScope = display(.licenseScope)
        licenseScopeValue = display(
            FieldReferenceLocalizationKeyV1.licenseScopeKey(projection.licenseScope)
        )
        pack = display(.pack)
        kind = display(.kind)
        kindValue = display(FieldReferenceLocalizationKeyV1.kindKey(projection.kind))
        semanticVersion = display(.semanticVersion)
        release = display(.release)
        releaseValue = projection.releaseDisposition == .active
            ? display(.releaseActive) : display(.releaseRevoked)
        binding = display(.binding)
        subject = display(.subject)
        subjectValue = display(FieldReferenceLocalizationKeyV1.subjectKindKey(projection.subjectKind))
            + " / "
            + display(FieldReferenceLocalizationKeyV1.subjectStateKey(projection.subjectState))
        availability = display(.availability)
        availabilityValue = display(
            FieldReferenceLocalizationKeyV1.availabilityKey(projection.availability)
        )
        requiredContent = display(.requiredContent)
        missingContent = display(.missingContent)
        nextStep = display(.nextStep)
    }

    func validate() throws {
        let values = [
            heading, provenance, provenanceValue, licenseScope, licenseScopeValue,
            pack, kind, kindValue,
            semanticVersion, release, releaseValue, binding, subject,
            subjectValue, availability, availabilityValue, requiredContent,
            missingContent, nextStep,
        ]
        guard values.allSatisfy({ !$0.isEmpty }),
              !FieldReferenceLocalizationPolicyV1.containsProhibitedClaim(in: values),
              !FieldReferenceLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(in: values) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
    }
}

struct FieldReferenceOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schema = "FIELD_REFERENCE_REPORT_OPEN_JSON_V1"
    static let schemaVersion = 1

    let schemaVersion: Int
    let schema: String
    let locale: String
    let projection: FieldReferenceReportProjectionV1
    let labels: FieldReferenceOpenJSONLabelsV1

    init(
        projection: FieldReferenceReportProjectionV1,
        locale: String = BundledLocalizationCatalogV1.runtimeLanguage
    ) throws {
        try projection.validate()
        guard locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        schemaVersion = Self.schemaVersion
        schema = Self.schema
        self.locale = locale
        self.projection = projection
        labels = FieldReferenceOpenJSONLabelsV1(projection: projection)
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              schema == Self.schema,
              locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try projection.validate()
        try labels.validate()
        guard labels == FieldReferenceOpenJSONLabelsV1(projection: projection) else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderFieldReference(
        _ projection: FieldReferenceReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        try FieldReferenceReportProjectionPolicyV1.validate(projection, format: .openJSON)
        let envelope = try FieldReferenceOpenJSONEnvelopeV1(projection: projection)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              try reopenFieldReference(data) == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: projection.projectionSHA256,
            orderedSemanticIDs: [
                FieldReferenceAccessibilityIDV1.heading.rawValue,
                FieldReferenceAccessibilityIDV1.provenance.rawValue,
                FieldReferenceAccessibilityPolicyV1
                    .availabilityID(projection.availability).rawValue,
                FieldReferenceAccessibilityIDV1.nextStep.rawValue,
            ],
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenFieldReference(
        _ data: Data
    ) throws -> FieldReferenceReportProjectionV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let envelope = try JSONDecoder().decode(
            FieldReferenceOpenJSONEnvelopeV1.self,
            from: data
        )
        try envelope.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(envelope) == data else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return envelope.projection
    }
}

// MARK: - C20 audience-safe privacy-transform open JSON

struct PrivacyTransformOpenJSONLabelsV1: Codable, Equatable, Sendable {
    let heading: String
    let redactionDeclaration: String
    let derivative: String
    let derivativeOnly: String
    let review: String
    let reviewState: String
    let freshness: String
    let projection: String
    let projectionState: String
    let originalAccess: String
    let nextStep: String

    init(projection: PrivacyTransformReportProjectionV1) {
        _ = projection
        heading = BundledLocalizationCatalogV1.localized(.privacyTransformHeading)
        redactionDeclaration = BundledLocalizationCatalogV1.localized(.privacyTransformRedactionDeclaration)
        derivative = BundledLocalizationCatalogV1.localized(.privacyTransformDerivative)
        derivativeOnly = BundledLocalizationCatalogV1.localized(.privacyTransformDerivativeOnly)
        review = BundledLocalizationCatalogV1.localized(.privacyTransformReview)
        reviewState = BundledLocalizationCatalogV1.localized(.privacyTransformReviewApproved)
        freshness = BundledLocalizationCatalogV1.localized(.privacyTransformFreshnessCurrent)
        projection = BundledLocalizationCatalogV1.localized(.privacyTransformProjection)
        projectionState = BundledLocalizationCatalogV1.localized(.privacyTransformProjectionAllowed)
        originalAccess = BundledLocalizationCatalogV1.localized(.privacyTransformOriginalAccessSeparate)
        nextStep = BundledLocalizationCatalogV1.localized(.privacyTransformNextStep)
    }

    func validate() throws {
        let values = [
            heading, redactionDeclaration, derivative, derivativeOnly, review,
            reviewState, freshness, projection, projectionState, originalAccess,
            nextStep,
        ]
        guard values.allSatisfy({ !$0.isEmpty }),
              !PrivacyTransformLocalizationPolicyV1.containsProhibitedClaim(in: values),
              !PrivacyTransformLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(in: values) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
    }
}

struct PrivacyTransformOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schema = "PRIVACY_TRANSFORM_REPORT_OPEN_JSON_V1"
    static let schemaVersion = 1

    let schemaVersion: Int
    let schema: String
    let locale: String
    let projection: PrivacyTransformReportProjectionV1
    let labels: PrivacyTransformOpenJSONLabelsV1

    init(
        projection: PrivacyTransformReportProjectionV1,
        locale: String = BundledLocalizationCatalogV1.runtimeLanguage
    ) throws {
        try projection.validate()
        guard locale == "en" else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        schemaVersion = Self.schemaVersion
        schema = Self.schema
        self.locale = locale
        self.projection = projection
        labels = PrivacyTransformOpenJSONLabelsV1(projection: projection)
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, schema == Self.schema,
              locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try projection.validate()
        try labels.validate()
        guard labels == PrivacyTransformOpenJSONLabelsV1(projection: projection) else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderPrivacyTransform(
        _ projection: PrivacyTransformReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        let envelope = try PrivacyTransformOpenJSONEnvelopeV1(projection: projection)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              try reopenPrivacyTransform(data) == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: projection.projectionSHA256,
            orderedSemanticIDs: [
                PrivacyTransformAccessibilityIDV1.heading.rawValue,
                PrivacyTransformAccessibilityIDV1.derivativeOnly.rawValue,
                PrivacyTransformAccessibilityIDV1.review.rawValue,
                PrivacyTransformAccessibilityIDV1.projectionAllowed.rawValue,
                PrivacyTransformAccessibilityIDV1.nextStep.rawValue,
            ],
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenPrivacyTransform(
        _ data: Data
    ) throws -> PrivacyTransformReportProjectionV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(PrivacyTransformOpenJSONEnvelopeV1.self, from: data)
        try envelope.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(envelope) == data else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return envelope.projection
    }
}

// MARK: - C25 survey-definition Open JSON

struct SurveyDefinitionOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let schema = "SURVEY_DEFINITION_REPORT_OPEN_JSON_V1"

    let schemaVersion: Int
    let schema: String
    let locale: String
    let projection: SurveyDefinitionReportProjectionV1
    let heading: String
    let activityKindLabel: String
    let lifecycleLabel: String
    let claimBoundary: String
    let nextStep: String

    init(
        projection: SurveyDefinitionReportProjectionV1,
        locale: String = "en"
    ) throws {
        try projection.validate(format: .openJSON)
        guard locale == "en" else {
            throw SurveyDefinitionConsumerFailureV1.unsupportedFormat
        }
        schemaVersion = Self.schemaVersion
        schema = Self.schema
        self.locale = locale
        self.projection = projection
        heading = BundledLocalizationCatalogV1.localized(.reportHeading)
        activityKindLabel = BundledLocalizationCatalogV1.localized(
            SurveyDefinitionLocalizationKeyV1.activityKindKey(
                projection.metadata.activityKind
            )
        )
        lifecycleLabel = BundledLocalizationCatalogV1.localized(
            SurveyDefinitionLocalizationKeyV1.lifecycleKey(
                projection.metadata.lifecycleState
            )
        )
        claimBoundary = BundledLocalizationCatalogV1.localized(.reportClaimBoundary)
        nextStep = BundledLocalizationCatalogV1.localized(.nextStepReviewRecordedFacts)
        try validate()
    }

    func validate() throws {
        try projection.validate(format: .openJSON)
        guard schemaVersion == Self.schemaVersion,
              schema == Self.schema,
              locale == "en",
              heading == BundledLocalizationCatalogV1.localized(.reportHeading),
              activityKindLabel == BundledLocalizationCatalogV1.localized(
                SurveyDefinitionLocalizationKeyV1.activityKindKey(
                    projection.metadata.activityKind
                )
              ),
              lifecycleLabel == BundledLocalizationCatalogV1.localized(
                SurveyDefinitionLocalizationKeyV1.lifecycleKey(
                    projection.metadata.lifecycleState
                )
              ),
              claimBoundary == BundledLocalizationCatalogV1.localized(.reportClaimBoundary),
              nextStep == BundledLocalizationCatalogV1.localized(.nextStepReviewRecordedFacts),
              !SurveyDefinitionConsumerPolicyV1.containsUnsupportedClaim([
                  heading, activityKindLabel, lifecycleLabel, claimBoundary, nextStep
              ]) else {
            throw SurveyDefinitionConsumerFailureV1.privacyViolation
        }
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderSurveyDefinition(
        _ projection: SurveyDefinitionReportProjectionV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        let envelope = try SurveyDefinitionOpenJSONEnvelopeV1(
            projection: projection,
            locale: locale
        )
        let encoder = canonicalEncoder()
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SurveyDefinitionConsumerFailureV1.limitExceeded
        }
        guard try encoder.encode(try SurveyDefinitionOpenJSONEnvelopeV1(
            projection: envelope.projection,
            locale: envelope.locale
        )) == data else {
            throw SurveyDefinitionConsumerFailureV1.invalidValue
        }
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: KernelCanonicalHashV1.sha256(
                Data(SurveyDefinitionConsumerPolicyV1.projectionVersion.utf8)
            ),
            orderedSemanticIDs: [
                SurveyDefinitionAccessibilityIDV1.screen.rawValue,
                SurveyDefinitionAccessibilityIDV1.heading.rawValue,
                SurveyDefinitionAccessibilityIDV1.activityKind.rawValue,
                SurveyDefinitionAccessibilityIDV1.lifecycle.rawValue,
                SurveyDefinitionAccessibilityIDV1.claimBoundary.rawValue,
                SurveyDefinitionAccessibilityIDV1.nextStep.rawValue,
            ],
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenSurveyDefinition(
        _ data: Data
    ) throws -> SurveyDefinitionReportProjectionV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SurveyDefinitionConsumerFailureV1.limitExceeded
        }
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(
            SurveyDefinitionOpenJSONEnvelopeV1.self,
            from: data
        )
        try envelope.validate()
        let encoder = canonicalEncoder()
        guard try encoder.encode(envelope) == data else {
            throw SurveyDefinitionConsumerFailureV1.invalidValue
        }
        return envelope.projection
    }
}
