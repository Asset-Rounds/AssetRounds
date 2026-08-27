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
            manifest: manifest
        )
    }

    private static func project(
        activity: CompletedActivitySnapshotPayloadV1,
        snapshotSHA256: String,
        locationComposition: CompletedLocationCompositionSnapshotV1?,
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
        for fact in activity.serviceFacts where binding.audience == .internalUse || fact.privacyClass != .internalOnly {
            try append("service", "fact", fact.label, fact.value)
        }
        for card in activity.evidenceCards {
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
