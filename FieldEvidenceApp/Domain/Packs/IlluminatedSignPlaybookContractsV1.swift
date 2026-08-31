import Foundation

enum IlluminatedSignPlaybookFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case limitExceeded
    case releaseMismatch
    case registryMismatch
    case staleEvidence
    case missingCapture
    case invalidPose
    case invalidCheckpoint
    case digestMismatch
    case recoveryConflict
}

enum IlluminatedSignPlaybookLimitsV1 {
    static let maximumCanonicalBytes = 2 * 1_024 * 1_024
    static let maximumCaptureTraces = 3
    static let maximumFacts = 7
    static let maximumHistoryEvents = 512
}

enum IlluminatedSignPlaybookLifecycleV1 {
    static let persistence = "NONPERSISTENT_DIGEST_BOUND_SIDECAR"
    static let schema = "NOT_APPLICABLE"
    static let store = "NOT_APPLICABLE"
    static let writer = "INCUMBENT_FIELD_DRAFT_AND_POSE_AUTHORITIES"
    static let evidence = "INCUMBENT_C05_EVIDENCE_METADATA_AUTHORITY"
    static let backupRestoreDeleteErase = "NOT_APPLICABLE_DERIVED_FROM_DURABLE_AUTHORITIES"
    static let networkDependency = false
    static let certificationAuthority = false
}

enum IlluminatedSignPlaybookIDV1: String, CaseIterable, Codable, Hashable, Sendable {
    case generalVisibleCondition = "general_visible_condition"
    case darkSection = "dark_section"
    case dimOrUneven = "dim_or_uneven"
    case flickerOrIntermittent = "flicker_or_intermittent"
    case colorMismatch = "color_mismatch"
    case physicalDamage = "physical_damage"
    case otherVisibleCondition = "other_visible_condition"

    static let canonicalOrder: [Self] = [
        .generalVisibleCondition, .darkSection, .dimOrUneven,
        .flickerOrIntermittent, .colorMismatch, .physicalDamage,
        .otherVisibleCondition,
    ]
}

enum IlluminatedSignCaptureSlotIDV1: String, CaseIterable, Codable, Hashable, Sendable {
    case wideContext = "wide_context"
    case closeDetail = "close_detail"
    case workContext = "work_context"

    static let canonicalOrder: [Self] = [.wideContext, .closeDetail, .workContext]
}

enum IlluminatedSignPlaybookOutcomeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case noVisibleIssue = "no_visible_issue"
    case visibleIssue = "visible_issue"
    case couldNotVerify = "could_not_verify"
}

enum IlluminatedSignPlaybookStageV1: String, CaseIterable, Codable, Hashable, Sendable {
    case check = "check"
    case recheck = "recheck"
}

struct IlluminatedSignCheckedTimeV1: Codable, Equatable, Sendable {
    let context: TimeContextSnapshotV1

    init(context: TimeContextSnapshotV1) throws {
        guard context.observedAtUTC.timeIntervalSinceReferenceDate.isFinite,
              !context.localDate.isEmpty, !context.localTime.isEmpty,
              !context.timeZoneID.isEmpty, TimeZone(identifier: context.timeZoneID) != nil,
              (-24 * 60 ... 24 * 60).contains(context.utcOffsetMinutes) else {
            throw IlluminatedSignPlaybookFailureV1.invalidValue
        }
        let frozen = try TimeContextRule.freeze(
            observedAtUTC: context.observedAtUTC,
            confirmedTimeZoneID: context.timeZoneID
        )
        guard frozen.localDate == context.localDate, frozen.localTime == context.localTime,
              frozen.utcOffsetMinutes == context.utcOffsetMinutes else {
            throw IlluminatedSignPlaybookFailureV1.invalidValue
        }
        self.context = context
    }

    func validate() throws { guard self == (try Self(context: context)) else { throw IlluminatedSignPlaybookFailureV1.invalidValue } }
}

struct IlluminatedSignSelectedVisibleConditionV1: Codable, Equatable, Hashable, Sendable {
    let playbookID: IlluminatedSignPlaybookIDV1
    let frozenDisplay: String

    init(playbookID: IlluminatedSignPlaybookIDV1, frozenDisplay: String) throws {
        guard !frozenDisplay.isEmpty,
              frozenDisplay == frozenDisplay.trimmingCharacters(in: .whitespacesAndNewlines),
              frozenDisplay.utf8.count <= 512 else {
            throw IlluminatedSignPlaybookFailureV1.invalidValue
        }
        self.playbookID = playbookID
        self.frozenDisplay = frozenDisplay
    }
    func validate() throws { guard self == (try Self(playbookID: playbookID, frozenDisplay: frozenDisplay)) else { throw IlluminatedSignPlaybookFailureV1.invalidValue } }
}

enum IlluminatedSignCompletenessStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case incomplete = "INCOMPLETE"
    case complete = "COMPLETE"
    case couldNotVerify = "COULD_NOT_VERIFY"
}

enum IlluminatedSignPoseRequirementV1: String, CaseIterable, Codable, Hashable, Sendable {
    case requiredDeclaredAxis = "REQUIRED_DECLARED_AXIS"
}

enum IlluminatedSignVisibleConditionClaimV1: String, CaseIterable, Codable, Hashable, Sendable {
    case visibleConditionsOnly = "VISIBLE_CONDITIONS_ONLY"
}

enum IlluminatedSignPlaybookDraftScopeV1 {
    static let scopeKind = "illuminated-sign-playbook"
    static func make(subject: EvidenceAssociationTargetV1,
                     playbookID: IlluminatedSignPlaybookIDV1) throws -> DraftScopeKeyV1 {
        try DraftScopeKeyV1(scopeKind: scopeKind,
                            stableComponentIDs: [
                                "workspace:\(subject.workspaceID)",
                                "kind:\(subject.kind.rawValue)",
                                "target:\(subject.targetID)",
                                "target-revision:\(subject.targetRevision)",
                                "playbook:\(playbookID.rawValue)",
                            ])
    }
    static func validate(_ scope: DraftScopeKeyV1,
                         subject: EvidenceAssociationTargetV1,
                         playbookID: IlluminatedSignPlaybookIDV1) throws {
        guard scope == (try make(subject: subject, playbookID: playbookID)) else {
            throw IlluminatedSignPlaybookFailureV1.invalidCheckpoint
        }
    }
}

struct IlluminatedSignCaptureRequirementV1: Codable, Equatable, Hashable, Sendable {
    let slotID: IlluminatedSignCaptureSlotIDV1
    let purposeKey: String
    let required: Bool

    init(slotID: IlluminatedSignCaptureSlotIDV1, purposeKey: String, required: Bool) throws {
        guard purposeKey == slotID.rawValue,
              required == (slotID != .workContext) else {
            throw IlluminatedSignPlaybookFailureV1.invalidValue
        }
        self.slotID = slotID
        self.purposeKey = purposeKey
        self.required = required
    }
}

struct IlluminatedSignCouldNotVerifyV1: Codable, Equatable, Hashable, Sendable {
    let reasonKey: String
    let frozenDisplay: String
    let registryVersion: String

    init(reasonKey: String, frozenDisplay: String, registryVersion: String) throws {
        guard Self.validText(reasonKey, maximumBytes: 128),
              Self.validText(frozenDisplay, maximumBytes: 512),
              Self.validText(registryVersion, maximumBytes: 128) else {
            throw IlluminatedSignPlaybookFailureV1.invalidValue
        }
        self.reasonKey = reasonKey
        self.frozenDisplay = frozenDisplay
        self.registryVersion = registryVersion
    }

    func validate() throws { guard self == (try Self(reasonKey: reasonKey, frozenDisplay: frozenDisplay, registryVersion: registryVersion)) else { throw IlluminatedSignPlaybookFailureV1.invalidValue } }

    private static func validText(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.utf8.count <= maximumBytes
    }
}

struct IlluminatedSignPlaybookManifestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let playbookID: IlluminatedSignPlaybookIDV1
    let manifestVersion: UInt64
    let packageReleaseID: String
    let packageID: String
    let packageContentVersion: Int
    let packageSHA256: String
    let workflowSHA256: String
    let sourcePackSHA256: String
    let captureRequirements: [IlluminatedSignCaptureRequirementV1]
    let poseRequirement: IlluminatedSignPoseRequirementV1
    let visibleConditionClaim: IlluminatedSignVisibleConditionClaimV1
    let comparisonIsProof: Bool
    let electricalCertification: Bool
    let safetyCertification: Bool
    let reportSectionID: String
    let reportSectionVersion: UInt64
    let manifestSHA256: String

    init(playbookID: IlluminatedSignPlaybookIDV1, manifestVersion: UInt64 = 1,
         release: InspectionPackageReleaseV1, sourcePackSHA256: String,
         captureRequirements: [IlluminatedSignCaptureRequirementV1],
         poseRequirement: IlluminatedSignPoseRequirementV1 = .requiredDeclaredAxis,
         reportSectionVersion: UInt64 = 1) throws {
        try release.validate()
        let requirements = captureRequirements.sorted { lhs, rhs in
            Self.slotIndex(lhs.slotID) < Self.slotIndex(rhs.slotID)
        }
        schemaVersion = Self.schemaVersion
        self.playbookID = playbookID
        self.manifestVersion = manifestVersion
        packageReleaseID = release.packageReleaseID
        packageID = release.packageID
        packageContentVersion = release.packageContentVersion
        packageSHA256 = release.packageSHA256
        workflowSHA256 = release.workflowSHA256
        self.sourcePackSHA256 = sourcePackSHA256
        self.captureRequirements = requirements
        self.poseRequirement = poseRequirement
        visibleConditionClaim = .visibleConditionsOnly
        comparisonIsProof = false
        electricalCertification = false
        safetyCertification = false
        reportSectionID = "illuminated_sign.playbook.\(playbookID.rawValue)"
        self.reportSectionVersion = reportSectionVersion
        manifestSHA256 = try IlluminatedSignPlaybookCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, playbookID: playbookID,
            manifestVersion: manifestVersion, packageReleaseID: release.packageReleaseID,
            packageID: release.packageID, packageContentVersion: release.packageContentVersion,
            packageSHA256: release.packageSHA256, workflowSHA256: release.workflowSHA256,
            sourcePackSHA256: sourcePackSHA256, captureRequirements: requirements,
            poseRequirement: poseRequirement, visibleConditionClaim: .visibleConditionsOnly,
            comparisonIsProof: false, electricalCertification: false,
            safetyCertification: false,
            reportSectionID: "illuminated_sign.playbook.\(playbookID.rawValue)",
            reportSectionVersion: reportSectionVersion
        ))
        try validate(against: release)
    }

    func validate(against release: InspectionPackageReleaseV1) throws {
        try release.validate()
        let expectedSlots = IlluminatedSignCaptureSlotIDV1.canonicalOrder
        guard schemaVersion == Self.schemaVersion, manifestVersion > 0,
              packageReleaseID == release.packageReleaseID, packageID == release.packageID,
              packageContentVersion == release.packageContentVersion,
              packageSHA256 == release.packageSHA256, workflowSHA256 == release.workflowSHA256,
              KernelCanonicalHashV1.validSHA256(sourcePackSHA256),
              captureRequirements.map(\.slotID) == expectedSlots,
              Set(captureRequirements.map(\.slotID)).count == expectedSlots.count,
              captureRequirements.allSatisfy({ $0.purposeKey == $0.slotID.rawValue && $0.required == ($0.slotID != .workContext) }),
              visibleConditionClaim == .visibleConditionsOnly, !comparisonIsProof,
              !electricalCertification, !safetyCertification,
              reportSectionID == "illuminated_sign.playbook.\(playbookID.rawValue)",
              reportSectionVersion > 0,
              manifestSHA256 == (try IlluminatedSignPlaybookCanonicalCodecV1.sha256(basis)) else {
            throw IlluminatedSignPlaybookFailureV1.releaseMismatch
        }
    }

    private static func slotIndex(_ slot: IlluminatedSignCaptureSlotIDV1) -> Int {
        IlluminatedSignCaptureSlotIDV1.canonicalOrder.firstIndex(of: slot) ?? Int.max
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, playbookID: playbookID,
        manifestVersion: manifestVersion, packageReleaseID: packageReleaseID, packageID: packageID,
        packageContentVersion: packageContentVersion, packageSHA256: packageSHA256,
        workflowSHA256: workflowSHA256, sourcePackSHA256: sourcePackSHA256,
        captureRequirements: captureRequirements, poseRequirement: poseRequirement,
        visibleConditionClaim: visibleConditionClaim, comparisonIsProof: comparisonIsProof,
        electricalCertification: electricalCertification, safetyCertification: safetyCertification,
        reportSectionID: reportSectionID, reportSectionVersion: reportSectionVersion) }
    private struct Basis: Codable { let schemaVersion: Int; let playbookID: IlluminatedSignPlaybookIDV1; let manifestVersion: UInt64; let packageReleaseID: String; let packageID: String; let packageContentVersion: Int; let packageSHA256: String; let workflowSHA256: String; let sourcePackSHA256: String; let captureRequirements: [IlluminatedSignCaptureRequirementV1]; let poseRequirement: IlluminatedSignPoseRequirementV1; let visibleConditionClaim: IlluminatedSignVisibleConditionClaimV1; let comparisonIsProof: Bool; let electricalCertification: Bool; let safetyCertification: Bool; let reportSectionID: String; let reportSectionVersion: UInt64 }
}

struct IlluminatedSignPlaybookRegistryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let release: InspectionPackageReleaseV1
    let sourcePackSHA256: String
    let draftCodec: DraftPayloadCodecReleaseV1
    let manifests: [IlluminatedSignPlaybookManifestV1]
    let evidencePurposeKeys: [String]
    let visibleConditionDisplays: [String: String]
    let disclaimer: String
    let couldNotVerifyRegistryVersion: String
    let couldNotVerifyReasons: [String: String]
    let registrySHA256: String

    init(release: InspectionPackageReleaseV1, sourcePackSHA256: String,
         draftCodec: DraftPayloadCodecReleaseV1,
         manifests: [IlluminatedSignPlaybookManifestV1], evidencePurposeKeys: [String],
         visibleConditionDisplays: [String: String],
         disclaimer: String,
         couldNotVerifyRegistryVersion: String, couldNotVerifyReasons: [String: String]) throws {
        let orderedPurposes = evidencePurposeKeys.sorted()
        guard manifests.count == IlluminatedSignPlaybookIDV1.canonicalOrder.count,
              manifests.map(\.playbookID) == IlluminatedSignPlaybookIDV1.canonicalOrder,
              Set(manifests.map(\.playbookID)).count == manifests.count else {
            throw IlluminatedSignPlaybookFailureV1.registryMismatch
        }
        let orderedManifests = manifests
        schemaVersion = Self.schemaVersion
        self.release = release
        self.sourcePackSHA256 = sourcePackSHA256
        self.draftCodec = draftCodec
        self.manifests = orderedManifests
        self.evidencePurposeKeys = orderedPurposes
        self.visibleConditionDisplays = visibleConditionDisplays
        self.disclaimer = disclaimer
        self.couldNotVerifyRegistryVersion = couldNotVerifyRegistryVersion
        self.couldNotVerifyReasons = couldNotVerifyReasons
        registrySHA256 = try IlluminatedSignPlaybookCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, release: release, sourcePackSHA256: sourcePackSHA256,
            draftCodec: draftCodec, manifests: orderedManifests, evidencePurposeKeys: orderedPurposes,
            visibleConditionDisplays: visibleConditionDisplays,
            disclaimer: disclaimer,
            couldNotVerifyRegistryVersion: couldNotVerifyRegistryVersion,
            couldNotVerifyReasons: couldNotVerifyReasons
        ))
        try validate()
    }

    func validate() throws {
        try release.validate(); try draftCodec.validate()
        try manifests.forEach { try $0.validate(against: release) }
        let ids = manifests.map(\.playbookID)
        guard schemaVersion == Self.schemaVersion, ids == IlluminatedSignPlaybookIDV1.canonicalOrder,
              Set(ids).count == IlluminatedSignPlaybookIDV1.allCases.count,
              manifests.allSatisfy({ $0.sourcePackSHA256 == sourcePackSHA256 }),
              evidencePurposeKeys == evidencePurposeKeys.sorted(), Set(evidencePurposeKeys).count == evidencePurposeKeys.count,
              evidencePurposeKeys == IlluminatedSignCaptureSlotIDV1.canonicalOrder.map(\.rawValue).sorted(),
              Set(visibleConditionDisplays.keys) == Set(IlluminatedSignPlaybookIDV1.allCases.map(\.rawValue)),
              visibleConditionDisplays.values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }),
              !disclaimer.isEmpty, disclaimer.utf8.count <= 2_048,
              Set(couldNotVerifyReasons.keys) == Set(["conditions_changed", "access_lost", "unsafe_to_continue", "required_view_obstructed", "capture_unavailable", "other"]),
              !couldNotVerifyReasons.isEmpty,
              couldNotVerifyReasons.keys.allSatisfy({ !$0.isEmpty }),
              couldNotVerifyReasons.values.allSatisfy({ !$0.isEmpty }),
              registrySHA256 == (try IlluminatedSignPlaybookCanonicalCodecV1.sha256(basis)) else {
            throw IlluminatedSignPlaybookFailureV1.registryMismatch
        }
    }

    func manifest(for id: IlluminatedSignPlaybookIDV1) throws -> IlluminatedSignPlaybookManifestV1 {
        let matches = manifests.filter { $0.playbookID == id }
        guard matches.count == 1 else { throw IlluminatedSignPlaybookFailureV1.registryMismatch }
        return matches[0]
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, release: release,
        sourcePackSHA256: sourcePackSHA256, draftCodec: draftCodec, manifests: manifests,
        evidencePurposeKeys: evidencePurposeKeys, visibleConditionDisplays: visibleConditionDisplays,
        disclaimer: disclaimer,
        couldNotVerifyRegistryVersion: couldNotVerifyRegistryVersion,
        couldNotVerifyReasons: couldNotVerifyReasons) }
    private struct Basis: Codable { let schemaVersion: Int; let release: InspectionPackageReleaseV1; let sourcePackSHA256: String; let draftCodec: DraftPayloadCodecReleaseV1; let manifests: [IlluminatedSignPlaybookManifestV1]; let evidencePurposeKeys: [String]; let visibleConditionDisplays: [String: String]; let disclaimer: String; let couldNotVerifyRegistryVersion: String; let couldNotVerifyReasons: [String: String] }
}

struct IlluminatedSignCaptureTraceV1: Codable, Equatable, Sendable {
    let slotID: IlluminatedSignCaptureSlotIDV1
    let purposeKey: String
    let item: EvidenceSequenceItemV1

    init(slotID: IlluminatedSignCaptureSlotIDV1, purposeKey: String,
         item: EvidenceSequenceItemV1) throws {
        guard purposeKey == slotID.rawValue else { throw IlluminatedSignPlaybookFailureV1.staleEvidence }
        self.slotID = slotID; self.purposeKey = purposeKey; self.item = item
    }
    func validate() throws { guard self == (try Self(slotID: slotID, purposeKey: purposeKey, item: item)) else { throw IlluminatedSignPlaybookFailureV1.staleEvidence } }
}

struct IlluminatedSignPoseTraceV1: Codable, Equatable, Sendable {
    let descriptor: PoseAxisDescriptorV1
    let event: AssetPoseEventV1
    let eventReference: AssetPoseEventReferenceV1

    init(descriptor: PoseAxisDescriptorV1, event: AssetPoseEventV1) throws {
        try descriptor.validate(); try event.validateIntrinsic()
        guard descriptor == event.axisDescriptor,
              descriptor.applicability == .applicable,
              descriptor.semanticRole == .signFaceNormal || descriptor.semanticRole == .assetForwardAxis else {
            throw IlluminatedSignPlaybookFailureV1.invalidPose
        }
        self.descriptor = descriptor; self.event = event; eventReference = event.reference
    }

    func validate(workspaceID: WorkspaceID) throws {
        try descriptor.validate(); try event.validateIntrinsic(); try eventReference.validate()
        guard event.workspaceID == workspaceID, descriptor == event.axisDescriptor,
              eventReference == event.reference,
              descriptor.applicability == .applicable,
              descriptor.semanticRole == .signFaceNormal || descriptor.semanticRole == .assetForwardAxis else {
            throw IlluminatedSignPlaybookFailureV1.invalidPose
        }
    }
}

struct IlluminatedSignPlaybookDraftPayloadV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let playbookID: IlluminatedSignPlaybookIDV1
    let subject: EvidenceAssociationTargetV1
    let registrySHA256: String
    let manifestSHA256: String
    let stage: IlluminatedSignPlaybookStageV1
    let checkedTime: IlluminatedSignCheckedTimeV1
    let selectedVisibleCondition: IlluminatedSignSelectedVisibleConditionV1?
    let captures: [IlluminatedSignCaptureTraceV1]
    let outcome: IlluminatedSignPlaybookOutcomeV1?
    let couldNotVerify: IlluminatedSignCouldNotVerifyV1?
    let poseTrace: IlluminatedSignPoseTraceV1?
    let payloadSHA256: String

    init(workspaceID: WorkspaceID, playbookID: IlluminatedSignPlaybookIDV1,
         registry: IlluminatedSignPlaybookRegistryV1,
         subject: EvidenceAssociationTargetV1,
         stage: IlluminatedSignPlaybookStageV1,
         checkedTime: IlluminatedSignCheckedTimeV1,
         selectedVisibleCondition: IlluminatedSignSelectedVisibleConditionV1? = nil,
         captures: [IlluminatedSignCaptureTraceV1] = [],
         outcome: IlluminatedSignPlaybookOutcomeV1? = nil,
         couldNotVerify: IlluminatedSignCouldNotVerifyV1? = nil,
         poseTrace: IlluminatedSignPoseTraceV1? = nil) throws {
        try registry.validate()
        let manifest = try registry.manifest(for: playbookID)
        let ordered = Self.ordered(captures)
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID
        self.playbookID = playbookID; self.subject = subject; registrySHA256 = registry.registrySHA256
        manifestSHA256 = manifest.manifestSHA256; self.stage = stage
        self.checkedTime = checkedTime; self.selectedVisibleCondition = selectedVisibleCondition
        self.captures = ordered
        self.outcome = outcome; self.couldNotVerify = couldNotVerify; self.poseTrace = poseTrace
        payloadSHA256 = try IlluminatedSignPlaybookCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, workspaceID: workspaceID, playbookID: playbookID, subject: subject,
            registrySHA256: registry.registrySHA256, manifestSHA256: manifest.manifestSHA256,
            stage: stage, checkedTime: checkedTime, selectedVisibleCondition: selectedVisibleCondition,
            captures: ordered, outcome: outcome, couldNotVerify: couldNotVerify, poseTrace: poseTrace
        ))
        try validate(registry: registry)
    }

    func validate(registry: IlluminatedSignPlaybookRegistryV1) throws {
        try registry.validate(); let manifest = try registry.manifest(for: playbookID)
        try checkedTime.validate(); try selectedVisibleCondition?.validate()
        try couldNotVerify?.validate(); try captures.forEach { try $0.validate() }
        try poseTrace?.validate(workspaceID: workspaceID)
        let slotIDs = captures.map(\.slotID)
        guard schemaVersion == Self.schemaVersion, registrySHA256 == registry.registrySHA256,
              subject.workspaceID == workspaceID.rawValue.uuidString.lowercased(), subject.kind == .asset,
              poseTrace.map({ $0.event.assetID.uuidString.lowercased() == subject.targetID }) ?? true,
              manifestSHA256 == manifest.manifestSHA256,
              captures.count <= IlluminatedSignPlaybookLimitsV1.maximumCaptureTraces,
              captures == Self.ordered(captures), Set(slotIDs).count == slotIDs.count,
              captures.allSatisfy({ trace in
                  trace.purposeKey == trace.slotID.rawValue
                    && trace.item.target == subject
              }),
              (outcome == .visibleIssue) == (selectedVisibleCondition != nil),
              selectedVisibleCondition.map({ $0.playbookID == playbookID && registry.visibleConditionDisplays[$0.playbookID.rawValue] == $0.frozenDisplay }) ?? true,
              (outcome == .couldNotVerify) == (couldNotVerify != nil),
              !(selectedVisibleCondition != nil && couldNotVerify != nil),
              couldNotVerify.map({ registry.couldNotVerifyRegistryVersion == $0.registryVersion && registry.couldNotVerifyReasons[$0.reasonKey] == $0.frozenDisplay }) ?? true,
              payloadSHA256 == (try IlluminatedSignPlaybookCanonicalCodecV1.sha256(basis)) else {
            throw IlluminatedSignPlaybookFailureV1.digestMismatch
        }
    }

    private static func ordered(_ captures: [IlluminatedSignCaptureTraceV1]) -> [IlluminatedSignCaptureTraceV1] {
        captures.sorted { lhs, rhs in
            (IlluminatedSignCaptureSlotIDV1.canonicalOrder.firstIndex(of: lhs.slotID) ?? Int.max)
                < (IlluminatedSignCaptureSlotIDV1.canonicalOrder.firstIndex(of: rhs.slotID) ?? Int.max)
        }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, workspaceID: workspaceID,
        playbookID: playbookID, subject: subject, registrySHA256: registrySHA256, manifestSHA256: manifestSHA256,
        stage: stage, checkedTime: checkedTime, selectedVisibleCondition: selectedVisibleCondition,
        captures: captures, outcome: outcome, couldNotVerify: couldNotVerify, poseTrace: poseTrace) }
    private struct Basis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let playbookID: IlluminatedSignPlaybookIDV1; let subject: EvidenceAssociationTargetV1; let registrySHA256: String; let manifestSHA256: String; let stage: IlluminatedSignPlaybookStageV1; let checkedTime: IlluminatedSignCheckedTimeV1; let selectedVisibleCondition: IlluminatedSignSelectedVisibleConditionV1?; let captures: [IlluminatedSignCaptureTraceV1]; let outcome: IlluminatedSignPlaybookOutcomeV1?; let couldNotVerify: IlluminatedSignCouldNotVerifyV1?; let poseTrace: IlluminatedSignPoseTraceV1? }
}

struct IlluminatedSignPlaybookCompletenessV1: Codable, Equatable, Sendable {
    let playbookID: IlluminatedSignPlaybookIDV1
    let state: IlluminatedSignCompletenessStateV1
    let missingRequiredSlots: [IlluminatedSignCaptureSlotIDV1]
    let hasReviewedPose: Bool
    let payloadSHA256: String
}

struct IlluminatedSignStructuredFactV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let subject: EvidenceAssociationTargetV1
    let playbookID: IlluminatedSignPlaybookIDV1
    let stage: IlluminatedSignPlaybookStageV1
    let checkedTime: IlluminatedSignCheckedTimeV1
    let selectedVisibleCondition: IlluminatedSignSelectedVisibleConditionV1?
    let outcome: IlluminatedSignPlaybookOutcomeV1
    let couldNotVerify: IlluminatedSignCouldNotVerifyV1?
    let captures: [IlluminatedSignCaptureTraceV1]
    let poseTrace: IlluminatedSignPoseTraceV1?
    let visibleConditionClaim: IlluminatedSignVisibleConditionClaimV1
    let comparisonIsProof: Bool
    let diagnosisClaimed: Bool
    let electricalCertification: Bool
    let safetyCertification: Bool
    let factSHA256: String

    init(payload: IlluminatedSignPlaybookDraftPayloadV1,
         completeness: IlluminatedSignPlaybookCompletenessV1,
         registry: IlluminatedSignPlaybookRegistryV1) throws {
        try payload.validate(registry: registry)
        let manifest = try registry.manifest(for: payload.playbookID)
        guard let outcome = payload.outcome else {
            throw IlluminatedSignPlaybookFailureV1.missingCapture
        }
        try Self.validateReportability(payload: payload, completeness: completeness, manifest: manifest)
        workspaceID = payload.workspaceID; subject = payload.subject
        playbookID = payload.playbookID; stage = payload.stage; checkedTime = payload.checkedTime
        selectedVisibleCondition = payload.selectedVisibleCondition; self.outcome = outcome
        couldNotVerify = payload.couldNotVerify; captures = payload.captures; poseTrace = payload.poseTrace
        visibleConditionClaim = .visibleConditionsOnly; comparisonIsProof = false
        diagnosisClaimed = false; electricalCertification = false; safetyCertification = false
        factSHA256 = try IlluminatedSignPlaybookCanonicalCodecV1.sha256(Basis(
            workspaceID: payload.workspaceID, subject: payload.subject,
            playbookID: payload.playbookID, stage: payload.stage, checkedTime: payload.checkedTime,
            selectedVisibleCondition: payload.selectedVisibleCondition,
            outcome: outcome, couldNotVerify: payload.couldNotVerify,
            captures: payload.captures, poseTrace: payload.poseTrace, visibleConditionClaim: .visibleConditionsOnly,
            comparisonIsProof: false, diagnosisClaimed: false,
            electricalCertification: false, safetyCertification: false
        ))
    }

    func validate(manifest: IlluminatedSignPlaybookManifestV1,
                  registry: IlluminatedSignPlaybookRegistryV1) throws {
        try checkedTime.validate(); try selectedVisibleCondition?.validate()
        try couldNotVerify?.validate(); try captures.forEach { try $0.validate() }
        if let poseTrace { try poseTrace.validate(workspaceID: poseTrace.event.workspaceID) }
        guard manifest.playbookID == playbookID,
              subject.workspaceID == workspaceID.rawValue.uuidString.lowercased(), subject.kind == .asset,
              captures.allSatisfy({ $0.item.target == subject }),
              poseTrace.map({ $0.event.workspaceID == workspaceID && $0.event.assetID.uuidString.lowercased() == subject.targetID }) ?? true,
              selectedVisibleCondition.map({ $0.playbookID == playbookID && registry.visibleConditionDisplays[$0.playbookID.rawValue] == $0.frozenDisplay }) ?? (outcome != .visibleIssue),
              (outcome == .visibleIssue) == (selectedVisibleCondition != nil),
              (outcome == .couldNotVerify) == (couldNotVerify != nil),
              couldNotVerify.map({ $0.registryVersion == registry.couldNotVerifyRegistryVersion && registry.couldNotVerifyReasons[$0.reasonKey] == $0.frozenDisplay }) ?? true,
              visibleConditionClaim == .visibleConditionsOnly, !comparisonIsProof,
              !diagnosisClaimed, !electricalCertification, !safetyCertification,
              factSHA256 == (try IlluminatedSignPlaybookCanonicalCodecV1.sha256(basis)) else {
            throw IlluminatedSignPlaybookFailureV1.digestMismatch
        }
        let required = Set(manifest.captureRequirements.filter(\.required).map(\.slotID))
        let actual = Set(captures.map(\.slotID))
        guard outcome == .couldNotVerify || (required.isSubset(of: actual) && poseTrace != nil),
              Set(captures.map { $0.item.evidenceID }).count == captures.count,
              Set(captures.map { $0.item.contentID }).count == captures.count,
              Set(captures.map { $0.item.associationBinding.associationEventID }).count == captures.count else {
            throw IlluminatedSignPlaybookFailureV1.missingCapture
        }
        if outcome == .couldNotVerify, poseTrace == nil {
            guard let reason = couldNotVerify?.reasonKey,
                  Self.poseOmissionReasons.contains(reason) else {
                throw IlluminatedSignPlaybookFailureV1.invalidPose
            }
        }
    }

    private static let poseOmissionReasons: Set<String> = [
        "access_lost", "unsafe_to_continue", "required_view_obstructed", "capture_unavailable",
    ]
    private static func validateReportability(payload: IlluminatedSignPlaybookDraftPayloadV1,
                                              completeness: IlluminatedSignPlaybookCompletenessV1,
                                              manifest: IlluminatedSignPlaybookManifestV1) throws {
        guard completeness.playbookID == payload.playbookID,
              completeness.payloadSHA256 == payload.payloadSHA256,
              completeness.state == .complete || completeness.state == .couldNotVerify else {
            throw IlluminatedSignPlaybookFailureV1.missingCapture
        }
        if completeness.state == .couldNotVerify, payload.poseTrace == nil {
            guard let key = payload.couldNotVerify?.reasonKey, poseOmissionReasons.contains(key) else {
                throw IlluminatedSignPlaybookFailureV1.invalidPose
            }
        }
        let required = Set(manifest.captureRequirements.filter(\.required).map(\.slotID))
        let actual = Set(payload.captures.map(\.slotID))
        guard completeness.state == .couldNotVerify || required.isSubset(of: actual) else {
            throw IlluminatedSignPlaybookFailureV1.missingCapture
        }
    }
    private var basis: Basis { .init(workspaceID: workspaceID, subject: subject,
        playbookID: playbookID, stage: stage, checkedTime: checkedTime,
        selectedVisibleCondition: selectedVisibleCondition, outcome: outcome,
        couldNotVerify: couldNotVerify, captures: captures, poseTrace: poseTrace,
        visibleConditionClaim: visibleConditionClaim, comparisonIsProof: comparisonIsProof,
        diagnosisClaimed: diagnosisClaimed, electricalCertification: electricalCertification,
        safetyCertification: safetyCertification) }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let subject: EvidenceAssociationTargetV1; let playbookID: IlluminatedSignPlaybookIDV1; let stage: IlluminatedSignPlaybookStageV1; let checkedTime: IlluminatedSignCheckedTimeV1; let selectedVisibleCondition: IlluminatedSignSelectedVisibleConditionV1?; let outcome: IlluminatedSignPlaybookOutcomeV1; let couldNotVerify: IlluminatedSignCouldNotVerifyV1?; let captures: [IlluminatedSignCaptureTraceV1]; let poseTrace: IlluminatedSignPoseTraceV1?; let visibleConditionClaim: IlluminatedSignVisibleConditionClaimV1; let comparisonIsProof: Bool; let diagnosisClaimed: Bool; let electricalCertification: Bool; let safetyCertification: Bool }
}

struct IlluminatedSignPlaybookCompletionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let checkpointDraftID: UUID
    let checkpointDraftRevision: UInt64
    let checkpointSHA256: String
    let registrySHA256: String
    let manifestSHA256: String
    let evidenceSequenceWorkspaceID: WorkspaceID
    let evidenceSequenceFrontier: EvidenceSequenceReferenceV1
    let poseEventFrontier: AssetPoseEventReferenceV1?
    let fact: IlluminatedSignStructuredFactV1
    let completionSHA256: String

    init(checkpoint: FieldDraftCheckpointV1, payload: IlluminatedSignPlaybookDraftPayloadV1,
         completeness: IlluminatedSignPlaybookCompletenessV1,
         evidenceSequence: EvidenceSequenceV1,
         registry: IlluminatedSignPlaybookRegistryV1) throws {
        try checkpoint.validate(); try payload.validate(registry: registry); try evidenceSequence.validate()
        let canonicalPayload = try IlluminatedSignPlaybookCanonicalCodecV1.encode(payload)
        guard checkpoint.workspaceID == payload.workspaceID, checkpoint.purpose == .evidenceCuration,
              checkpoint.codec == registry.draftCodec, checkpoint.payloadData == canonicalPayload,
              checkpoint.state == .active || checkpoint.state == .committing,
              evidenceSequence.workspaceID == payload.workspaceID,
              evidenceSequence.target == payload.subject,
              payload.captures.allSatisfy({ evidenceSequence.orderedItems.contains($0.item) }) else {
            throw IlluminatedSignPlaybookFailureV1.invalidCheckpoint
        }
        let fact = try IlluminatedSignStructuredFactV1(payload: payload, completeness: completeness, registry: registry)
        workspaceID = checkpoint.workspaceID; checkpointDraftID = checkpoint.draftID
        checkpointDraftRevision = checkpoint.draftRevision; checkpointSHA256 = checkpoint.checkpointSHA256
        registrySHA256 = registry.registrySHA256; manifestSHA256 = payload.manifestSHA256
        evidenceSequenceWorkspaceID = evidenceSequence.workspaceID
        evidenceSequenceFrontier = try evidenceSequence.frontier
        poseEventFrontier = payload.poseTrace?.eventReference
        self.fact = fact
        completionSHA256 = try IlluminatedSignPlaybookCanonicalCodecV1.sha256(Basis(
            workspaceID: checkpoint.workspaceID, checkpointDraftID: checkpoint.draftID,
            checkpointDraftRevision: checkpoint.draftRevision, checkpointSHA256: checkpoint.checkpointSHA256,
            registrySHA256: registry.registrySHA256, manifestSHA256: payload.manifestSHA256,
            evidenceSequenceWorkspaceID: evidenceSequence.workspaceID,
            evidenceSequenceFrontier: try evidenceSequence.frontier,
            poseEventFrontier: payload.poseTrace?.eventReference, fact: fact
        ))
    }
    func validate(registry: IlluminatedSignPlaybookRegistryV1) throws {
        let manifest = try registry.manifest(for: fact.playbookID)
        try fact.validate(manifest: manifest, registry: registry); try evidenceSequenceFrontier.validate()
        try poseEventFrontier?.validate()
        guard registrySHA256 == registry.registrySHA256, manifestSHA256 == manifest.manifestSHA256,
              evidenceSequenceWorkspaceID == workspaceID,
              fact.workspaceID == workspaceID,
              fact.poseTrace.map({ $0.event.workspaceID == workspaceID }) ?? true,
              poseEventFrontier == fact.poseTrace?.eventReference,
              completionSHA256 == (try IlluminatedSignPlaybookCanonicalCodecV1.sha256(basis)) else {
            throw IlluminatedSignPlaybookFailureV1.digestMismatch
        }
    }
    private var basis: Basis { .init(workspaceID: workspaceID, checkpointDraftID: checkpointDraftID,
        checkpointDraftRevision: checkpointDraftRevision, checkpointSHA256: checkpointSHA256,
        registrySHA256: registrySHA256, manifestSHA256: manifestSHA256,
        evidenceSequenceWorkspaceID: evidenceSequenceWorkspaceID,
        evidenceSequenceFrontier: evidenceSequenceFrontier,
        poseEventFrontier: poseEventFrontier, fact: fact) }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let checkpointDraftID: UUID; let checkpointDraftRevision: UInt64; let checkpointSHA256: String; let registrySHA256: String; let manifestSHA256: String; let evidenceSequenceWorkspaceID: WorkspaceID; let evidenceSequenceFrontier: EvidenceSequenceReferenceV1; let poseEventFrontier: AssetPoseEventReferenceV1?; let fact: IlluminatedSignStructuredFactV1 }
}

struct IlluminatedSignReportSectionV1: Codable, Equatable, Sendable {
    let sectionID: String
    let sectionVersion: UInt64
    let playbookID: IlluminatedSignPlaybookIDV1
    let completionSHA256: String
    let fact: IlluminatedSignStructuredFactV1
    let visibleConditionsOnly: Bool
    let nonCertificationStatementRequired: Bool
    let disclaimer: String
    let sectionSHA256: String

    init(completion: IlluminatedSignPlaybookCompletionV1,
         manifest: IlluminatedSignPlaybookManifestV1,
         registry: IlluminatedSignPlaybookRegistryV1) throws {
        try completion.validate(registry: registry)
        guard completion.fact.playbookID == manifest.playbookID,
              completion.manifestSHA256 == manifest.manifestSHA256 else {
            throw IlluminatedSignPlaybookFailureV1.registryMismatch
        }
        sectionID = manifest.reportSectionID; sectionVersion = manifest.reportSectionVersion
        playbookID = manifest.playbookID; completionSHA256 = completion.completionSHA256
        fact = completion.fact; visibleConditionsOnly = true; nonCertificationStatementRequired = true
        disclaimer = registry.disclaimer
        sectionSHA256 = try IlluminatedSignPlaybookCanonicalCodecV1.sha256(Basis(
            sectionID: manifest.reportSectionID, sectionVersion: manifest.reportSectionVersion,
            playbookID: manifest.playbookID, completionSHA256: completion.completionSHA256,
            fact: completion.fact, visibleConditionsOnly: true,
            nonCertificationStatementRequired: true, disclaimer: registry.disclaimer
        ))
    }
    func validate(completion: IlluminatedSignPlaybookCompletionV1,
                  registry: IlluminatedSignPlaybookRegistryV1) throws {
        try completion.validate(registry: registry)
        let manifest = try registry.manifest(for: playbookID)
        guard sectionID == manifest.reportSectionID, sectionVersion == manifest.reportSectionVersion,
              completionSHA256 == completion.completionSHA256, fact == completion.fact,
              visibleConditionsOnly, nonCertificationStatementRequired, disclaimer == registry.disclaimer,
              sectionSHA256 == (try IlluminatedSignPlaybookCanonicalCodecV1.sha256(basis)) else {
            throw IlluminatedSignPlaybookFailureV1.digestMismatch
        }
    }
    private var basis: Basis { .init(sectionID: sectionID, sectionVersion: sectionVersion,
        playbookID: playbookID, completionSHA256: completionSHA256, fact: fact,
        visibleConditionsOnly: visibleConditionsOnly,
        nonCertificationStatementRequired: nonCertificationStatementRequired, disclaimer: disclaimer) }
    private struct Basis: Codable { let sectionID: String; let sectionVersion: UInt64; let playbookID: IlluminatedSignPlaybookIDV1; let completionSHA256: String; let fact: IlluminatedSignStructuredFactV1; let visibleConditionsOnly: Bool; let nonCertificationStatementRequired: Bool; let disclaimer: String }
}

enum IlluminatedSignPlaybookCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard !data.isEmpty, data.count <= IlluminatedSignPlaybookLimitsV1.maximumCanonicalBytes else {
            throw IlluminatedSignPlaybookFailureV1.limitExceeded
        }
        return data
    }

    static func decodeDraftPayload(from data: Data,
                                   registry: IlluminatedSignPlaybookRegistryV1) throws
        -> IlluminatedSignPlaybookDraftPayloadV1 {
        guard !data.isEmpty, data.count <= IlluminatedSignPlaybookLimitsV1.maximumCanonicalBytes else {
            throw IlluminatedSignPlaybookFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(IlluminatedSignPlaybookDraftPayloadV1.self, from: data)
        try value.validate(registry: registry)
        guard try encode(value) == data else { throw IlluminatedSignPlaybookFailureV1.digestMismatch }
        return value
    }

    static func decodeRegistry(from data: Data) throws -> IlluminatedSignPlaybookRegistryV1 {
        let value = try canonicalDecoded(IlluminatedSignPlaybookRegistryV1.self, from: data)
        try value.validate(); return value
    }

    static func decodeCompletion(
        from data: Data, checkpoint: FieldDraftCheckpointV1,
        payload: IlluminatedSignPlaybookDraftPayloadV1,
        completeness: IlluminatedSignPlaybookCompletenessV1,
        evidenceSequence: EvidenceSequenceV1,
        registry: IlluminatedSignPlaybookRegistryV1
    ) throws -> IlluminatedSignPlaybookCompletionV1 {
        let value = try canonicalDecoded(IlluminatedSignPlaybookCompletionV1.self, from: data)
        let expected = try IlluminatedSignPlaybookCompletionV1(
            checkpoint: checkpoint, payload: payload, completeness: completeness,
            evidenceSequence: evidenceSequence, registry: registry
        )
        guard value == expected else { throw IlluminatedSignPlaybookFailureV1.digestMismatch }
        return value
    }

    static func decodeReportSection(
        from data: Data, completion: IlluminatedSignPlaybookCompletionV1,
        registry: IlluminatedSignPlaybookRegistryV1
    ) throws -> IlluminatedSignReportSectionV1 {
        let value = try canonicalDecoded(IlluminatedSignReportSectionV1.self, from: data)
        try value.validate(completion: completion, registry: registry)
        return value
    }

    private static func canonicalDecoded<T: Codable & Equatable>(
        _ type: T.Type, from data: Data
    ) throws -> T {
        guard !data.isEmpty, data.count <= IlluminatedSignPlaybookLimitsV1.maximumCanonicalBytes else {
            throw IlluminatedSignPlaybookFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(type, from: data)
        guard try encode(value) == data else { throw IlluminatedSignPlaybookFailureV1.digestMismatch }
        return value
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(value)
    }
}
