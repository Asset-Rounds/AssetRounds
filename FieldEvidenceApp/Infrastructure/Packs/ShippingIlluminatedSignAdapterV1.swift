import CryptoKit
import Foundation

struct ShippingIlluminatedSignParityReceiptV1: Equatable, Sendable {
    let packageID: String
    let sourceSchemaVersion: Int
    let sourceContentVersion: Int
    let inspectionPackageSchemaVersion: Int
    let sourceCanonicalSHA256: String
    let roundTripCanonicalSHA256: String
    let exactParity: Bool
}

struct LegacySignCouldNotVerifyValueV1: Equatable, Sendable {
    let reasonKey: String
    let frozenDisplay: String
    let registryVersion: String
}

struct LegacySignResponseSourceV1: Equatable, Sendable {
    let acknowledgementValues: [String: Bool]
    let outcomeKey: String?
    let issueKeys: [String]
    let couldNotVerify: LegacySignCouldNotVerifyValueV1?
    let note: String?
    let entityReference: ResponseEntityReferenceV1?
    let contentReference: ResponseContentReferenceIDV1?

    init(
        acknowledgementValues: [String: Bool] = [:],
        outcomeKey: String? = nil,
        issueKeys: [String] = [],
        couldNotVerify: LegacySignCouldNotVerifyValueV1? = nil,
        note: String? = nil,
        entityReference: ResponseEntityReferenceV1? = nil,
        contentReference: ResponseContentReferenceIDV1? = nil
    ) {
        self.acknowledgementValues = acknowledgementValues
        self.outcomeKey = outcomeKey
        self.issueKeys = issueKeys
        self.couldNotVerify = couldNotVerify
        self.note = note
        self.entityReference = entityReference
        self.contentReference = contentReference
    }
}

struct LegacySignTypedResponseEntryV1: Codable, Equatable, Sendable {
    let fieldID: String
    let value: ResponseValueV1
}

struct LegacySignTypedResponseMappingReceiptV1: Equatable, Sendable {
    let packageID: String
    let packageContentVersion: Int
    let couldNotVerifyRegistryVersion: String
    let couldNotVerifyFrozenDisplay: String?
    let shippingPackCanonicalSHA256: String
    let orderedFieldIDs: [String]
    let canonicalResponsesSHA256: String
    let exactSemanticParity: Bool
    let inventedMeasurementCount: Int
}

struct LegacySignTypedResponseMappingV1: Equatable, Sendable {
    let responses: [LegacySignTypedResponseEntryV1]
    let receipt: LegacySignTypedResponseMappingReceiptV1
}

enum ShippingIlluminatedSignAdapterV1 {
    static let packageID = SignPack.illuminatedSignPackageID

    static func inspectionPackage(
        from source: SignPack = .illuminatedSignV1
    ) throws -> InspectionPackageV2 {
        // The bundled V1 resource remains the canonical shipping parity
        // source, while successor content versions may reuse this typed
        // adapter after passing the closed loader contract.
        guard SignPackLoader.valid(source),
              source.packID == packageID else {
            throw InspectionPackageFailureV2.unknownPackage
        }
        return try InspectionPackageV2(
            packageID: source.packID,
            contentVersion: source.contentVersion,
            capabilities: [
                .photoCapture,
                .photoImport,
                .visibleIssueClassification,
                .couldNotVerify,
                .recheck,
                .workEvidence,
            ],
            permissions: [.camera, .photoLibrarySelection],
            advisoryGuidance: [
                InspectionPackageGuidanceV2(
                    guidanceID: "evidence.required_views",
                    kind: .evidence,
                    localizationKey: "package.illuminated_sign.guidance.required_views"
                ),
                InspectionPackageGuidanceV2(
                    guidanceID: "limitation.visible_conditions_only",
                    kind: .limitation,
                    localizationKey: "package.illuminated_sign.guidance.visible_conditions_only"
                ),
                InspectionPackageGuidanceV2(
                    guidanceID: "safety.authorized_position",
                    kind: .safety,
                    localizationKey: "package.illuminated_sign.guidance.authorized_position"
                ),
            ],
            presentation: InspectionPackagePresentationV2(
                assetSingular: source.nouns.asset.singular,
                assetPlural: source.nouns.asset.plural,
                checkSingular: source.nouns.check.singular,
                checkPlural: source.nouns.check.plural,
                issueSingular: source.nouns.issue.singular,
                issuePlural: source.nouns.issue.plural,
                evidencePurposes: source.evidencePurposes.map {
                    InspectionPackageEvidencePurposeV2(
                        key: $0.key,
                        display: $0.display,
                        instruction: $0.instruction
                    )
                },
                acknowledgements: source.acknowledgements.map {
                    InspectionPackageAcknowledgementV2(
                        key: $0.key,
                        copy: $0.copy,
                        version: $0.version
                    )
                },
                issueLabels: entries(source.issueLabels),
                couldNotVerifyRegistryVersion: source.couldNotVerifyReasons.version,
                couldNotVerifyReasons: entries(source.couldNotVerifyReasons.entries),
                stageDisplays: entries(source.stageDisplays),
                outcomeDisplays: entries(source.outcomeDisplays),
                disclaimer: source.disclaimer
            )
        )
    }

    static func signPack(from package: InspectionPackageV2) throws -> SignPack {
        try InspectionPackageCompatibilityValidatorV2.validate(package)
        let expected = try inspectionPackage()
        guard package.packageID == packageID, package.contentVersion > 0,
              package.capabilities == expected.capabilities,
              package.permissions == expected.permissions,
              package.advisoryGuidance == expected.advisoryGuidance else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        let value = package.presentation
        let result = SignPack(
            schemaVersion: 1,
            packID: package.packageID,
            contentVersion: package.contentVersion,
            nouns: .init(
                asset: .init(singular: value.assetSingular, plural: value.assetPlural),
                check: .init(singular: value.checkSingular, plural: value.checkPlural),
                issue: .init(singular: value.issueSingular, plural: value.issuePlural)
            ),
            evidencePurposes: value.evidencePurposes.map {
                .init(key: $0.key, display: $0.display, instruction: $0.instruction)
            },
            acknowledgements: value.acknowledgements.map {
                .init(key: $0.key, copy: $0.copy, version: $0.version)
            },
            issueLabels: signEntries(value.issueLabels),
            couldNotVerifyReasons: .init(
                version: value.couldNotVerifyRegistryVersion,
                entries: signEntries(value.couldNotVerifyReasons)
            ),
            stageDisplays: signEntries(value.stageDisplays),
            outcomeDisplays: signEntries(value.outcomeDisplays),
            disclaimer: value.disclaimer
        )
        guard SignPackLoader.valid(result), result.packID == packageID else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        return result
    }

    static func parityReceipt() throws -> ShippingIlluminatedSignParityReceiptV1 {
        let source = SignPack.illuminatedSignV1
        let package = try inspectionPackage(from: source)
        let roundTrip = try signPack(from: package)
        let sourceData = try canonicalSignPack(source)
        let roundTripData = try canonicalSignPack(roundTrip)
        return ShippingIlluminatedSignParityReceiptV1(
            packageID: source.packID,
            sourceSchemaVersion: source.schemaVersion,
            sourceContentVersion: source.contentVersion,
            inspectionPackageSchemaVersion: package.schemaVersion,
            sourceCanonicalSHA256: digest(sourceData),
            roundTripCanonicalSHA256: digest(roundTripData),
            exactParity: sourceData == roundTripData && source == roundTrip
        )
    }

    /// Identifies the native finalizer's concrete check or recheck contract.
    /// Deriving these bytes does not publish an inspection-package release.
    /// A Round must separately hold the published release with these exact
    /// package and workflow bytes before it can use the resulting completion.
    static func finalizationInspectionRelease(
        from source: SignPack,
        stage: WorkflowStage
    ) throws -> FinalizationInspectionReleaseBindingV1 {
        let package = try inspectionPackage(from: source)
        let roundTrip = try signPack(from: package)
        let sourceBytes = try canonicalSignPack(source)
        guard roundTrip == source,
              try canonicalSignPack(roundTrip) == sourceBytes else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        let workflow = try finalizationWorkflow(from: source, stage: stage)
        let release = try InspectionPackageReleaseV1.makeDraft(package: package, workflow: workflow)
        return try FinalizationInspectionReleaseBindingV1(
            packageReleaseID: release.packageReleaseID,
            packageID: release.packageID,
            packageContentVersion: release.packageContentVersion,
            packageSHA256: release.packageSHA256,
            workflowSHA256: release.workflowSHA256,
            sourcePackSHA256: digest(sourceBytes)
        )
    }

    /// This is the closed finalization workflow over the incumbent native
    /// runner's retained facts. The native finalizer still owns execution,
    /// file validation, temporal truth and the canonical writer transaction.
    /// Optional-view branches preserve its early could-not-verify outcomes,
    /// including the validated zero-, one- and two-view cases.
    static func finalizationWorkflow(
        from source: SignPack,
        stage: WorkflowStage
    ) throws -> WorkflowDefinitionV1 {
        _ = try inspectionPackage(from: source)
        guard stage == .check || stage == .recheck else {
            throw InspectionKernelFailureV1.invalidValue
        }
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: source)
        let selected = try profile.stage(stage.rawValue)
        guard profile.requiredAcknowledgementKeys == ["after_dark", "safe_authorized_position"],
              profile.evidencePurposeKeys(for: .captureRequired) == ["wide_context", "close_detail"] else {
            throw InspectionKernelFailureV1.invalidValue
        }
        let couldNotVerify = selected.outcomes.filter { $0.role == .couldNotVerify }
        let withCondition = selected.outcomes.filter {
            stage == .check ? $0.role == .findingObserved : $0.role == .originalResolvedDifferentFinding
        }
        let completeOutcomes = selected.outcomes.filter { $0.role != .couldNotVerify }.map(\.key).sorted()
        guard couldNotVerify.count == 1, withCondition.count == 1,
              !completeOutcomes.isEmpty else { throw InspectionKernelFailureV1.invalidValue }

        let prefix = "native.sign.finalization."
        let afterDark = prefix + "after_dark"
        let safePosition = prefix + "safe_authorized_position"
        let wide = prefix + "wide_present"
        let close = prefix + "close_present"
        let outcome = prefix + "outcome"
        let condition = prefix + "condition"
        let reason = prefix + "could_not_verify_reason"
        let note = prefix + "could_not_verify_note"
        var nodes: [WorkflowNodeV1] = []
        func fact(_ id: String, _ field: String, _ key: String, next: String) throws {
            nodes.append(try .init(nodeID: id, kind: .fact, localizationKey: key,
                                   fieldID: field, outgoingNodeIDs: [next]))
        }
        func equals(_ field: String, _ value: String) throws -> BranchPredicateV1 {
            try .init(kind: .equals, fieldID: field, optionID: value)
        }
        func branch(_ id: String, _ predicate: BranchPredicateV1,
                    yes: String, no: String, unknown: String = "blocked") throws {
            nodes.append(try .init(nodeID: id, kind: .branch, predicate: predicate,
                branchDestinations: .init(trueNodeID: yes, falseNodeID: no, unknownNodeID: unknown),
                outgoingNodeIDs: [yes, no, unknown]))
        }
        func evidence(_ id: String, _ purpose: String, next: String) throws {
            nodes.append(try .init(nodeID: id, kind: .evidenceRequest,
                localizationKey: "illuminated.playbook.capture." + purpose,
                evidencePurposeID: purpose, outgoingNodeIDs: [next]))
        }

        try fact("after_dark", afterDark, "illuminated.playbook.preflight.after_dark", next: "safe_position")
        try fact("safe_position", safePosition, "illuminated.playbook.preflight.safe_authorized_position", next: "preflight")
        try branch("preflight", .init(kind: .all, operands: [
            equals(afterDark, "accepted"), equals(safePosition, "accepted")
        ]), yes: "wide_present", no: "blocked")
        try fact("wide_present", wide, "illuminated.playbook.capture.wide_context", next: "wide_known")
        try branch("wide_known", .init(kind: .inSet, fieldID: wide, optionIDs: ["absent", "present"]),
                   yes: "wide_branch", no: "blocked")
        try branch("wide_branch", equals(wide, "present"), yes: "wide_evidence", no: "close_present")
        try evidence("wide_evidence", "wide_context", next: "close_present")
        try fact("close_present", close, "illuminated.playbook.capture.close_detail", next: "close_known")
        try branch("close_known", .init(kind: .inSet, fieldID: close, optionIDs: ["absent", "present"]),
                   yes: "close_branch", no: "blocked")
        try branch("close_branch", equals(close, "present"), yes: "close_evidence", no: "outcome")
        try evidence("close_evidence", "close_detail", next: "outcome")
        try fact("outcome", outcome, "illuminated.playbook.facts.outcome", next: "could_not_verify")
        try branch("could_not_verify", equals(outcome, couldNotVerify[0].key),
                   yes: "could_not_verify_reason", no: "required_views")
        try fact("could_not_verify_reason", reason, "illuminated.playbook.facts.could_not_verify_reason", next: "reason_allowed")
        try branch("reason_allowed", .init(kind: .inSet, fieldID: reason,
            optionIDs: source.couldNotVerifyReasons.entries.map(\.key).sorted()),
            yes: "could_not_verify_note", no: "blocked")
        try fact("could_not_verify_note", note, "illuminated.playbook.facts.report_trace", next: "review_could_not_verify")
        try branch("required_views", .init(kind: .all, operands: [
            equals(wide, "present"), equals(close, "present")
        ]), yes: "outcome_allowed", no: "blocked")
        try branch("outcome_allowed", .init(kind: .inSet, fieldID: outcome, optionIDs: completeOutcomes),
                   yes: "condition_required", no: "blocked")
        try branch("condition_required", equals(outcome, withCondition[0].key),
                   yes: "condition", no: "review_completed")
        try fact("condition", condition, "illuminated.playbook.facts.selected_condition", next: "condition_allowed")
        try branch("condition_allowed", .init(kind: .inSet, fieldID: condition,
            optionIDs: source.issueLabels.map(\.key).sorted()), yes: "review_completed", no: "blocked")
        nodes.append(try .init(nodeID: "review_completed", kind: .review,
            localizationKey: "illuminated.playbook.facts.report_trace", outgoingNodeIDs: ["completed"]))
        nodes.append(try .init(nodeID: "review_could_not_verify", kind: .review,
            localizationKey: "illuminated.playbook.facts.report_trace", outgoingNodeIDs: ["completed_could_not_verify"]))
        nodes.append(try .init(nodeID: "completed", kind: .terminal,
            localizationKey: "illuminated.playbook.facts.outcome", outgoingNodeIDs: []))
        nodes.append(try .init(nodeID: "completed_could_not_verify", kind: .terminal,
            localizationKey: "illuminated.playbook.facts.outcome.could_not_verify", outgoingNodeIDs: []))
        nodes.append(try .init(nodeID: "blocked", kind: .terminal,
            localizationKey: "illuminated.playbook.state.blocked", outgoingNodeIDs: []))
        let value = try WorkflowDefinitionV1(workflowID: prefix + stage.rawValue + ".v1",
            entryNodeID: "after_dark", declaredFieldIDs: [afterDark, safePosition, wide, close, outcome, condition, reason, note],
            nodes: nodes)
        _ = try WorkflowGraphValidatorV1.validate(value)
        return value
    }

    /// The only sign-specific response mapping. The neutral inspection kernel
    /// remains package-agnostic and receives only its closed typed values.
    static func typedResponses(
        from source: LegacySignResponseSourceV1,
        signPack: SignPack = .illuminatedSignV1
    ) throws -> LegacySignTypedResponseMappingV1 {
        guard SignPackLoader.valid(signPack),
              signPack.packID == packageID else {
            throw ResponseContractFailureV1.invalidValue
        }
        let acknowledgementKeys = signPack.acknowledgements.map(\.key)
        guard Set(source.acknowledgementValues.keys).isSubset(of: Set(acknowledgementKeys)) else {
            throw ResponseContractFailureV1.unknownKind
        }
        let outcomeKeys = Set(signPack.outcomeDisplays.map(\.key))
        if let outcomeKey = source.outcomeKey, !outcomeKeys.contains(outcomeKey) {
            throw ResponseContractFailureV1.unknownKind
        }
        let issueKeys = source.issueKeys.sorted()
        guard Set(issueKeys).count == issueKeys.count,
              Set(issueKeys).isSubset(of: Set(signPack.issueLabels.map(\.key))) else {
            throw ResponseContractFailureV1.invalidValue
        }
        let cnvEntries = Dictionary(uniqueKeysWithValues:
            signPack.couldNotVerifyReasons.entries.map { ($0.key, $0.display) }
        )
        if let cnv = source.couldNotVerify {
            guard source.outcomeKey == "could_not_verify",
                  cnv.registryVersion == signPack.couldNotVerifyReasons.version,
                  cnvEntries[cnv.reasonKey] == cnv.frozenDisplay else {
                throw ResponseContractFailureV1.invalidValue
            }
        } else if source.outcomeKey == "could_not_verify" {
            throw ResponseContractFailureV1.invalidValue
        }
        if source.outcomeKey != "could_not_verify", source.couldNotVerify != nil {
            throw ResponseContractFailureV1.invalidValue
        }
        if let note = source.note, note.utf8.count > ResponseValueV1.maximumTextUTF8Bytes {
            throw ResponseContractFailureV1.limitExceeded
        }

        var responses = acknowledgementKeys.map { key in
            LegacySignTypedResponseEntryV1(
                fieldID: "legacy.acknowledgement.\(key)",
                value: source.acknowledgementValues[key].map(ResponseValueV1.boolean) ?? .noValue
            )
        }
        responses.append(.init(
            fieldID: "legacy.outcome",
            value: source.outcomeKey.map(ResponseValueV1.singleOption) ?? .noValue
        ))
        responses.append(.init(
            fieldID: "legacy.issues",
            value: issueKeys.isEmpty ? .noValue : .multipleOptions(issueKeys)
        ))
        responses.append(.init(
            fieldID: "legacy.could_not_verify.reason",
            value: source.couldNotVerify.map { .singleOption($0.reasonKey) } ?? .noValue
        ))
        responses.append(.init(
            fieldID: "legacy.note",
            value: source.note.map(ResponseValueV1.text) ?? .noValue
        ))
        responses.append(.init(
            fieldID: "legacy.entity_reference",
            value: source.entityReference.map(ResponseValueV1.entityReference) ?? .noValue
        ))
        responses.append(.init(
            fieldID: "legacy.content_reference",
            value: source.contentReference.map(ResponseValueV1.contentReference) ?? .noValue
        ))
        responses.sort { $0.fieldID < $1.fieldID }
        try responses.forEach { try $0.value.validate() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(responses)
        let packageParity = try parityReceipt()
        return LegacySignTypedResponseMappingV1(
            responses: responses,
            receipt: LegacySignTypedResponseMappingReceiptV1(
                packageID: signPack.packID,
                packageContentVersion: signPack.contentVersion,
                couldNotVerifyRegistryVersion: signPack.couldNotVerifyReasons.version,
                couldNotVerifyFrozenDisplay: source.couldNotVerify?.frozenDisplay,
                shippingPackCanonicalSHA256: packageParity.sourceCanonicalSHA256,
                orderedFieldIDs: responses.map(\.fieldID),
                canonicalResponsesSHA256: digest(bytes),
                exactSemanticParity: true,
                inventedMeasurementCount: 0
            )
        )
    }

    static func playbookRegistry(
        release: InspectionPackageReleaseV1,
        draftCodec: DraftPayloadCodecReleaseV1,
        source: SignPack = .illuminatedSignV1
    ) throws -> IlluminatedSignPlaybookRegistryV1 {
        try release.validate(); try draftCodec.validate()
        guard release.state == .published,
              SignPackLoader.valid(source), source.packID == packageID else {
            throw IlluminatedSignPlaybookFailureV1.releaseMismatch
        }
        let expectedPackage = try inspectionPackage(from: source)
        let releasedPackage = try InspectionPackageCanonicalCodecV2.decode(release.canonicalPackageBytes)
        guard releasedPackage == expectedPackage,
              release.packageID == source.packID,
              release.packageContentVersion == source.contentVersion else {
            throw IlluminatedSignPlaybookFailureV1.releaseMismatch
        }
        let sourceSHA256 = digest(try canonicalSignPack(source))
        let requirements = try IlluminatedSignCaptureSlotIDV1.canonicalOrder.map {
            try IlluminatedSignCaptureRequirementV1(
                slotID: $0, purposeKey: $0.rawValue, required: $0 != .workContext
            )
        }
        let manifests = try IlluminatedSignPlaybookIDV1.canonicalOrder.map {
            try IlluminatedSignPlaybookManifestV1(
                playbookID: $0, release: release, sourcePackSHA256: sourceSHA256,
                captureRequirements: requirements
            )
        }
        let issuePairs = source.issueLabels.map { ($0.key, $0.display) }
        guard Set(issuePairs.map(\.0)).count == issuePairs.count else {
            throw IlluminatedSignPlaybookFailureV1.registryMismatch
        }
        var visibleDisplays = Dictionary(uniqueKeysWithValues: issuePairs)
        visibleDisplays[IlluminatedSignPlaybookIDV1.generalVisibleCondition.rawValue] = "General visible condition"
        let cnvPairs = source.couldNotVerifyReasons.entries.map { ($0.key, $0.display) }
        guard Set(cnvPairs.map(\.0)).count == cnvPairs.count else {
            throw IlluminatedSignPlaybookFailureV1.registryMismatch
        }
        return try IlluminatedSignPlaybookRegistryV1(
            release: release, sourcePackSHA256: sourceSHA256, draftCodec: draftCodec,
            manifests: manifests, evidencePurposeKeys: source.evidencePurposes.map(\.key),
            visibleConditionDisplays: visibleDisplays,
            disclaimer: source.disclaimer,
            couldNotVerifyRegistryVersion: source.couldNotVerifyReasons.version,
            couldNotVerifyReasons: Dictionary(uniqueKeysWithValues: cnvPairs)
        )
    }

    private static func entries(
        _ values: [SignPack.RegistryEntry]
    ) -> [InspectionPackageDisplayEntryV2] {
        values.map { InspectionPackageDisplayEntryV2(key: $0.key, display: $0.display) }
    }

    private static func signEntries(
        _ values: [InspectionPackageDisplayEntryV2]
    ) -> [SignPack.RegistryEntry] {
        values.map { SignPack.RegistryEntry(key: $0.key, display: $0.display) }
    }

    private static func canonicalSignPack(_ value: SignPack) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
