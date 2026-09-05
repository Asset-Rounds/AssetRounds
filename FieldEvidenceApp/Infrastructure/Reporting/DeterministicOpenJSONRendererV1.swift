import Foundation

struct ReviewedEvidenceOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let projection: ReviewedEvidenceReportProjectionV1

    init(projection: ReviewedEvidenceReportProjectionV1) throws {
        try projection.validateIntrinsic()
        schemaVersion = Self.schemaVersion
        self.projection = projection
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderReviewedEvidence(
        _ projection: ReviewedEvidenceReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        let envelope = try ReviewedEvidenceOpenJSONEnvelopeV1(projection: projection)
        let data = try EvidenceMetadataCanonicalCodecV1.data(envelope)
        guard data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let reopened = try reopenReviewedEvidence(data)
        guard reopened.projection == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: projection.projectionSHA256,
            orderedSemanticIDs: projection.orderedItems.map {
                "evidence.reviewed.\($0.item.evidenceID)"
            },
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenReviewedEvidence(_ data: Data) throws -> ReviewedEvidenceOpenJSONEnvelopeV1 {
        let value = try EvidenceMetadataCanonicalCodecV1.decode(
            ReviewedEvidenceOpenJSONEnvelopeV1.self, from: data
        )
        guard value.schemaVersion == ReviewedEvidenceOpenJSONEnvelopeV1.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try value.projection.validateIntrinsic()
        return value
    }
}

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

// MARK: - C51 advanced schedule Open JSON

private struct AdvancedScheduleReportOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schema = "ADVANCED_SCHEDULE_REPORT_OPEN_JSON_V1"
    let schema: String
    let locale: String
    let projection: AdvancedScheduleReportProjectionV1
    let labels: [String: String]

    init(_ projection: AdvancedScheduleReportProjectionV1, locale: String) throws {
        guard locale == "en" else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        self.schema = Self.schema; self.locale = locale; self.projection = projection
        labels = Self.expectedLabels
        try validate()
    }
    func validate() throws {
        guard schema == Self.schema, locale == "en", labels == Self.expectedLabels else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try AdvancedScheduleReportProjectionPolicyV1.validate(projection)
    }
    private static var expectedLabels: [String: String] { [
        "recurrence": BundledLocalizationCatalogV1.localized(.advancedRecurrence),
        "calendar": BundledLocalizationCatalogV1.localized(.exceptionCalendar),
        "adjustment": BundledLocalizationCatalogV1.localized(.businessDayAdjustment),
        "lineage": BundledLocalizationCatalogV1.localized(.occurrenceLineage),
        "override": BundledLocalizationCatalogV1.localized(.scheduleOverride),
        "precedence": BundledLocalizationCatalogV1.localized(.overridePrecedence),
        "preview": BundledLocalizationCatalogV1.localized(.changePreview),
        "conflict": BundledLocalizationCatalogV1.localized(.changeConflict),
        "recovery": BundledLocalizationCatalogV1.localized(.recovery),
    ] }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderAdvancedSchedule(
        _ projection: AdvancedScheduleReportProjectionV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        let envelope = try AdvancedScheduleReportOpenJSONEnvelopeV1(projection, locale: locale)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              try reopenAdvancedSchedule(data) == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return .init(format: .openJSON, data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: projection.projectionSHA256,
            orderedSemanticIDs: ScheduleAccessibilityIDV1.allCases.map(\.rawValue),
            taggedPDFAccessibilityEvidence: false)
    }

    static func reopenAdvancedSchedule(_ data: Data) throws -> AdvancedScheduleReportProjectionV1 {
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(AdvancedScheduleReportOpenJSONEnvelopeV1.self, from: data)
        try value.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(value) == data else { throw SnapshotProjectionFailureV1.projectionDisagreement }
        return value.projection
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
        try evidenceReferences.forEach{try $0.validate()};guard Set(evidenceReferences.map(\.outputReferenceID)).count==evidenceReferences.count else{throw AccessibleDocumentFailureV1.duplicateIdentity};let referenceByID=Dictionary(uniqueKeysWithValues:evidenceReferences.map{($0.outputReferenceID,$0)});let referencedIDs=Set(validated.nodes.compactMap(\.outputReferenceID));guard referencedIDs==Set(referenceByID.keys)else{throw AccessibleDocumentFailureV1.missingEvidence}
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

private struct C18LightingOpenJSONEnvelopeV1:Codable,Equatable,Sendable{let schemaVersion:String;let projection:LightingReportProjectionV1;let projectionSHA256:String}
extension DeterministicOpenJSONRendererV1{
 static func renderC18LightingNight(_ p:LightingReportProjectionV1)throws->ReportProjectionOutputV1{try C18LightingReportProjectionSupportV1.validate(p);let d=try C18LightingReportProjectionSupportV1.digest(p);let v=C18LightingOpenJSONEnvelopeV1(schemaVersion:C18LightingReportProjectionSupportV1.projectionVersion,projection:p,projectionSHA256:d);let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];let data=try e.encode(v);guard try reopenC18LightingNight(data)==p else{throw SnapshotProjectionFailureV1.projectionDisagreement};return .init(format:.openJSON,data:data,sha256:KernelCanonicalHashV1.sha256(data),semanticSHA256:d,orderedSemanticIDs:[p.workflowID.uuidString.lowercased()],taggedPDFAccessibilityEvidence:false)}
 static func reopenC18LightingNight(_ data:Data)throws->LightingReportProjectionV1{guard !data.isEmpty,data.count<=SnapshotProjectionLimitsV1.maximumProjectionBytes else{throw SnapshotProjectionFailureV1.limitExceeded};let v=try JSONDecoder().decode(C18LightingOpenJSONEnvelopeV1.self,from:data);let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];guard v.schemaVersion==C18LightingReportProjectionSupportV1.projectionVersion,v.projectionSHA256==(try C18LightingReportProjectionSupportV1.digest(v.projection)),try e.encode(v)==data else{throw SnapshotProjectionFailureV1.projectionDisagreement};return v.projection}
}

// MARK: - C30 operating-context report output

/// Deterministic, frozen C30 output.  Only the consumer projection is
/// serialized; the durable context remains the sole source of truth and no
/// timestamp, image, solar calculation, or expected control value is promoted
/// into an operational conclusion.
struct C30OperatingContextOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = "C30_OPERATING_CONTEXT_OPEN_JSON_V1"
    let schemaVersion: String
    let projection: C30EvidenceContextReportReferenceV1
    let labels: [String: String]

    init(
        projection: C30EvidenceContextReportReferenceV1,
        labels: [String: String]
    ) throws {
        try projection.validate()
        guard !labels.isEmpty,
              labels.keys.sorted() == Array(labels.keys).sorted(),
              labels.keys.allSatisfy(C30OperatingContextOpenJSONLabelsV1.isAllowedKey),
              labels.values.allSatisfy({ !$0.isEmpty }),
              !C30OperatingContextLocalizationPolicyV1.containsProhibitedClaim(
                Array(labels.values)
              ) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
        schemaVersion = Self.schemaVersion
        self.projection = projection
        self.labels = labels
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        try projection.validate()
        guard !labels.isEmpty,
              labels.keys.allSatisfy(C30OperatingContextOpenJSONLabelsV1.isAllowedKey),
              labels.values.allSatisfy({ !$0.isEmpty }),
              !C30OperatingContextLocalizationPolicyV1.containsProhibitedClaim(
                Array(labels.values)
              ) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderOperatingContext(
        _ projection: C30EvidenceContextReportReferenceV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        guard locale == C30OperatingContextLocalizationKeyV1.sourceLocale else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        let labels = try C30OperatingContextOpenJSONLabelsV1.labels(
            for: projection
        )
        let envelope = try C30OperatingContextOpenJSONEnvelopeV1(
            projection: projection,
            labels: labels
        )
        var encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let decoded = try reopenOperatingContext(data)
        guard decoded.projection == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: KernelCanonicalHashV1.sha256(data),
            orderedSemanticIDs: [
                "evidence.context.\(projection.contextID.uuidString.lowercased())"
            ],
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenOperatingContext(
        _ data: Data
    ) throws -> C30OperatingContextOpenJSONEnvelopeV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(
            C30OperatingContextOpenJSONEnvelopeV1.self,
            from: data
        )
        try envelope.validate()
        var encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(envelope) == data else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return envelope
    }
}

private enum C30OperatingContextOpenJSONLabelsV1 {
    private static let allowedKeys: Set<String> = [
        "claimBoundary", "condition", "conditionValue", "derivedCondition",
        "expectedControl", "heading", "historyFrozen", "manualOffline",
        "nextStep", "pairedComparison", "pairedReason", "pairedState",
        "temporalBasis",
    ]

    static func isAllowedKey(_ key: String) -> Bool {
        allowedKeys.contains(key)
    }

    static func labels(
        for projection: C30EvidenceContextReportReferenceV1
    ) throws -> [String: String] {
        try C30OperatingContextLocalizationPolicyV1.validate()
        var labels: [String: String] = [
            "claimBoundary": C30OperatingContextLocalizationKeyV1.claimBoundary
                .englishDefaultValue,
            "condition": C30OperatingContextLocalizationKeyV1.condition
                .englishDefaultValue,
            "conditionValue": C30OperatingContextLocalizationKeyV1.conditionKey(
                projection.observedCondition
            ).englishDefaultValue,
            "heading": C30OperatingContextLocalizationKeyV1.heading
                .englishDefaultValue,
            "historyFrozen": C30OperatingContextLocalizationKeyV1.historyFrozen
                .englishDefaultValue,
            "manualOffline": C30OperatingContextLocalizationKeyV1.manualOffline
                .englishDefaultValue,
            "nextStep": C30OperatingContextLocalizationKeyV1.nextStep
                .englishDefaultValue,
            "pairedComparison": C30OperatingContextLocalizationKeyV1.pairedComparison
                .englishDefaultValue,
            "temporalBasis": C30OperatingContextLocalizationKeyV1.temporalBasis
                .englishDefaultValue,
        ]
        if projection.derivedCondition != nil {
            labels["derivedCondition"] = C30OperatingContextLocalizationKeyV1
                .derivedCondition.englishDefaultValue
        }
        if let expected = projection.expectedControlState {
            labels["expectedControl"] = C30OperatingContextLocalizationKeyV1
                .expectedControlKey(expected).englishDefaultValue
        } else {
            labels["expectedControl"] = C30OperatingContextLocalizationKeyV1
                .expectedNone.englishDefaultValue
        }
        if let pair = projection.pairedObservation {
            labels["pairedState"] = pair.isComparable
                ? C30OperatingContextLocalizationKeyV1.pairedComparable
                    .englishDefaultValue
                : C30OperatingContextLocalizationKeyV1.pairedMismatch
                    .englishDefaultValue
            if !pair.mismatchReasons.isEmpty {
                labels["pairedReason"] = C30OperatingContextLocalizationKeyV1
                    .pairedMismatchReason.englishDefaultValue
            }
        } else {
            labels["pairedState"] = C30OperatingContextLocalizationKeyV1
                .pairedNotLinked.englishDefaultValue
        }
        return labels
    }
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

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Reporting_DeterministicOpenJSONRendererV1 {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
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

// MARK: - C27 asset-locator open JSON

struct AssetLocatorOpenJSONLabelsV1: Codable, Equatable, Sendable {
    let heading: String
    let resolution: String
    let representation: String
    let representationValue: String
    let outcome: String
    let outcomeValue: String
    let lifecycle: String
    let stateValue: String
    let claimBoundary: String
    let nextStep: String

    init(projection: AssetLocatorReportProjectionV1) {
        heading = BundledLocalizationCatalogV1.localized(
            AssetLocatorLocalizationKeyV1.heading
        )
        resolution = BundledLocalizationCatalogV1.localized(
            AssetLocatorLocalizationKeyV1.resolution
        )
        representation = BundledLocalizationCatalogV1.localized(
            AssetLocatorLocalizationKeyV1.representation
        )
        let representationKey: AssetLocatorLocalizationKeyV1
        switch projection.metadata?.representation ?? "" {
        case "LOCAL_SIGNED": representationKey = .representationLocalSigned
        case "EXTERNAL_KEY": representationKey = .representationExternalKey
        default: representationKey = .representationUnavailable
        }
        representationValue = BundledLocalizationCatalogV1.localized(representationKey)
        outcome = BundledLocalizationCatalogV1.localized(
            AssetLocatorLocalizationKeyV1.resolution
        )
        outcomeValue = BundledLocalizationCatalogV1.localized(
            AssetLocatorLocalizationKeyV1.outcomeKey(projection.resolution.outcome)
        )
        lifecycle = BundledLocalizationCatalogV1.localized(
            AssetLocatorLocalizationKeyV1.lifecycle
        )
        stateValue = BundledLocalizationCatalogV1.localized(
            AssetLocatorLocalizationKeyV1.stateKey(projection.metadata?.state)
        )
        claimBoundary = BundledLocalizationCatalogV1.localized(
            AssetLocatorLocalizationKeyV1.claimBoundary
        )
        nextStep = BundledLocalizationCatalogV1.localized(
            AssetLocatorLocalizationKeyV1.nextStep
        )
    }

    func validate(projection: AssetLocatorReportProjectionV1) throws {
        let expected = AssetLocatorOpenJSONLabelsV1(projection: projection)
        guard self == expected,
              [heading, resolution, representation, representationValue,
               outcome, outcomeValue, lifecycle, stateValue, claimBoundary,
               nextStep].allSatisfy({ !$0.isEmpty }),
              !AssetLocatorLocalizationPolicyV1.containsProhibitedClaim([
                  heading, resolution, representation, representationValue,
                  outcome, outcomeValue, lifecycle, stateValue, claimBoundary,
                  nextStep,
              ]) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
    }
}

struct AssetLocatorOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schema = "ASSET_LOCATOR_REPORT_OPEN_JSON_V1"
    static let schemaVersion = 1

    let schemaVersion: Int
    let schema: String
    let locale: String
    let projection: AssetLocatorReportProjectionV1
    let labels: AssetLocatorOpenJSONLabelsV1

    init(
        projection: AssetLocatorReportProjectionV1,
        locale: String = "en"
    ) throws {
        try projection.validate(format: .openJSON)
        guard locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        schemaVersion = Self.schemaVersion
        schema = Self.schema
        self.locale = locale
        self.projection = projection
        labels = AssetLocatorOpenJSONLabelsV1(projection: projection)
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              schema == Self.schema,
              locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try projection.validate(format: .openJSON)
        try labels.validate(projection: projection)
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderAssetLocator(
        _ projection: AssetLocatorReportProjectionV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        try ReportProjectionRegistryV1.validateAssetLocatorProjection(projection)
        let envelope = try AssetLocatorOpenJSONEnvelopeV1(
            projection: projection,
            locale: locale
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              try reopenAssetLocator(data) == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: try projection.semanticDigest(),
            orderedSemanticIDs: [
                AssetLocatorAccessibilityIDV1.screen.rawValue,
                AssetLocatorAccessibilityIDV1.heading.rawValue,
                AssetLocatorAccessibilityIDV1.resolution.rawValue,
                AssetLocatorAccessibilityIDV1.representation.rawValue,
                AssetLocatorAccessibilityIDV1.outcome.rawValue,
                AssetLocatorAccessibilityIDV1.lifecycle.rawValue,
                AssetLocatorAccessibilityPolicyV1.stateID(
                    projection.metadata?.state
                ).rawValue,
                AssetLocatorAccessibilityIDV1.claimBoundary.rawValue,
                AssetLocatorAccessibilityIDV1.nextStep.rawValue,
            ],
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenAssetLocator(
        _ data: Data
    ) throws -> AssetLocatorReportProjectionV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let envelope = try JSONDecoder().decode(
            AssetLocatorOpenJSONEnvelopeV1.self,
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

    static func renderAssetLocatorOpenJSON(
        _ projection: AssetLocatorReportProjectionV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        try renderAssetLocator(projection, locale: locale)
    }
}

// MARK: - C29 plan and rebase open JSON

struct PlanReportOpenJSONLabelsV1: Codable, Equatable, Sendable {
    let heading: String
    let document: String
    let revision: String
    let documentState: String
    let revisionState: String
    let placement: String
    let placementDisposition: String
    let coordinate: String
    let reference: String
    let rebasePreview: String
    let rebaseReceipt: String
    let rebaseDecision: String
    let rebaseWarning: String
    let component: String
    let residual: String
    let expectedRevision: String
    let historyImmutable: String
    let previewNotApplied: String
    let claimBoundary: String
    let nextStep: String
    let documentStates: [String: String]
    let revisionStates: [String: String]
    let placementDispositions: [String: String]
    let decisions: [String: String]
    let warnings: [String: String]

    init(projection: PlanReportProjectionV1) {
        heading = BundledLocalizationCatalogV1.localized(.planHeading)
        document = BundledLocalizationCatalogV1.localized(.planDocument)
        revision = BundledLocalizationCatalogV1.localized(.planRevision)
        documentState = BundledLocalizationCatalogV1.localized(.planRevisionState)
        revisionState = BundledLocalizationCatalogV1.localized(.planRevisionState)
        placement = BundledLocalizationCatalogV1.localized(.planPlacement)
        placementDisposition = BundledLocalizationCatalogV1.localized(.planPlacementDisposition)
        coordinate = BundledLocalizationCatalogV1.localized(.planCoordinate)
        reference = BundledLocalizationCatalogV1.localized(.planReference)
        rebasePreview = BundledLocalizationCatalogV1.localized(.planRebasePreview)
        rebaseReceipt = BundledLocalizationCatalogV1.localized(.planRebaseReceipt)
        rebaseDecision = BundledLocalizationCatalogV1.localized(.planRebaseDecision)
        rebaseWarning = BundledLocalizationCatalogV1.localized(.planRebaseWarning)
        component = BundledLocalizationCatalogV1.localized(.planRebaseComponent)
        residual = BundledLocalizationCatalogV1.localized(.planResidual)
        expectedRevision = BundledLocalizationCatalogV1.localized(.planExpectedRevision)
        historyImmutable = BundledLocalizationCatalogV1.localized(.planHistoryImmutable)
        previewNotApplied = BundledLocalizationCatalogV1.localized(.planPreviewNotApplied)
        claimBoundary = BundledLocalizationCatalogV1.localized(.planClaimBoundary)
        nextStep = BundledLocalizationCatalogV1.localized(.planNextStep)
        documentStates = Dictionary(uniqueKeysWithValues: PlanDocumentStateV1.allCases.map {
            ($0.rawValue, BundledLocalizationCatalogV1.planDocumentStateDisplayLabel($0))
        })
        revisionStates = Dictionary(uniqueKeysWithValues: PlanRevisionStateV1.allCases.map {
            ($0.rawValue, BundledLocalizationCatalogV1.planRevisionStateDisplayLabel($0))
        })
        placementDispositions = Dictionary(uniqueKeysWithValues: PlanPlacementDispositionV1.allCases.map {
            ($0.rawValue, BundledLocalizationCatalogV1.planPlacementDispositionDisplayLabel($0))
        })
        decisions = Dictionary(uniqueKeysWithValues: PlanRebaseDecisionV1.allCases.map {
            ($0.rawValue, BundledLocalizationCatalogV1.planRebaseDecisionDisplayLabel($0))
        })
        warnings = Dictionary(uniqueKeysWithValues: PlanRebaseWarningCodeV1.allCases.map {
            ($0.rawValue, BundledLocalizationCatalogV1.planRebaseWarningDisplayLabel($0))
        })
    }

    func validate(projection: PlanReportProjectionV1) throws {
        let expected = PlanReportOpenJSONLabelsV1(projection: projection)
        let values = [
            heading, document, revision, documentState, revisionState, placement,
            placementDisposition, coordinate, reference, rebasePreview,
            rebaseReceipt, rebaseDecision, rebaseWarning, component, residual,
            expectedRevision, historyImmutable, previewNotApplied, claimBoundary,
            nextStep,
        ] + Array(documentStates.values) + Array(revisionStates.values)
            + Array(placementDispositions.values) + Array(decisions.values)
            + Array(warnings.values)
        guard self == expected,
              values.allSatisfy({ !$0.isEmpty }),
              Set(documentStates.keys) == Set(PlanDocumentStateV1.allCases.map(\.rawValue)),
              Set(revisionStates.keys) == Set(PlanRevisionStateV1.allCases.map(\.rawValue)),
              Set(placementDispositions.keys) == Set(PlanPlacementDispositionV1.allCases.map(\.rawValue)),
              Set(decisions.keys) == Set(PlanRebaseDecisionV1.allCases.map(\.rawValue)),
              Set(warnings.keys) == Set(PlanRebaseWarningCodeV1.allCases.map(\.rawValue)),
              !PlanLocalizationPolicyV1.containsProhibitedClaim(values) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
    }
}

struct PlanReportOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schema = "PLAN_REPORT_OPEN_JSON_V1"
    static let schemaVersion = 1

    let schemaVersion: Int
    let schema: String
    let locale: String
    let projection: PlanReportProjectionV1
    let labels: PlanReportOpenJSONLabelsV1

    init(
        projection: PlanReportProjectionV1,
        locale: String = "en"
    ) throws {
        try projection.validate()
        guard locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        schemaVersion = Self.schemaVersion
        schema = Self.schema
        self.locale = locale
        self.projection = projection
        labels = PlanReportOpenJSONLabelsV1(projection: projection)
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              schema == Self.schema,
              locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try PlanReportProjectionPolicyV1.validate(
            projection,
            format: .openJSON
        )
        try labels.validate(projection: projection)
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderPlan(
        _ projection: PlanReportProjectionV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        try ReportProjectionRegistryV1.validatePlanProjection(projection)
        let envelope = try PlanReportOpenJSONEnvelopeV1(
            projection: projection,
            locale: locale
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              try reopenPlan(data) == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: projection.projectionSHA256,
            orderedSemanticIDs: PlanAccessibilityIDV1.allCases.map(\.rawValue),
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenPlan(
        _ data: Data
    ) throws -> PlanReportProjectionV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let envelope = try JSONDecoder().decode(
            PlanReportOpenJSONEnvelopeV1.self,
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

    static func renderPlanOpenJSON(
        _ projection: PlanReportProjectionV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        try renderPlan(projection, locale: locale)
    }
}

// MARK: - C28 schedule and occurrence open JSON

/// Labels are carried beside the machine-readable schedule projection so a
/// report can be rendered without treating an occurrence state token as user
/// facing copy. The state map is closed over the canonical ten states.
struct ScheduleReportOpenJSONLabelsV1: Codable, Equatable, Sendable {
    let heading: String
    let definition: String
    let recurrence: String
    let occurrence: String
    let occurrenceState: String
    let timeBasis: String
    let history: String
    let historyImmutable: String
    let dueQueue: String
    let reminder: String
    let reminderNotTruth: String
    let claimBoundary: String
    let nextStep: String
    let stateLabels: [String: String]

    init(projection: ScheduleReportProjectionV1) {
        heading = BundledLocalizationCatalogV1.localized(.heading)
        definition = BundledLocalizationCatalogV1.localized(.definition)
        let recurrenceKey: ScheduleLocalizationKeyV1
        switch projection.recurrenceKind {
        case "FIXED_CALENDAR": recurrenceKey = .fixedCalendar
        case "COMPLETION_RELATIVE": recurrenceKey = .completionRelative
        case "ADVANCED": recurrenceKey = .advancedRecurrence
        default: recurrenceKey = .claimBoundary
        }
        recurrence = BundledLocalizationCatalogV1.localized(recurrenceKey)
        occurrence = BundledLocalizationCatalogV1.localized(.occurrence)
        occurrenceState = BundledLocalizationCatalogV1.localized(.occurrenceState)
        timeBasis = BundledLocalizationCatalogV1.localized(.timeBasis)
        history = BundledLocalizationCatalogV1.localized(.history)
        historyImmutable = BundledLocalizationCatalogV1.localized(.historyImmutable)
        dueQueue = BundledLocalizationCatalogV1.localized(.dueQueue)
        reminder = BundledLocalizationCatalogV1.localized(.reminder)
        reminderNotTruth = BundledLocalizationCatalogV1.localized(.reminderNotTruth)
        claimBoundary = BundledLocalizationCatalogV1.localized(.claimBoundary)
        nextStep = BundledLocalizationCatalogV1.localized(.nextStep)
        stateLabels = Dictionary(uniqueKeysWithValues: OccurrenceStateV1.allCases.map {
            ($0.rawValue, BundledLocalizationCatalogV1.scheduleDisplayLabel(for: $0))
        })
    }

    func validate(projection: ScheduleReportProjectionV1) throws {
        let expected = ScheduleReportOpenJSONLabelsV1(projection: projection)
        let values = [
            heading, definition, recurrence, occurrence, occurrenceState,
            timeBasis, history, historyImmutable, dueQueue, reminder,
            reminderNotTruth, claimBoundary, nextStep,
        ] + Array(stateLabels.values)
        guard self == expected,
              values.allSatisfy({ !$0.isEmpty }),
              Set(stateLabels.keys) == Set(OccurrenceStateV1.allCases.map(\.rawValue)),
              !ScheduleLocalizationPolicyV1.containsProhibitedClaim(values) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
    }
}

struct ScheduleReportOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schema = "SCHEDULE_REPORT_OPEN_JSON_V1"
    static let schemaVersion = 1

    let schemaVersion: Int
    let schema: String
    let locale: String
    let projection: ScheduleReportProjectionV1
    let labels: ScheduleReportOpenJSONLabelsV1

    init(
        projection: ScheduleReportProjectionV1,
        locale: String = "en"
    ) throws {
        try projection.validate()
        guard locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        schemaVersion = Self.schemaVersion
        schema = Self.schema
        self.locale = locale
        self.projection = projection
        labels = ScheduleReportOpenJSONLabelsV1(projection: projection)
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              schema == Self.schema,
              locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try ScheduleReportProjectionPolicyV1.validate(
            projection,
            format: .openJSON
        )
        try labels.validate(projection: projection)
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderSchedule(
        _ projection: ScheduleReportProjectionV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        try ReportProjectionRegistryV1.validateScheduleProjection(projection)
        let envelope = try ScheduleReportOpenJSONEnvelopeV1(
            projection: projection,
            locale: locale
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              try reopenSchedule(data) == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: projection.projectionSHA256,
            orderedSemanticIDs: ScheduleAccessibilityIDV1.allCases.map(\.rawValue),
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenSchedule(
        _ data: Data
    ) throws -> ScheduleReportProjectionV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let envelope = try JSONDecoder().decode(
            ScheduleReportOpenJSONEnvelopeV1.self,
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

    static func renderScheduleOpenJSON(
        _ projection: ScheduleReportProjectionV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        try renderSchedule(projection, locale: locale)
    }
}

// MARK: - C37 reference-framed pose Open JSON

struct C37PoseReportOpenJSONLabelsV1: Codable, Equatable, Sendable {
    let heading: String
    let axis: String
    let current: String
    let history: String
    let referenceFrame: String
    let observation: String
    let uncertainty: String
    let currentTip: String
    let historyFrozen: String
    let previewNotApplied: String
    let claimBoundary: String
    let nextStep: String
    let referenceFrames: [String: String]
    let observationStates: [String: String]
    let notObservedReasons: [String: String]

    init() {
        heading = BundledLocalizationCatalogV1.localized(.heading)
        axis = BundledLocalizationCatalogV1.localized(.axis)
        current = BundledLocalizationCatalogV1.localized(.current)
        history = BundledLocalizationCatalogV1.localized(.history)
        referenceFrame = BundledLocalizationCatalogV1.localized(.referenceFrame)
        observation = BundledLocalizationCatalogV1.localized(.observation)
        uncertainty = BundledLocalizationCatalogV1.localized(.uncertainty)
        currentTip = BundledLocalizationCatalogV1.localized(.currentTip)
        historyFrozen = BundledLocalizationCatalogV1.localized(.historyFrozen)
        previewNotApplied = BundledLocalizationCatalogV1.localized(.previewNotApplied)
        claimBoundary = BundledLocalizationCatalogV1.localized(.claimBoundary)
        nextStep = BundledLocalizationCatalogV1.localized(.nextStep)
        referenceFrames = Dictionary(uniqueKeysWithValues:
            C37PoseReferenceFrameProjectionV1.allCases.map {
                ($0.rawValue, BundledLocalizationCatalogV1.poseReferenceFrameDisplayLabel(for: $0))
            }
        )
        observationStates = Dictionary(uniqueKeysWithValues:
            C37PoseObservationStateV1.allCases.map {
                ($0.rawValue, BundledLocalizationCatalogV1.poseObservationStateDisplayLabel(for: $0))
            }
        )
        notObservedReasons = Dictionary(uniqueKeysWithValues:
            PoseNotObservedReasonV1.allCases.map {
                ($0.rawValue, BundledLocalizationCatalogV1.poseNotObservedReasonDisplayLabel(for: $0))
            }
        )
    }

    func validate() throws {
        let expected = Self()
        let values = [
            heading, axis, current, history, referenceFrame, observation,
            uncertainty, currentTip, historyFrozen, previewNotApplied,
            claimBoundary, nextStep,
        ] + Array(referenceFrames.values) + Array(observationStates.values)
            + Array(notObservedReasons.values)
        guard self == expected,
              values.allSatisfy({ !$0.isEmpty }),
              Set(referenceFrames.keys) == Set(C37PoseReferenceFrameProjectionV1.allCases.map(\.rawValue)),
              Set(observationStates.keys) == Set(C37PoseObservationStateV1.allCases.map(\.rawValue)),
              Set(notObservedReasons.keys) == Set(PoseNotObservedReasonV1.allCases.map(\.rawValue)),
              !C37PoseLocalizationPolicyV1.containsProhibitedClaim(values) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
    }
}

struct C37PoseQualifiedDisplayRowV1: Codable, Equatable, Sendable {
    let eventID: UUID
    let text: String

    init(row: C37PoseHistoryProjectionV1, labels: C37PoseReportOpenJSONLabelsV1) {
        eventID = row.eventID
        let frame = labels.referenceFrames[row.referenceFrame.rawValue]
            ?? row.referenceFrame.rawValue
        let uncertainty = row.horizontalUncertaintyState == .unknown
            || row.verticalUncertaintyState == .unknown
            ? BundledLocalizationCatalogV1.localized(.uncertaintyUnknown)
            : BundledLocalizationCatalogV1.localized(.uncertaintyKnown)
        if row.disposition == .notObserved {
            let reason = row.notObservedReason.map {
                labels.notObservedReasons[$0.rawValue] ?? $0.rawValue
            } ?? BundledLocalizationCatalogV1.localized(.missing)
            text = "\(BundledLocalizationCatalogV1.localized(.notObserved)) — \(reason); \(uncertainty)"
        } else {
            let azimuth = row.azimuthMilliDegrees.map(Self.angleText) ?? "—"
            let elevation = row.elevationMilliDegrees.map(Self.angleText)
            let values = elevation.map { "\(azimuth)° / \($0)°" } ?? "\(azimuth)°"
            let stateQualifier: String
            switch row.observationState {
            case .manualFallback:
                stateQualifier = "\(BundledLocalizationCatalogV1.localized(.manualFallback)); "
            case .reviewRequired:
                stateQualifier = "\(BundledLocalizationCatalogV1.localized(.reviewRequired)); "
            default:
                stateQualifier = ""
            }
            text = "\(stateQualifier)\(values) \(frame); \(uncertainty)"
        }
    }

    private static func angleText(_ value: Int32) -> String {
        let sign = value < 0 ? "-" : ""
        let magnitude = Int64(value < 0 ? -Int64(value) : Int64(value))
        return String(format: "%@%lld.%03lld", sign, magnitude / 1_000,
                      magnitude % 1_000)
    }
}

struct C37PoseReportOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schema = "C37_PLACEMENT_POSE_OPEN_JSON_V1"
    static let schemaVersion = 1

    let schemaVersion: Int
    let schema: String
    let locale: String
    let projection: C37PlacementPoseReportProjectionV1
    let labels: C37PoseReportOpenJSONLabelsV1
    let qualifiedRows: [C37PoseQualifiedDisplayRowV1]

    init(projection: C37PlacementPoseReportProjectionV1, locale: String = "en") throws {
        try C37PoseReportProjectionPolicyV1.validate(projection)
        guard locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        schemaVersion = Self.schemaVersion
        schema = Self.schema
        self.locale = locale
        self.projection = projection
        let builtLabels = C37PoseReportOpenJSONLabelsV1()
        labels = builtLabels
        qualifiedRows = projection.history.map {
            C37PoseQualifiedDisplayRowV1(row: $0, labels: builtLabels)
        }
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              schema == Self.schema,
              locale == "en" else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        try C37PoseReportProjectionPolicyV1.validate(projection)
        try labels.validate()
        let expected = projection.history.map {
            C37PoseQualifiedDisplayRowV1(row: $0, labels: labels)
        }
        guard qualifiedRows == expected,
              !C37PoseLocalizationPolicyV1.containsProhibitedClaim(qualifiedRows.map(\.text)) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderPlacementPose(
        _ projection: C37PlacementPoseReportProjectionV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        let envelope = try C37PoseReportOpenJSONEnvelopeV1(
            projection: projection, locale: locale
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              try reopenPlacementPose(data) == projection else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: projection.projectionSHA256,
            orderedSemanticIDs: C37PlacementPoseAccessibilityIDV1.allCases.map(\.rawValue),
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func renderPoseOpenJSON(
        _ projection: C37PlacementPoseReportProjectionV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        try renderPlacementPose(projection, locale: locale)
    }

    static func reopenPlacementPose(
        _ data: Data
    ) throws -> C37PlacementPoseReportProjectionV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let envelope = try JSONDecoder().decode(
            C37PoseReportOpenJSONEnvelopeV1.self, from: data
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
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Reporting_DeterministicOpenJSONRendererV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift", role: .report)
}

// MARK: - C31 lighting report output

private enum C31LightingOpenJSONLabelsV1 {
    static let allowed: Set<String> = [
        "heading", "topology", "claim_boundary", "history_frozen",
        "manual_offline", "safety_stop", "next_step",
    ]
}

struct C31LightingOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = "C31_LIGHTING_OPEN_JSON_V1"

    let schemaVersion: String
    let projection: C31LightingReportProjectionV1
    let labels: [String: String]

    init(
        projection: C31LightingReportProjectionV1,
        labels: [String: String]
    ) throws {
        try C31LightingProjectionPolicyV1.validate(projection)
        guard Set(labels.keys) == C31LightingOpenJSONLabelsV1.allowed,
              labels.values.allSatisfy({ !$0.isEmpty }),
              !C31LightingLocalizationPolicyV1.containsProhibitedClaim(
                Array(labels.values)
              ) else {
            throw SnapshotProjectionFailureV1.hostileText
        }
        schemaVersion = Self.schemaVersion
        self.projection = projection
        self.labels = labels
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              Set(labels.keys) == C31LightingOpenJSONLabelsV1.allowed,
              labels.values.allSatisfy({ !$0.isEmpty }) else {
            throw SnapshotProjectionFailureV1.invalidValue
        }
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

extension DeterministicOpenJSONRendererV1 {
    static func renderLighting(
        _ projection: C31LightingReportProjectionV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        guard locale == "en" else { throw SnapshotProjectionFailureV1.incompatibleVersion }
        let labels = [
            "heading": BundledLocalizationCatalogV1.lightingDisplayLabel(
                for: .systemHeading
            ),
            "topology": BundledLocalizationCatalogV1.lightingDisplayLabel(
                for: .topology
            ),
            "claim_boundary": BundledLocalizationCatalogV1.lightingDisplayLabel(
                for: .claimBoundary
            ),
            "history_frozen": BundledLocalizationCatalogV1.lightingDisplayLabel(
                for: .historyFrozen
            ),
            "manual_offline": BundledLocalizationCatalogV1.lightingDisplayLabel(
                for: .manualOffline
            ),
            "safety_stop": BundledLocalizationCatalogV1.lightingDisplayLabel(
                for: .safetyStop
            ),
            "next_step": BundledLocalizationCatalogV1.lightingDisplayLabel(
                for: .safetyNextStep
            ),
        ]
        let envelope = try C31LightingOpenJSONEnvelopeV1(
            projection: projection,
            labels: labels
        )
        var encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: projection.systemSHA256,
            orderedSemanticIDs: C31LightingAccessibilityIDV1.allCases.map(\.rawValue),
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenLighting(
        _ data: Data
    ) throws -> C31LightingReportProjectionV1 {
        guard !data.isEmpty,
              data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let envelope = try JSONDecoder().decode(
            C31LightingOpenJSONEnvelopeV1.self,
            from: data
        )
        try envelope.validate()
        var encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(envelope) == data else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return envelope.projection
    }
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Reporting_DeterministicOpenJSONRendererV1_swift {
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

/// C45 OpenJSON describes manifest metadata and never becomes a second label renderer.
enum C45AssetLabelBoundary_DeterministicOpenJSONRendererV1 {
    static func validate(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws { try snapshot.validate() }
    static let rendersLabelArtifactBytes = false
}

enum C46OperationalContactBoundary_27{static let defaultProjection="EXCLUDED";static let rawPhoneOrEmailEmitted=false;static let platformOutcomeClaimEmitted=false}

enum C47ActivityContractConformance_FieldEvidenceApp_Infrastructure_Reporting_DeterministicOpenJSONRendererV1_swift {
    static let integrationRole = "UNKNOWN_KIND_READ_EXPORT"
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingReportInfrastructure = true
    static let createsSecondRendererWriterOrStore = false
    static func validateReadable(_ value: ActivitySessionEnvelopeV2) throws { try value.validateForRead() }
    static func metadata(_ projection: ActivityContractReportProjectionV2) throws -> [String: String] {
        try projection.envelope.validateForRead()
        return ["activity_id": projection.envelope.activityID.uuidString.lowercased(),
                "activity_kind": projection.envelope.kind.rawValue,
                "activity_state": projection.envelope.state.rawValue,
                "activity_revision": String(projection.envelope.revision),
                "envelope_sha256": projection.envelope.envelopeSHA256]
    }
}

extension ReportSemanticProjectorV1 {
    static func project(
        activityContract projection: ActivityContractReportProjectionV2,
        manifest: ContractManifestV1
    ) throws -> ReportSemanticProjectionV1 {
        guard let completed = projection.completed else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        guard let reference = projection.envelope.completedSnapshotReference else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        try reference.validate(snapshot: completed)
        guard reference.workspaceID == projection.envelope.workspaceID,
              reference.activityID == projection.envelope.activityID else {
            throw SnapshotProjectionFailureV1.missingBinding
        }
        let base = try project(snapshot: completed, manifest: manifest)
        let section = base.nodes.contains(where: { $0.sectionID == "service" })
            ? "service" : (base.nodes.first?.sectionID ?? "identity")
        var nodes = base.nodes
        nodes += [
            try ReportSemanticNodeV1(semanticID: "c47-activity-kind", sectionID: section,
                                     role: "fact", label: "Activity kind",
                                     value: projection.envelope.kind.rawValue),
            try ReportSemanticNodeV1(semanticID: "c47-activity-state", sectionID: section,
                                     role: "fact", label: "Activity state",
                                     value: projection.envelope.state.rawValue),
            try ReportSemanticNodeV1(semanticID: "c47-activity-title", sectionID: section,
                                     role: "fact", label: "Activity",
                                     value: projection.envelope.title),
            try ReportSemanticNodeV1(semanticID: "c47-activity-revision", sectionID: section,
                                     role: "fact", label: "Activity revision",
                                     value: String(projection.envelope.revision)),
        ]
        if let reference = projection.completedSnapshotReference {
            nodes += [
                try ReportSemanticNodeV1(
                    semanticID: "c47-snapshot-target-workspace", sectionID: section,
                    role: "identity", label: "Snapshot target workspace",
                    value: reference.workspaceID.rawValue.uuidString.lowercased()
                ),
                try ReportSemanticNodeV1(
                    semanticID: "c47-snapshot-target-activity", sectionID: section,
                    role: "identity", label: "Snapshot target activity",
                    value: reference.activityID.uuidString.lowercased()
                ),
                try ReportSemanticNodeV1(
                    semanticID: "c47-snapshot-source-workspace", sectionID: section,
                    role: "identity", label: "Snapshot source workspace",
                    value: reference.sourceWorkspaceID.rawValue.uuidString.lowercased()
                ),
                try ReportSemanticNodeV1(
                    semanticID: "c47-snapshot-source-activity", sectionID: section,
                    role: "identity", label: "Snapshot source activity",
                    value: reference.sourceActivityID.uuidString.lowercased()
                ),
                try ReportSemanticNodeV1(
                    semanticID: "c47-snapshot-source-revision", sectionID: section,
                    role: "fact", label: "Snapshot source revision",
                    value: String(reference.sourceActivityRevision)
                ),
                try ReportSemanticNodeV1(
                    semanticID: "c47-snapshot-source-closeout", sectionID: section,
                    role: "digest", label: "Snapshot source closeout SHA-256",
                    value: reference.sourceCloseoutSHA256
                ),
                try ReportSemanticNodeV1(
                    semanticID: "c47-snapshot-target-closeout", sectionID: section,
                    role: "digest", label: "Snapshot target closeout SHA-256",
                    value: reference.targetCloseoutSHA256
                ),
            ]
        }
        if let installation = projection.installation {
            nodes.append(try ReportSemanticNodeV1(
                semanticID: "c47-installation-completion", sectionID: section,
                role: "fact", label: "Installation completion",
                value: installation.completion.rawValue
            ))
        }
        if let closeout = projection.installationCloseout {
            nodes += [
                try ReportSemanticNodeV1(
                    semanticID: "c47-installation-closeout-completion", sectionID: section,
                    role: "fact", label: "Installation closeout",
                    value: closeout.completion.rawValue
                ),
                try ReportSemanticNodeV1(
                    semanticID: "c47-installation-closeout-as-built", sectionID: section,
                    role: "digest", label: "As-built snapshot SHA-256",
                    value: closeout.asBuiltSnapshotSHA256
                ),
                try ReportSemanticNodeV1(
                    semanticID: "c47-installation-closeout-open-findings", sectionID: section,
                    role: "fact", label: "Open recorded findings",
                    value: String(closeout.openFindings.count)
                ),
                try ReportSemanticNodeV1(
                    semanticID: "c47-installation-closeout-sha256", sectionID: section,
                    role: "digest", label: "Installation closeout SHA-256",
                    value: closeout.closeoutSHA256
                ),
            ]
            if let limitation = closeout.limitation {
                nodes.append(try ReportSemanticNodeV1(
                    semanticID: "c47-installation-closeout-limitation", sectionID: section,
                    role: "limitation", label: "Installation limitation", value: limitation
                ))
            }
            for link in closeout.openFindings {
                nodes.append(try ReportSemanticNodeV1(
                    semanticID: "c47-installation-finding-\(link.findingID.uuidString.lowercased())",
                    sectionID: section, role: "digest", label: "Recorded finding SHA-256",
                    value: link.findingSHA256
                ))
            }
        }
        if let punch = projection.punch {
            nodes.append(try ReportSemanticNodeV1(
                semanticID: "c47-punch-basis", sectionID: section,
                role: "digest", label: "Punch review basis SHA-256",
                value: punch.basisSHA256
            ))
        }
        if let closeout = projection.punchReviewCloseout {
            nodes += [
                try ReportSemanticNodeV1(
                    semanticID: "c47-punch-closeout-completion", sectionID: section,
                    role: "fact", label: "Punch review closeout",
                    value: closeout.completion.rawValue
                ),
                try ReportSemanticNodeV1(
                    semanticID: "c47-punch-closeout-basis", sectionID: section,
                    role: "digest", label: "Punch review basis SHA-256",
                    value: closeout.basisSHA256
                ),
                try ReportSemanticNodeV1(
                    semanticID: "c47-punch-closeout-limitation", sectionID: section,
                    role: "limitation", label: "Punch review scope and time limitation",
                    value: closeout.scopeAndTimeLimitation
                ),
                try ReportSemanticNodeV1(
                    semanticID: "c47-punch-closeout-sha256", sectionID: section,
                    role: "digest", label: "Punch review closeout SHA-256",
                    value: closeout.closeoutSHA256
                ),
            ]
            for (itemIndex, item) in closeout.scope.enumerated() {
                nodes.append(try ReportSemanticNodeV1(
                    semanticID: "c47-punch-item-\(itemIndex)", sectionID: section,
                    role: "fact", label: "Punch scope item \(item.scopeItemID)",
                    value: "\(item.disposition.rawValue)|findings=\(item.findingLinks.count)"
                ))
                for (findingIndex, link) in item.findingLinks.enumerated() {
                    nodes.append(try ReportSemanticNodeV1(
                        semanticID: "c47-punch-item-\(itemIndex)-finding-\(findingIndex)",
                        sectionID: section, role: "digest", label: "Recorded finding SHA-256",
                        value: link.findingSHA256
                    ))
                }
            }
        }
        return try ReportSemanticProjectionV1(
            projectionVersion: "activity-contract-report-v2",
            snapshotID: base.snapshotID,
            snapshotSHA256: base.snapshotSHA256,
            manifestSHA256: base.manifestSHA256,
            profileBindingSHA256: base.profileBindingSHA256,
            nodes: nodes.sorted()
        )
    }
}

// MARK: - C48 portable-review derived open-JSON boundary

extension DeterministicOpenJSONRendererV1 {
    /// Validate-only hook for the existing renderer.  The canonical review
    /// response is never passed to or serialized by this surface.
    static func validatePortableReviewDerivedHistory(
        _ projection: C48PortableReviewDerivedHistoryProjectionV1
    ) throws -> C48PortableReviewDerivedHistoryProjectionV1 {
        try C48PortableReviewReportProjectionBoundaryV1.validate(projection)
        return projection
    }
}

enum C48PortableReviewOpenJSONBoundaryV1 {
    static let usesExistingOpenJSONRenderer = true
    static let emitsDerivedMetadataOnly = true
    static let capabilityBytesEmitted = false
    static let capabilityProofBytesEmitted = false
    static let responseBodyEmitted = false
    static let rawRequestResponseBytesEmitted = false
    static let workspaceAndReplicaIdentityEmitted = false
}

// MARK: - C49 work-resource deterministic open JSON

extension DeterministicOpenJSONRendererV1 {
    static func renderWorkResource(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> Data {
        let envelope = try C49WorkResourceProjectionSupportV1.envelope(
            projection,
            format: "OPEN_JSON"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }

    static func renderWorkResourceOutput(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        let data = try renderWorkResource(projection)
        return ReportProjectionOutputV1(
            format: .openJSON,
            data: data,
            sha256: KernelCanonicalHashV1.sha256(data),
            semanticSHA256: projection.projectionSHA256,
            orderedSemanticIDs: projection.sourceRecordIDs.map { $0.uuidString.lowercased() },
            taggedPDFAccessibilityEvidence: false
        )
    }

    static func reopenWorkResource(
        _ data: Data
    ) throws -> C49WorkResourceProjectionEnvelopeV1 {
        try C49WorkResourceReportSnapshotEncoderBoundaryV1.decode(data)
    }
}

enum C49WorkResourceOpenJSONBoundaryV1 {
    static let sortedKeysAndStableBytes = true
    static let reopenRequiresByteEquality = true
    static let rawStockAndLiveInventoryClaimsEmitted = false
    static let formulaSafeCSVIsSeparate = true
}

/// Open JSON is a deterministic projection of accepted canonical/report
/// values. It never serializes source bytes, external keys, private fields,
/// direct costs, or a live-stock assertion from C50 exchange state.
enum C50IncumbentFileExchangeOpenJSONBoundaryV1 {
    static let sortedKeysAndStableBytes = true
    static let repeatedRenderBytesMatch = true
    static let sourceAndQuarantineBytesExcluded = true
    static let externalAvailabilityExcludedFromReportTruth = true
    static let privateFieldsRequireExplicitApproval = true
    static let directCostProjectionIsAbsent = C50IncumbentFileExchangeLifecycleBoundaryV1.directCostProjectionIsAbsent
    static let rawStockAndLiveInventoryClaimsExcluded = true

    static func validate() -> Bool {
        sortedKeysAndStableBytes
            && repeatedRenderBytesMatch
            && sourceAndQuarantineBytesExcluded
            && externalAvailabilityExcludedFromReportTruth
            && privateFieldsRequireExplicitApproval
            && directCostProjectionIsAbsent
            && rawStockAndLiveInventoryClaimsExcluded
    }
}

// MARK: - C34 route snapshot Open JSON exclusion

enum C34RouteSnapshotOpenJSONBoundaryV1 {
    static let snapshotType: Any.Type = SceneNavigationSnapshotV1.self
    static let routeSnapshotRendererExists = false
    static let selectedRootOrPathRendered = false
    static let stableRouteIdentifiersRendered = false
    static let fallbackReasonRendered = false
    static let customerContentRendered = false

    static func validate(_ lifecycle: SceneNavigationLifecycleDispositionV1 = .init()) -> Bool {
        !lifecycle.reportIncluded && !lifecycle.exportIncluded && !routeSnapshotRendererExists
    }
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Reporting_DeterministicOpenJSONRendererV1_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}

// MARK: - C53 reliability open JSON renderer boundary

enum C53ServiceReliabilityOpenJSONRendererV1 {
    static let format = "OPEN_JSON"
    static let usesCanonicalProjectionBytes = true
    static let emitsUnavailableQualification = true
    static let emitsOperationalOrComplianceClaim = false

    static func render(
        _ projection: C53ServiceReliabilityReportProjectionV1
    ) throws -> Data {
        try projection.validate()
        return try ServiceReliabilityCanonicalCodecV1.encode(projection)
    }

    static func reopen(_ data: Data) throws -> C53ServiceReliabilityReportProjectionV1 {
        try ServiceReliabilityCanonicalCodecV1.decode(
            C53ServiceReliabilityReportProjectionV1.self,
            from: data
        )
    }
}

// MARK: - C57 My Day privacy-bounded Open JSON

struct C57MyDayOpenJSONCountV1: Codable, Equatable, Sendable {
    let value: String
    let count: Int
}

struct C57MyDayOpenJSONEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let planRevision: UInt64
    let itemCount: Int
    let estimatedItemCount: Int
    let dueItemCount: Int
    let sourceStateCounts: [C57MyDayOpenJSONCountV1]
    let readinessCounts: [C57MyDayOpenJSONCountV1]
    let sourceClosureSHA256: String
    let readinessProjectionSHA256: String
    let reportProjectionSHA256: String

    init(_ projection: C57MyDayReportProjectionV1) throws {
        try projection.validate()
        schemaVersion = Self.schemaVersion
        planRevision = projection.plan.revision
        itemCount = projection.items.count
        estimatedItemCount = projection.items.filter { $0.estimateWholeMinutes != nil }.count
        dueItemCount = projection.items.filter { $0.dueAt != nil }.count
        sourceStateCounts = Self.counts(projection.items.map(\.sourceState.rawValue))
        readinessCounts = Self.counts(projection.items.map(\.readiness.rawValue))
        sourceClosureSHA256 = projection.sourceClosureSHA256
        readinessProjectionSHA256 = projection.readinessProjectionSHA256
        reportProjectionSHA256 = projection.projectionSHA256
        try validate()
    }

    func validate() throws {
        let stateValues = sourceStateCounts.map(\.value)
        let readinessValues = readinessCounts.map(\.value)
        guard schemaVersion == Self.schemaVersion, planRevision > 0,
              itemCount >= 0, itemCount <= MyDayLimitsV1.maximumItems,
              estimatedItemCount >= 0, estimatedItemCount <= itemCount,
              dueItemCount >= 0, dueItemCount <= itemCount,
              sourceStateCounts == sourceStateCounts.sorted(by: { $0.value < $1.value }),
              readinessCounts == readinessCounts.sorted(by: { $0.value < $1.value }),
              Set(stateValues).count == stateValues.count,
              Set(readinessValues).count == readinessValues.count,
              Set(stateValues).isSubset(of: Set(MyDaySourceStateV1.allCases.map(\.rawValue))),
              Set(readinessValues).isSubset(of: Set(MyDayReadinessV1.allCases.map(\.rawValue))),
              sourceStateCounts.reduce(0, { $0 + $1.count }) == itemCount,
              readinessCounts.reduce(0, { $0 + $1.count }) == itemCount,
              sourceStateCounts.allSatisfy({ $0.count > 0 }),
              readinessCounts.allSatisfy({ $0.count > 0 }),
              KernelCanonicalHashV1.validSHA256(sourceClosureSHA256),
              KernelCanonicalHashV1.validSHA256(readinessProjectionSHA256),
              KernelCanonicalHashV1.validSHA256(reportProjectionSHA256) else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
    }

    private static func counts(_ values: [String]) -> [C57MyDayOpenJSONCountV1] {
        Dictionary(grouping: values, by: { $0 }).map {
            .init(value: $0.key, count: $0.value.count)
        }.sorted { $0.value < $1.value }
    }
}

enum C57MyDayOpenJSONRendererV1 {
    static let exactDueTimestampsEmitted = false
    static let sourceStableIdentifiersEmitted = false
    static let actorOrMutationIdentifiersEmitted = false

    static func render(
        _ projection: C57MyDayReportProjectionV1,
        plan: MyDayPlanV1,
        readiness: MyDayReadinessProjectionV1
    ) throws -> Data {
        try projection.validate(plan: plan, readiness: readiness)
        let envelope = try C57MyDayOpenJSONEnvelopeV1(projection)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }

    static func reopen(_ data: Data) throws -> C57MyDayOpenJSONEnvelopeV1 {
        guard !data.isEmpty, data.count <= MyDayLimitsV1.maximumCanonicalBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        let decoder = JSONDecoder()
        let value = try decoder.decode(C57MyDayOpenJSONEnvelopeV1.self, from: data)
        try value.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(value) == data else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return value
    }
}

enum EntityIdentityResolutionOpenJSONRendererV1 {
    static let format = "OPEN_JSON"
    static let emitsMutablePlan = false
    static let emitsAutomaticConsolidationClaim = false

    static func render(_ projection: EntityIdentityResolutionReportProjectionV1) throws -> Data {
        try projection.validate()
        return try WorkspaceMutationCanonicalV1.data(projection)
    }

    static func reopen(_ data: Data) throws -> EntityIdentityResolutionReportProjectionV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(EntityIdentityResolutionReportProjectionV1.self, from: data)
        try value.validate()
        guard try WorkspaceMutationCanonicalV1.data(value) == data else {
            throw EntityIdentityResolutionFailureV1.corruptDigest
        }
        return value
    }
}
