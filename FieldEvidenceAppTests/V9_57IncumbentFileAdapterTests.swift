import Foundation
import XCTest

@testable import FieldEvidenceApp

fileprivate struct C50IncumbentCorpus: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let corpusID: String
    let testOnly: Bool
    let synthetic: Bool
    let immutable: Bool
    let containsCustomerData: Bool
    let containsSecrets: Bool
    let evidenceIDs: [String]
    let qualifiedEvidenceIDs: [String]
    let contracts: [String]
    let profile: C50IncumbentProfileFixture
    let golden: C50IncumbentGoldenFixture
    let strictHostileCases: [String]
    let lifecycle: C50IncumbentLifecycleFixture
    let privacy: C50IncumbentPrivacyFixture
    let accessibility: C50IncumbentAccessibilityFixture
    let recovery: [String]
}

fileprivate struct C50IncumbentProfileFixture: Decodable {
    let profileID: String
    let adapterID: String
    let releaseID: String
    let revision: UInt64
    let providerDisplayToken: String
    let uti: String
    let filenameExtension: String
    let encoding: String
    let delimiter: String
    let versionHeader: String
    let versionValue: String
    let orderedHeaders: [String]
    let canonicalFields: [String]
    let direction: String
    let maximumByteCount: UInt64
    let maximumRowCount: Int
    let maximumColumnCount: Int
    let maximumScalarCountPerCell: Int
    let stableKeyMeaning: String
    let targetWorkflow: String
    let privateFieldClass: String
    let noProviderClaim: Bool
}

fileprivate struct C50IncumbentGoldenFixture: Decodable {
    let inputUTF8: Bool
    let inputLineEndings: [String]
    let quotedCells: Bool
    let embeddedNewlines: Bool
    let nfcCanonicalization: Bool
    let rowCount: Int
    let allowedCanonicalFields: [String]
    let omittedCanonicalFields: [String]
    let renderedOutputIsDeterministic: Bool
    let previewIsZeroWrite: Bool
}

fileprivate struct C50IncumbentLifecycleFixture: Decodable {
    let disabledStatus: String
    let zeroOrOneProductionProfile: Bool
    let previewCanonicalWriteCount: Int
    let previewReceiptCount: Int
    let canonicalEffectBeforeReceipt: Bool
    let interruptionDisposition: String
    let retryDisposition: String
    let lostExportCallback: String
    let historicReadUsesExactReleasedBytes: Bool
    let newStartRequiresCurrentSelection: Bool
    let cloneForkCopySelection: Bool
    let eraseRemovesAppOwnedScratch: Bool
    let eraseRecallsExternalFiles: Bool
}

fileprivate struct C50IncumbentPrivacyFixture: Decodable {
    let privateFieldsRequireExplicitApproval: Bool
    let diagnosticsContainCustomerRows: Bool
    let diagnosticsContainSourceBytes: Bool
    let accessibilityContainsPrivateValues: Bool
    let networkEndpoints: Bool
    let credentialsOrBookmarks: Bool
    let providerSDK: Bool
}

fileprivate struct C50IncumbentAccessibilityFixture: Decodable {
    let statusLabel: String
    let previewLabel: String
    let errorFocusRequired: Bool
    let dynamicTypeAndVoiceOver: Bool
    let rtlSafe: Bool
}

/// Test-only transport shape for proving that a structurally valid Codable
/// mutation reference is not an authority token after decoding.
private struct C50ForgedCanonicalMutationReferenceV1: Encodable {
    let workspaceID: WorkspaceID
    let mutationID: MutationIDV1
    let commandBodySHA256: String
    let envelopeSHA256: String
    let receiptSHA256: String
    let expectedPlanSHA256: String
}

private struct C50ForgedExchangeReceiptBasisV1: Encodable {
    let operationID: UUID
    let workspaceID: WorkspaceID
    let releaseSHA256: String
    let scopeSHA256: String
    let inputOrOutputSHA256: String
    let previewSHA256: String?
    let outcome: IncumbentExchangeOutcomeV1
    let canonicalMutation: C50ForgedCanonicalMutationReferenceV1?
    let externalAvailability: IncumbentExternalAvailabilityV1
    let occurredAt: Date
}

private struct C50ForgedExchangeReceiptV1: Encodable {
    let operationID: UUID
    let workspaceID: WorkspaceID
    let releaseSHA256: String
    let scopeSHA256: String
    let inputOrOutputSHA256: String
    let previewSHA256: String?
    let outcome: IncumbentExchangeOutcomeV1
    let canonicalMutation: C50ForgedCanonicalMutationReferenceV1?
    let externalAvailability: IncumbentExternalAvailabilityV1
    let occurredAt: Date
    let receiptSHA256: String
}

/// A fixture implementation of the production port.  It supplies only the
/// sanitized corpus rows and bytes; profile, scope, detection, preview,
/// receipt, and recovery authority remain the production C50 contracts.
struct C50IncumbentFixtureAdapterV1: IncumbentFileAdapterV1 {
    let release: IncumbentFileProfileReleaseV1
    let expectedRows: [IncumbentFileRowV1]
    let renderedBytes: Data

    func detect(_ input: IncumbentFileInputV1) throws -> IncumbentFileDetectionV1 {
        guard String(data: input.bytes, encoding: .utf8) != nil else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        return try IncumbentFileDetectionV1(
            release: release,
            inputSHA256: input.byteSHA256,
            observedHeaders: release.orderedHeaders,
            observedVersion: release.versionValue,
            rowCount: expectedRows.count
        )
    }

    func parse(
        _ input: IncumbentFileInputV1,
        detection: IncumbentFileDetectionV1
    ) throws -> [IncumbentFileRowV1] {
        guard detection.inputSHA256 == input.byteSHA256 else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
        return expectedRows
    }

    func render(
        rows: [IncumbentFileRowV1],
        scope: IncumbentExchangeScopeV1
    ) throws -> Data {
        guard rows == expectedRows,
              scope.releaseID == release.releaseID,
              scope.releaseSHA256 == release.releaseSHA256 else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        return renderedBytes
    }
}

private actor C50IncumbentScratchSpy: ScratchDataLeasePortV1 {
    private var requests: [UUID: ScratchDataLeaseRequestV1] = [:]
    private var finishCounts: [UUID: Int] = [:]
    private var terminals: [UUID: ScratchDataLeaseTerminalV1] = [:]
    private var recoveryCalls = 0

    func acquireScratchLease(_ request: ScratchDataLeaseRequestV1) async throws -> ScratchDataLeaseV1 {
        requests[request.leaseID] = request
        return try ScratchDataLeaseV1(
            request: request,
            relativeDirectory: "c50-\(request.leaseID.uuidString.lowercased())"
        )
    }

    func writeScratchData(_ data: Data, named: String, lease: ScratchDataLeaseV1) async throws -> URL {
        guard requests[lease.request.leaseID] == lease.request, !data.isEmpty,
              ["source.dat", "export.dat"].contains(named) else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        return URL(fileURLWithPath: "/synthetic/\(lease.relativeDirectory)/\(named)")
    }

    func releaseScratchLease(
        _ lease: ScratchDataLeaseV1,
        terminal: ScratchDataLeaseTerminalV1
    ) async throws {
        guard requests.removeValue(forKey: lease.request.leaseID) == lease.request else {
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
        finishCounts[lease.request.leaseID, default: 0] += 1
        terminals[lease.request.leaseID] = terminal
    }

    func recoverScratchLeases() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        recoveryCalls += 1
        let count = requests.count
        requests.removeAll()
        return try ScratchDataLeaseRecoverySummaryV1(
            recoveredExpiredLeaseCount: count,
            removedByteCount: UInt64(count)
        )
    }

    func resetScratchData() async throws { requests.removeAll() }
    func eraseScratchData() async throws { requests.removeAll() }

    func finishCount(for leaseID: UUID) -> Int { finishCounts[leaseID, default: 0] }
    func terminal(for leaseID: UUID) -> ScratchDataLeaseTerminalV1? { terminals[leaseID] }
    func recoveryCallCount() -> Int { recoveryCalls }
}

enum C50IncumbentFileAdapterTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_900_000_000)

    struct PrivacyApprovalFixtureV1 {
        let policy: PrivacyTransformPolicyV1
        let manifest: PrivacyTransformManifestV1
        let review: PrivacyReviewReceiptV1
        let approval: C50PrivacyPreviewApprovalReferenceV1
    }

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c5000000-0000-4000-8000-%012x", slot))!
    }

    static func digest(_ byte: Character = "a") -> String {
        String(repeating: byte, count: 64)
    }

    static func workspace(_ slot: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    static func privacyApproval(
        workspaceID: WorkspaceID = workspace(),
        slot: Int = 70
    ) throws -> C50PrivacyPreviewApprovalReferenceV1 {
        try privacyApprovalFixture(workspaceID: workspaceID, slot: slot).approval
    }

    static func privacyApprovalFixture(
        workspaceID: WorkspaceID = workspace(),
        slot: Int = 70
    ) throws -> PrivacyApprovalFixtureV1 {
        let mutationID = try MutationIDV1(rawValue: id(slot))
        let originalBytes = Data("c50-authoritative-original-\(slot)".utf8)
        let derivativeBytes = Data("c50-approved-derivative-\(slot)".utf8)
        let workspaceText = workspaceID.rawValue.uuidString.lowercased()
        let originalObserved = try ContentIntegrityV1.observe(
            workspaceID: workspaceText,
            contentID: "c50-original-\(slot)",
            data: originalBytes,
            mediaType: "image/jpeg"
        )
        let derivativeObserved = try ContentIntegrityV1.observe(
            workspaceID: workspaceText,
            contentID: "c50-derivative-\(slot)",
            data: derivativeBytes,
            mediaType: "image/jpeg"
        )
        guard let sourceSHA256 = originalObserved.digests.digest(for: .sha256)?.hexadecimalValue,
              let derivativeSHA256 = derivativeObserved.digests.digest(for: .sha256)?.hexadecimalValue else {
            throw PrivacyTransformFailureV1.digestMismatch
        }
        let original = try ContentReferenceV1(
            workspaceID: workspaceText,
            contentID: originalObserved.contentID,
            byteLength: originalObserved.byteLength,
            mediaType: originalObserved.mediaType,
            digests: originalObserved.digests,
            byteRole: .immutableOriginal,
            createdAt: "2030-03-17T17:46:40.000Z"
        )
        let derivative = try ContentReferenceV1(
            workspaceID: workspaceText,
            contentID: derivativeObserved.contentID,
            byteLength: derivativeObserved.byteLength,
            mediaType: derivativeObserved.mediaType,
            digests: derivativeObserved.digests,
            byteRole: .derivative,
            createdAt: "2030-03-17T17:46:40.000Z"
        )
        let reviewerReference = try LocalActorReferenceV1(
            actorReferenceID: id(slot + 1),
            workspaceID: workspaceID,
            displayName: "C50 privacy reviewer"
        )
        let reviewer = try ActorSnapshotV1(
            snapshotID: id(slot + 2),
            workspaceID: workspaceID,
            actor: reviewerReference,
            responsibility: .reviewedBy,
            displayNameAtTime: reviewerReference.displayName,
            capturedAt: fixedDate
        )
        let policy = try PrivacyTransformPolicyV1(
            policyID: id(slot + 3),
            workspaceID: workspaceID,
            purpose: "C50 customer-safe adapter preview",
            audience: .customerReport,
            allowedTransformKinds: [.solidFill],
            allowedReasons: [.confidentialInformation],
            effectiveAt: fixedDate,
            mutationID: mutationID
        )
        let region = try PrivacyRegionV1(
            regionID: id(slot + 4),
            workspaceID: workspaceID,
            sourceContentID: original.contentID,
            sourceRevision: 1,
            sourceSHA256: sourceSHA256,
            coordinateSpace: .normalizedImage,
            orientation: .up,
            sourceBounds: try PrivacyIntegerRectV1(
                x: 100_000,
                y: 100_000,
                width: 200_000,
                height: 200_000
            ),
            transformKind: .solidFill,
            reason: .confidentialInformation,
            author: reviewer,
            order: 0,
            authoredAt: fixedDate,
            mutationID: mutationID
        )
        let manifest = try PrivacyTransformManifestV1(
            manifestID: id(slot + 5),
            workspaceID: workspaceID,
            original: original,
            sourceRevision: 1,
            sourceSHA256: sourceSHA256,
            derivative: derivative,
            derivativeSHA256: derivativeSHA256,
            policy: policy,
            orderedRegions: [region],
            rendererID: "c50-privacy-renderer",
            rendererVersion: "1",
            metadataSanitation: try PrivacyMetadataSanitationEvidenceV1(
                sanitizerID: "c50-metadata-sanitizer",
                sanitizerVersion: "1",
                result: .complete
            ),
            renderedAt: fixedDate,
            mutationID: mutationID
        )
        let review = try PrivacyReviewReceiptV1(
            receiptID: id(slot + 6),
            workspaceID: workspaceID,
            manifest: manifest,
            policy: policy,
            reviewer: reviewer,
            decision: .approved,
            rationale: "C50 customer-safe derivative approved",
            reviewedAt: fixedDate,
            mutationID: mutationID
        )
        let approval = try C50PrivacyPreviewApprovalReferenceV1(
            manifest: manifest,
            review: review,
            policy: policy
        )
        return PrivacyApprovalFixtureV1(
            policy: policy,
            manifest: manifest,
            review: review,
            approval: approval
        )
    }

    static func workResourceProjection(
        privacyApproval: C50PrivacyPreviewApprovalReferenceV1,
        durationMinutes: Int? = nil,
        slot: Int = 170
    ) throws -> C50WorkResourceAdapterProjectionV1 {
        let snapshots: [WorkResourceSnapshotV1]
        if let durationMinutes {
            let workspaceID = privacyApproval.workspaceID
            let actorReference = try LocalActorReferenceV1(
                actorReferenceID: id(slot),
                workspaceID: workspaceID,
                displayName: "C50 projection actor"
            )
            let actor = try ActorSnapshotV1(
                snapshotID: id(slot + 1),
                workspaceID: workspaceID,
                actor: actorReference,
                responsibility: .recordedBy,
                displayNameAtTime: actorReference.displayName,
                capturedAt: fixedDate
            )
            let subject = try WorkResourceSubjectV1(
                workspaceID: workspaceID,
                kind: .workPacket,
                subjectID: id(slot + 2).uuidString,
                subjectRevision: 1,
                subjectSHA256: digest("b")
            )
            let entry = try WorkResourceEntryV1(
                entryID: id(slot + 3),
                workspaceID: workspaceID,
                subject: subject,
                actor: actor,
                duration: try ManualDurationV1(minutes: durationMinutes),
                visibility: .customerSafe,
                recordedAt: fixedDate,
                expectedRevision: 0,
                revision: 1,
                mutationID: try MutationIDV1(rawValue: id(slot + 4))
            )
            snapshots = [try WorkResourceSnapshotV1(entry: entry)]
        } else {
            snapshots = []
        }
        return try C50WorkResourceAdapterProjectionV1(
            customerSafeTotals: WorkResourceTotalsProjectionV1(
                snapshots: snapshots,
                visibility: .customerSafe
            ),
            privacyApproval: privacyApproval
        )
    }

    static func adapterApproval(
        privacyApproval: C50PrivacyPreviewApprovalReferenceV1,
        allowedCanonicalFields: [IncumbentCanonicalFieldV1],
        workspaceRevision: UInt64 = 1,
        durationMinutes: Int? = nil,
        slot: Int = 170
    ) throws -> IncumbentPrivacyApprovalReferenceV1 {
        try IncumbentPrivacyApprovalReferenceV1(
            projection: .workResource(try workResourceProjection(
                privacyApproval: privacyApproval,
                durationMinutes: durationMinutes,
                slot: slot
            )),
            workspaceRevision: workspaceRevision,
            allowedCanonicalFields: allowedCanonicalFields
        )
    }

    static func profile(
        profileSlot: Int = 1,
        releaseSlot: Int = 2,
        revision: UInt64 = 1,
        predecessor: IncumbentFileProfileReleaseV1? = nil,
        direction: IncumbentFileDirectionV1 = .bidirectionalFiles
    ) throws -> IncumbentFileProfileReleaseV1 {
        let mappings = try [
            IncumbentFieldMappingV1(
                externalHeader: "Version",
                canonicalField: .fileFormatVersion,
                required: true
            ),
            IncumbentFieldMappingV1(
                externalHeader: "Asset ID",
                canonicalField: .workMaterialLineCount,
                required: true
            ),
            IncumbentFieldMappingV1(
                externalHeader: "Note",
                canonicalField: .workMaterialTotals,
                required: false
            )
        ]
        let manifest = try IncumbentMappingManifestV1(mappings: mappings)
        let budget = try IncumbentFileBudgetV1(
            maximumByteCount: 4_096,
            maximumRowCount: 10,
            maximumColumnCount: 3,
            maximumScalarCountPerCell: 128
        )
        return try IncumbentFileProfileReleaseV1(
            profileID: id(profileSlot),
            adapterID: id(10),
            releaseID: id(releaseSlot),
            revision: revision,
            providerDisplayToken: "C50-Fixture-Profile",
            uniformTypeIdentifiers: ["public.comma-separated-values-text"],
            filenameExtensions: ["csv"],
            encoding: .utf8,
            delimiter: .comma,
            orderedHeaders: mappings.map(\.externalHeader),
            versionHeader: "Version",
            versionValue: "c50-v1",
            direction: direction,
            budget: budget,
            mappingManifest: manifest,
            externalKeyPolicy: .exactOpaqueStableKey,
            timeZonePolicy: .noTemporalFields,
            predecessorReleaseID: predecessor?.releaseID,
            predecessorReleaseSHA256: predecessor?.releaseSHA256
        )
    }

    static func successor(
        of predecessor: IncumbentFileProfileReleaseV1,
        releaseSlot: Int = 3
    ) throws -> IncumbentFileProfileReleaseV1 {
        try profile(
            profileSlot: 1,
            releaseSlot: releaseSlot,
            revision: predecessor.revision + 1,
            predecessor: predecessor,
            direction: predecessor.direction
        )
    }

    static func enabledSelection(
        for release: IncumbentFileProfileReleaseV1,
        receiptSlot: Int = 4,
        evidenceExpiresAt: Date? = nil
    ) throws -> IncumbentSelectionReceiptV1 {
        try IncumbentSelectionReceiptV1(
            receiptID: id(receiptSlot),
            disposition: .enabledNamedProfile,
            selectedRelease: release,
            sanitizedFixtureProvenance: "sanitized.c50.fixture",
            targetWorkflow: "C50-Golden-Workflow",
            fileVersion: release.versionValue,
            direction: release.direction,
            stableKeyMeaning: "the local stable row field is an exact opaque key",
            termsDisposition: .approvedForLocalFileExchange,
            evidenceDate: fixedDate,
            evidenceExpiresAt: evidenceExpiresAt ?? fixedDate.addingTimeInterval(86_400)
        )
    }

    static func disabledSelection(receiptSlot: Int = 5) throws -> IncumbentSelectionReceiptV1 {
        try IncumbentSelectionReceiptV1(
            receiptID: id(receiptSlot),
            disposition: .disabledNoSelectedProfile,
            selectedRelease: nil,
            sanitizedFixtureProvenance: "no.selected.profile",
            targetWorkflow: "C50-Disabled-Workflow",
            fileVersion: nil,
            direction: nil,
            stableKeyMeaning: "no selected profile is available",
            termsDisposition: .unavailable,
            evidenceDate: fixedDate,
            evidenceExpiresAt: nil
        )
    }

    static func scope(
        for release: IncumbentFileProfileReleaseV1,
        operationSlot: Int = 6,
        ordinaryOnly: Bool = false
    ) throws -> IncumbentExchangeScopeV1 {
        try scope(
            for: release,
            operationSlot: operationSlot,
            ordinaryOnly: ordinaryOnly,
            privacyApproval: privacyApproval()
        )
    }

    static func scope(
        for release: IncumbentFileProfileReleaseV1,
        operationSlot: Int = 6,
        ordinaryOnly: Bool = false,
        privacyApproval: C50PrivacyPreviewApprovalReferenceV1
    ) throws -> IncumbentExchangeScopeV1 {
        let fields = adapterFields(for: release, ordinaryOnly: ordinaryOnly)
        let adapterApproval = try adapterApproval(
            privacyApproval: privacyApproval,
            allowedCanonicalFields: fields
        )
        return try scope(
            for: release,
            operationSlot: operationSlot,
            ordinaryOnly: ordinaryOnly,
            privacyApproval: adapterApproval
        )
    }

    static func scope(
        for release: IncumbentFileProfileReleaseV1,
        operationSlot: Int = 6,
        ordinaryOnly: Bool = false,
        privacyApproval: IncumbentPrivacyApprovalReferenceV1
    ) throws -> IncumbentExchangeScopeV1 {
        let fields = adapterFields(for: release, ordinaryOnly: ordinaryOnly)
        return try IncumbentExchangeScopeV1(
            operationID: id(operationSlot),
            workspaceID: workspace(),
            workspaceRevision: 1,
            release: release,
            direction: release.direction,
            allowedCanonicalFields: fields,
            privacyApproval: privacyApproval
        )
    }

    static func projectionAndScope(
        for release: IncumbentFileProfileReleaseV1,
        operationSlot: Int = 6,
        ordinaryOnly: Bool = false,
        durationMinutes: Int? = nil,
        projectionSlot: Int = 170
    ) throws -> (projection: IncumbentAdapterProjectionV1, scope: IncumbentExchangeScopeV1) {
        let privacyApproval = try privacyApproval()
        let fields = adapterFields(for: release, ordinaryOnly: ordinaryOnly)
        let workProjection = try workResourceProjection(
            privacyApproval: privacyApproval,
            durationMinutes: durationMinutes,
            slot: projectionSlot
        )
        let adapterApproval = try IncumbentPrivacyApprovalReferenceV1(
            projection: .workResource(workProjection),
            workspaceRevision: 1,
            allowedCanonicalFields: fields
        )
        let scope = try scope(
            for: release,
            operationSlot: operationSlot,
            ordinaryOnly: ordinaryOnly,
            privacyApproval: adapterApproval
        )
        return (
            .workResource(workProjection, privacyApproval: adapterApproval),
            scope
        )
    }

    static func adapterFields(
        for release: IncumbentFileProfileReleaseV1,
        ordinaryOnly: Bool = false
    ) -> [IncumbentCanonicalFieldV1] {
        ordinaryOnly
            ? [.fileFormatVersion, .workMaterialLineCount]
            : release.mappingManifest.mappings.map(\.canonicalField)
                .sorted(by: { $0.rawValue < $1.rawValue })
    }

    static func input(
        bytes: Data? = nil,
        filenameExtension: String = "csv",
        uniformTypeIdentifier: String = "public.comma-separated-values-text"
    ) throws -> IncumbentFileInputV1 {
        try IncumbentFileInputV1(
            bytes: bytes ?? Data(
                "Version,Asset ID,Note\r\nc50-v1,1,\"Café\r\n\"\"quoted\"\"\"\r\n".utf8
            ),
            filenameExtension: filenameExtension,
            uniformTypeIdentifier: uniformTypeIdentifier
        )
    }

    static func rows(
        for release: IncumbentFileProfileReleaseV1
    ) throws -> [IncumbentFileRowV1] {
        let values: [IncumbentCanonicalFieldV1: String] = [
            .fileFormatVersion: "c50-v1",
            .workMaterialLineCount: "1",
            .workMaterialTotals: "Cafe\u{301}\r\n\"quoted\""
        ]
        let cells = try release.mappingManifest.mappings.map { mapping in
            try IncumbentFileCellV1(
                field: mapping.canonicalField,
                value: values[mapping.canonicalField] ?? "",
                maximumScalars: release.budget.maximumScalarCountPerCell
            )
        }
        return [try IncumbentFileRowV1(ordinal: 1, cells: cells, release: release)]
    }

    static func adapter(
        for release: IncumbentFileProfileReleaseV1
    ) throws -> IncumbentDelimitedTextAdapterV1 {
        try IncumbentDelimitedTextAdapterV1(release: release)
    }

    static func coordinator(
        release: IncumbentFileProfileReleaseV1,
        selection: IncumbentSelectionReceiptV1
    ) throws -> IncumbentFileExchangeCoordinatorV1 {
        let availability = try availability(selected: true, release: release)
        let registry = try ClosedIncumbentAdapterRegistryV1(
            currentProductionReleases: [release],
            selection: selection,
            selectionHistory: [selection],
            availabilityReceipt: availability
        )
        return try IncumbentFileExchangeCoordinatorV1(
            registry: registry,
            adapters: [try adapter(for: release)]
        )
    }

    static func availability(
        selected: Bool,
        release: IncumbentFileProfileReleaseV1? = nil
    ) throws -> TypedAvailabilityAndFallbackReceiptV1 {
        if selected { guard release != nil else { throw IncumbentFileContractFailureV1.invalidValue } }
        let reason: FeatureAvailabilityReasonV1 = selected ? .available : .notEntitled
        let visibleFallback: ManualFallbackActionV1
        if selected {
            visibleFallback = .noFallback
        } else {
            visibleFallback = try CapabilityPermissionMatrixV1.current()
                .descriptor(for: .filesAndShare).manualFallback
        }
        return try TypedAvailabilityAndFallbackReceiptV1(
            candidateHead: "1c8b3d99826a207d3b18b3e0429231c31804f317",
            candidateTree: "3107903158238e5e5eaed78322c3564b06c648e2",
            providerID: "C50_FILE_ADAPTER",
            providerSliceDigest: selected ? release!.releaseSHA256 : digest("f"),
            consumerID: "C50_FILE_EXCHANGE",
            capabilityID: .filesAndShare,
            availabilityReason: reason,
            mandatoryCoreComplete: true,
            visibleFallback: visibleFallback,
            persistenceDisposition: .noCanonicalEffectUntilAcceptance,
            dataDisposition: .priorHistoryPreserved,
            reentryTrigger: .capabilityStateChanged,
            localizedVisibleStateKey: "c50.adapter.state",
            localizedVisibleCopyKey: "c50.adapter.copy",
            localizedNextActionKey: "c50.adapter.nextAction",
            fallbackTestArtifactIDs: ["V23-P03-C50-A01-FALLBACK"],
            evidenceArtifactIDs: ["V23-P03-C50-A01-RECEIPT"],
            zeroUnsupportedPublicClaim: true
        )
    }

    static func recoveryPlan(
        input: IncumbentFileInputV1,
        scope: IncumbentExchangeScopeV1,
        release: IncumbentFileProfileReleaseV1,
        preview: IncumbentMappingPreviewV1,
        mutationSlot: Int = 21,
        expectedMutationID: MutationIDV1? = nil,
        expectedCommandBodySHA256: String? = nil
    ) throws -> IncumbentExchangeRecoveryPlanV1 {
        try IncumbentExchangeRecoveryPlanV1(
            operationID: scope.operationID,
            workspaceID: scope.workspaceID,
            sourceSHA256: input.byteSHA256,
            scope: scope,
            preview: preview,
            mappingManifestSHA256: release.mappingManifest.manifestSHA256,
            expectedMutationID: try (
                expectedMutationID ?? MutationIDV1(rawValue: id(mutationSlot))
            ),
            expectedCommandBodySHA256: expectedCommandBodySHA256 ?? digest("b"),
            cleanupIdentitySHA256: digest("d")
        )
    }

    fileprivate static func corpus() throws -> C50IncumbentCorpus {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Fixtures/V22/IncumbentExchange/V22P03C50IncumbentFileAdapterCorpusV1.json"
            )
        return try JSONDecoder().decode(C50IncumbentCorpus.self, from: Data(contentsOf: url))
    }
}

final class V9_57IncumbentFileAdapterTests: XCTestCase {
    func testV23P03C50G01GoldenProfileRegistryAndDeterministicPreviewRender() throws {
        let corpus = try C50IncumbentFileAdapterTestSupport.corpus()
        XCTAssertEqual(corpus.schema, "V22P03C50IncumbentFileAdapterCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C50")
        XCTAssertTrue(corpus.testOnly)
        XCTAssertTrue(corpus.synthetic)
        XCTAssertTrue(corpus.immutable)
        XCTAssertFalse(corpus.containsCustomerData)
        XCTAssertFalse(corpus.containsSecrets)
        XCTAssertEqual(corpus.evidenceIDs, ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(
            corpus.qualifiedEvidenceIDs,
            corpus.evidenceIDs.map { "V23-P03-C50-\($0)" }
        )

        let release = try C50IncumbentFileAdapterTestSupport.profile()
        XCTAssertEqual(release.profileID.uuidString.lowercased(), corpus.profile.profileID.lowercased())
        XCTAssertEqual(release.adapterID.uuidString.lowercased(), corpus.profile.adapterID.lowercased())
        XCTAssertEqual(release.releaseID.uuidString.lowercased(), corpus.profile.releaseID.lowercased())
        XCTAssertEqual(release.revision, corpus.profile.revision)
        XCTAssertEqual(release.providerDisplayToken, corpus.profile.providerDisplayToken)
        XCTAssertEqual(release.versionValue, corpus.profile.versionValue)
        XCTAssertEqual(release.orderedHeaders, corpus.profile.orderedHeaders)
        XCTAssertEqual(
            release.mappingManifest.mappings.map { $0.canonicalField.rawValue },
            corpus.profile.canonicalFields
        )
        XCTAssertEqual(
            IncumbentCanonicalFieldV1.allCases.map(\.rawValue).sorted(),
            [
                "file.formatVersion",
                "portableReview.latestResponsePublicID",
                "portableReview.publicID",
                "portableReview.state",
                "workResource.durationMinutes",
                "workResource.materialLineCount",
                "workResource.materialTotals"
            ]
        )
        XCTAssertEqual(release.direction.rawValue, corpus.profile.direction)
        XCTAssertEqual(release.budget.maximumByteCount, corpus.profile.maximumByteCount)
        XCTAssertEqual(release.budget.maximumRowCount, corpus.profile.maximumRowCount)
        XCTAssertEqual(release.budget.maximumColumnCount, corpus.profile.maximumColumnCount)
        XCTAssertEqual(
            release.budget.maximumScalarCountPerCell,
            corpus.profile.maximumScalarCountPerCell
        )
        try release.validate()

        let privacyFixture = try C50IncumbentFileAdapterTestSupport.privacyApprovalFixture()
        let adapterFields = C50IncumbentFileAdapterTestSupport.adapterFields(for: release)
        let encodedApproval = try JSONEncoder().encode(privacyFixture.approval)
        let structurallyValidUnboundApproval = try JSONDecoder().decode(
            C50PrivacyPreviewApprovalReferenceV1.self,
            from: encodedApproval
        )
        XCTAssertEqual(structurallyValidUnboundApproval, privacyFixture.approval)
        XCTAssertThrowsError(
            try structurallyValidUnboundApproval.requireAuthoritativelyBound()
        ) { error in
            XCTAssertEqual(error as? PrivacyTransformFailureV1, .reviewRequired)
        }
        let workResourceProjection = try C50IncumbentFileAdapterTestSupport.workResourceProjection(
            privacyApproval: privacyFixture.approval
        )
        let expectedProjection = IncumbentAdapterProjectionPayloadV1.workResource(
            workResourceProjection
        )
        let boundAdapterApproval = try IncumbentPrivacyApprovalReferenceV1(
            projection: expectedProjection,
            workspaceRevision: 1,
            allowedCanonicalFields: adapterFields
        )
        XCTAssertEqual(boundAdapterApproval.canonicalProjectionValues, try expectedProjection.canonicalProjectionValues())
        XCTAssertEqual(boundAdapterApproval.canonicalProjectionSHA256, try expectedProjection.canonicalProjectionSHA256())
        XCTAssertEqual(
            boundAdapterApproval.workspaceFrontier,
            try IncumbentAdapterWorkspaceFrontierV1(
                workspaceID: privacyFixture.approval.workspaceID,
                workspaceRevision: 1
            )
        )
        let encodedAdapterApproval = try JSONEncoder().encode(boundAdapterApproval)
        let structurallyValidUnboundAdapterApproval = try JSONDecoder().decode(
            IncumbentPrivacyApprovalReferenceV1.self,
            from: encodedAdapterApproval
        )
        XCTAssertEqual(structurallyValidUnboundAdapterApproval, boundAdapterApproval)
        XCTAssertEqual(
            Set([structurallyValidUnboundAdapterApproval]),
            Set([boundAdapterApproval])
        )
        XCTAssertThrowsError(
            try structurallyValidUnboundAdapterApproval.requireAuthoritativelyBound()
        ) { error in
            XCTAssertEqual(
                error as? IncumbentFileContractFailureV1,
                .privacyApprovalRequired
            )
        }
        XCTAssertThrowsError(try C50IncumbentFileAdapterTestSupport.scope(
            for: release,
            privacyApproval: structurallyValidUnboundAdapterApproval
        )) { error in
            XCTAssertEqual(
                error as? IncumbentFileContractFailureV1,
                .privacyApprovalRequired
            )
        }
        XCTAssertThrowsError(try C50WorkResourceAdapterProjectionV1(
            customerSafeTotals: WorkResourceTotalsProjectionV1(snapshots: []),
            privacyApproval: structurallyValidUnboundApproval
        )) { error in
            XCTAssertEqual(error as? PrivacyTransformFailureV1, .reviewRequired)
        }
        let privacyApproval = try structurallyValidUnboundApproval.revalidated(
            manifest: privacyFixture.manifest,
            review: privacyFixture.review,
            policy: privacyFixture.policy
        )
        XCTAssertNoThrow(try privacyApproval.requireAuthoritativelyBound())
        let adapterApproval = try structurallyValidUnboundAdapterApproval.revalidated(
            manifest: privacyFixture.manifest,
            review: privacyFixture.review,
            policy: privacyFixture.policy,
            expectedProjection: expectedProjection,
            workspaceID: privacyFixture.approval.workspaceID,
            workspaceRevision: 1,
            allowedCanonicalFields: adapterFields
        )
        XCTAssertNoThrow(try adapterApproval.requireAuthoritativelyBound())
        let portableSource = try ReviewRequestStateProjectionV1(
            requestPublicID: try ReviewRequestPublicIDV1("c50-wrong-kind"),
            state: .exportedAwaitingResponse,
            lifecycleState: .exportedAccepting
        )
        let portableProjection = try C50PortableReviewAdapterProjectionV1(
            portableSource,
            privacyApproval: privacyApproval
        )
        let wrongWorkspaceFrontier: UInt64 = 2
        XCTAssertThrowsError(try structurallyValidUnboundAdapterApproval.revalidated(
            manifest: privacyFixture.manifest,
            review: privacyFixture.review,
            policy: privacyFixture.policy,
            expectedProjection: .portableReview(portableProjection),
            workspaceID: privacyFixture.approval.workspaceID,
            workspaceRevision: 1,
            allowedCanonicalFields: adapterFields
        ))
        let alteredWorkResourceProjection = try C50IncumbentFileAdapterTestSupport.workResourceProjection(
            privacyApproval: privacyApproval,
            durationMinutes: 15,
            slot: 190
        )
        XCTAssertThrowsError(try structurallyValidUnboundAdapterApproval.revalidated(
            manifest: privacyFixture.manifest,
            review: privacyFixture.review,
            policy: privacyFixture.policy,
            expectedProjection: .workResource(alteredWorkResourceProjection),
            workspaceID: privacyFixture.approval.workspaceID,
            workspaceRevision: 1,
            allowedCanonicalFields: adapterFields
        ))
        XCTAssertThrowsError(try structurallyValidUnboundAdapterApproval.revalidated(
            manifest: privacyFixture.manifest,
            review: privacyFixture.review,
            policy: privacyFixture.policy,
            expectedProjection: expectedProjection,
            workspaceID: privacyFixture.approval.workspaceID,
            workspaceRevision: wrongWorkspaceFrontier,
            allowedCanonicalFields: adapterFields
        ))
        let reducedWorkFields: [IncumbentCanonicalFieldV1] = [
            .fileFormatVersion,
            .workMaterialLineCount,
        ]
        XCTAssertThrowsError(try structurallyValidUnboundAdapterApproval.revalidated(
            manifest: privacyFixture.manifest,
            review: privacyFixture.review,
            policy: privacyFixture.policy,
            expectedProjection: expectedProjection,
            workspaceID: privacyFixture.approval.workspaceID,
            workspaceRevision: 1,
            allowedCanonicalFields: reducedWorkFields
        ))
        XCTAssertThrowsError(try structurallyValidUnboundAdapterApproval.revalidated(
            manifest: privacyFixture.manifest,
            review: privacyFixture.review,
            policy: privacyFixture.policy,
            expectedProjection: expectedProjection,
            workspaceID: privacyFixture.approval.workspaceID,
            workspaceRevision: 1,
            allowedCanonicalFields: Array(adapterFields.reversed())
        ))
        XCTAssertThrowsError(try IncumbentPrivacyApprovalReferenceV1(
            projection: .portableReview(portableProjection),
            workspaceRevision: 1,
            allowedCanonicalFields: adapterFields
        ))
        var tamperedAdapterJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedAdapterApproval) as? [String: Any]
        )
        tamperedAdapterJSON["projectionKind"] = IncumbentAdapterProjectionKindV1.portableReview.rawValue
        XCTAssertThrowsError(try JSONDecoder().decode(
            IncumbentPrivacyApprovalReferenceV1.self,
            from: JSONSerialization.data(withJSONObject: tamperedAdapterJSON)
        ))
        var tamperedValuesJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedAdapterApproval) as? [String: Any]
        )
        var tamperedValues = try XCTUnwrap(
            tamperedValuesJSON["canonicalProjectionValues"] as? [[String: Any]]
        )
        tamperedValues[0]["canonicalValue"] = "altered"
        tamperedValuesJSON["canonicalProjectionValues"] = tamperedValues
        XCTAssertThrowsError(try JSONDecoder().decode(
            IncumbentPrivacyApprovalReferenceV1.self,
            from: JSONSerialization.data(withJSONObject: tamperedValuesJSON)
        ))
        let projectionScope = try C50IncumbentFileAdapterTestSupport.scope(
            for: release,
            privacyApproval: adapterApproval
        )
        XCTAssertThrowsError(try IncumbentExchangeScopeV1(
            operationID: C50IncumbentFileAdapterTestSupport.id(220),
            workspaceID: privacyFixture.approval.workspaceID,
            workspaceRevision: 2,
            release: release,
            direction: release.direction,
            allowedCanonicalFields: adapterFields,
            privacyApproval: adapterApproval
        )) { error in
            XCTAssertEqual(
                error as? IncumbentFileContractFailureV1,
                .privacyApprovalRequired
            )
        }
        let encodedProjectionScope = try IncumbentFileCanonicalCodecV1.encode(projectionScope)
        XCTAssertThrowsError(try IncumbentFileCanonicalCodecV1.decodeScope(
            from: encodedProjectionScope,
            release: release
        ))
        let revalidatedProjectionScope = try IncumbentFileCanonicalCodecV1.decodeScope(
            from: encodedProjectionScope,
            release: release,
            privacyManifest: privacyFixture.manifest,
            privacyReview: privacyFixture.review,
            privacyPolicy: privacyFixture.policy,
            expectedProjection: expectedProjection,
            expectedWorkspaceID: privacyFixture.approval.workspaceID,
            expectedWorkspaceRevision: 1,
            expectedAllowedCanonicalFields: adapterFields
        )
        XCTAssertEqual(revalidatedProjectionScope, projectionScope)
        let adapterProjection = IncumbentAdapterProjectionV1.workResource(
            workResourceProjection,
            privacyApproval: adapterApproval
        )
        XCTAssertThrowsError(try IncumbentFileRowV1(
            ordinal: 1,
            projection: .workResource(
                alteredWorkResourceProjection,
                privacyApproval: adapterApproval
            ),
            release: release,
            scope: projectionScope
        )) { error in
            XCTAssertEqual(
                error as? IncumbentFileContractFailureV1,
                .privacyApprovalRequired
            )
        }
        let projectedRow = try IncumbentFileRowV1(
            ordinal: 1,
            projection: adapterProjection,
            release: release,
            scope: projectionScope
        )
        XCTAssertEqual(
            projectedRow.cells.map(\.field),
            release.mappingManifest.mappings.map(\.canonicalField)
        )
        XCTAssertEqual(projectedRow.cells[0].field, .fileFormatVersion)

        let divergentApproval = try C50IncumbentFileAdapterTestSupport.privacyApproval(slot: 80)
        let divergentAdapterApproval = try C50IncumbentFileAdapterTestSupport.adapterApproval(
            privacyApproval: divergentApproval,
            allowedCanonicalFields: adapterFields,
            slot: 210
        )
        XCTAssertThrowsError(try IncumbentFileRowV1(
            ordinal: 1,
            projection: .workResource(
                workResourceProjection,
                privacyApproval: divergentAdapterApproval
            ),
            release: release,
            scope: try C50IncumbentFileAdapterTestSupport.scope(
                for: release,
                privacyApproval: divergentAdapterApproval
            )
        )) { error in
            XCTAssertEqual(
                error as? IncumbentFileContractFailureV1,
                .privacyApprovalRequired
            )
        }
        XCTAssertThrowsError(try IncumbentFileRowV1(
            ordinal: 1,
            projection: adapterProjection,
            release: release,
            scope: try C50IncumbentFileAdapterTestSupport.scope(
                for: release,
                privacyApproval: divergentAdapterApproval
            )
        )) { error in
            XCTAssertEqual(
                error as? IncumbentFileContractFailureV1,
                .privacyApprovalRequired
            )
        }

        let selection = try C50IncumbentFileAdapterTestSupport.enabledSelection(for: release)
        let registry = try ClosedIncumbentAdapterRegistryV1(
            currentProductionReleases: [release],
            selection: selection,
            selectionHistory: [selection],
            availabilityReceipt: try C50IncumbentFileAdapterTestSupport.availability(
                selected: true,
                release: release
            )
        )
        XCTAssertEqual(registry.currentProductionReleases.count, 1)
        XCTAssertTrue(corpus.lifecycle.zeroOrOneProductionProfile)

        let coordinator = try IncumbentFileExchangeCoordinatorV1(
            registry: registry,
            adapters: [try C50IncumbentFileAdapterTestSupport.adapter(for: release)]
        )
        let input = try C50IncumbentFileAdapterTestSupport.input()
        let scope = try C50IncumbentFileAdapterTestSupport.scope(for: release)
        let reorderedInput = try C50IncumbentFileAdapterTestSupport.input(
            bytes: Data("Asset ID,Version,Note\r\n1,c50-v1,Café\r\n".utf8)
        )
        XCTAssertThrowsError(try coordinator.preview(
            input: reorderedInput,
            scope: scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .headerMismatch)
        }
        let duplicateHeaderInput = try C50IncumbentFileAdapterTestSupport.input(
            bytes: Data("Version,Version,Note\r\nc50-v1,c50-v1,Café\r\n".utf8)
        )
        XCTAssertThrowsError(try coordinator.preview(
            input: duplicateHeaderInput,
            scope: scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .headerMismatch)
        }
        let unknownVersionInput = try C50IncumbentFileAdapterTestSupport.input(
            bytes: Data("Version,Asset ID,Note\r\nc50-v2,1,Café\r\n".utf8)
        )
        XCTAssertThrowsError(try coordinator.preview(
            input: unknownVersionInput,
            scope: scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .unsupportedVersion)
        }
        let formulaInput = try C50IncumbentFileAdapterTestSupport.input(
            bytes: Data("Version,Asset ID,Note\r\nc50-v1,1,=HYPERLINK\r\n".utf8)
        )
        XCTAssertThrowsError(try coordinator.preview(
            input: formulaInput,
            scope: scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .invalidValue)
        }
        let nonNFCInput = try C50IncumbentFileAdapterTestSupport.input(
            bytes: Data("Version,Asset ID,Note\r\nc50-v1,1,Cafe\u{301}\r\n".utf8)
        )
        XCTAssertThrowsError(try coordinator.preview(
            input: nonNFCInput,
            scope: scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .unsupportedVersion)
        }
        let controlInput = try C50IncumbentFileAdapterTestSupport.input(
            bytes: Data("Version,Asset ID,Note\r\nc50-v1,1,bad\u{1}\r\n".utf8)
        )
        XCTAssertThrowsError(try coordinator.preview(
            input: controlInput,
            scope: scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .unsupportedVersion)
        }
        let lfInput = try C50IncumbentFileAdapterTestSupport.input(
            bytes: Data("Version,Asset ID,Note\nc50-v1,1,Café\n".utf8)
        )
        let lfPreview = try coordinator.preview(
            input: lfInput,
            scope: scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        XCTAssertEqual(lfPreview.rows.first?.cells.last?.value, "Café")
        let firstPreview = try coordinator.preview(
            input: input,
            scope: scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        let secondPreview = try coordinator.preview(
            input: input,
            scope: scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        XCTAssertEqual(firstPreview.rows, secondPreview.rows)
        XCTAssertEqual(firstPreview.preview, secondPreview.preview)
        XCTAssertEqual(firstPreview.rows.count, corpus.golden.rowCount)
        XCTAssertEqual(
            firstPreview.preview.includedFields.map(\.rawValue),
            corpus.golden.allowedCanonicalFields
        )
        XCTAssertEqual(
            firstPreview.preview.omittedFields.map(\.rawValue),
            corpus.golden.omittedCanonicalFields
        )
        XCTAssertEqual(firstPreview.preview.inputSHA256, input.byteSHA256)
        XCTAssertEqual(firstPreview.rows[0].cells[2].value, "Café\r\n\"quoted\"")
        XCTAssertEqual(corpus.lifecycle.previewCanonicalWriteCount, 0)
        XCTAssertEqual(corpus.lifecycle.previewReceiptCount, 0)
        XCTAssertTrue(corpus.golden.previewIsZeroWrite)

        let boundExport = try C50IncumbentFileAdapterTestSupport.projectionAndScope(
            for: release
        )
        XCTAssertEqual(boundExport.scope, scope)
        let firstRender = try coordinator.render(
            projections: [boundExport.projection],
            scope: boundExport.scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        let secondRender = try coordinator.render(
            projections: [boundExport.projection],
            scope: boundExport.scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        XCTAssertEqual(firstRender.data, secondRender.data)
        XCTAssertEqual(firstRender.manifest, secondRender.manifest)
        XCTAssertEqual(firstRender.manifest.outputByteCount, UInt64(firstRender.data.count))
        XCTAssertTrue(corpus.golden.renderedOutputIsDeterministic)

        let alteredValuesProjection = IncumbentAdapterProjectionV1.workResource(
            try C50IncumbentFileAdapterTestSupport.workResourceProjection(
                privacyApproval: boundExport.projection.privacyApproval.privacyPreviewApproval,
                durationMinutes: 15
            ),
            privacyApproval: boundExport.projection.privacyApproval
        )
        var rowValueBypassRejected = false
        XCTAssertThrowsError(try coordinator.render(projections: [alteredValuesProjection],
            scope: boundExport.scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )) { error in
            rowValueBypassRejected = true
            XCTAssertEqual(
                error as? IncumbentFileContractFailureV1,
                .privacyApprovalRequired
            )
        }
        XCTAssertTrue(rowValueBypassRejected, "ROW_VALUE_BYPASS_REJECTED")
        XCTAssertThrowsError(try coordinator.render(
            projections: [boundExport.projection, boundExport.projection],
            scope: boundExport.scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .budgetExceeded)
        }

        let disabled = try ClosedIncumbentAdapterRegistryV1(
            currentProductionReleases: [],
            selection: try C50IncumbentFileAdapterTestSupport.disabledSelection(),
            selectionHistory: [try C50IncumbentFileAdapterTestSupport.disabledSelection()],
            availabilityReceipt: try C50IncumbentFileAdapterTestSupport.availability(selected: false)
        )
        XCTAssertEqual(disabled.currentProductionReleases.count, 0)
        let disabledCoordinator = try IncumbentFileExchangeCoordinatorV1(
            registry: disabled,
            adapters: []
        )
        XCTAssertThrowsError(
            try disabledCoordinator.preview(
                input: input,
                scope: scope,
                at: C50IncumbentFileAdapterTestSupport.fixedDate
            )
        ) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .noSelectedProfile)
        }
        XCTAssertEqual(corpus.lifecycle.disabledStatus, "DISABLED_NO_SELECTED_PROFILE")
    }

    func testV23P03C50A01HistoricReadExportAndNewStartRemainSeparated() throws {
        let corpus = try C50IncumbentFileAdapterTestSupport.corpus()
        let source = try C50IncumbentFileAdapterTestSupport.profile()
        let historic = try C50IncumbentFileAdapterTestSupport.successor(of: source)
        try historic.validateSuccessor(of: source)

        let disabledRegistry = try ClosedIncumbentAdapterRegistryV1(
            currentProductionReleases: [],
            historicReleases: [source, historic],
            selection: try C50IncumbentFileAdapterTestSupport.disabledSelection(),
            selectionHistory: [try C50IncumbentFileAdapterTestSupport.disabledSelection()],
            availabilityReceipt: try C50IncumbentFileAdapterTestSupport.availability(selected: false)
        )
        let readRelease = try disabledRegistry.exactHistoricRelease(
            id: historic.releaseID,
            sha256: historic.releaseSHA256
        )
        XCTAssertEqual(readRelease, historic)
        XCTAssertEqual(readRelease.predecessorReleaseSHA256, source.releaseSHA256)
        XCTAssertTrue(corpus.lifecycle.historicReadUsesExactReleasedBytes)
        XCTAssertTrue(corpus.lifecycle.newStartRequiresCurrentSelection)

        let historicExport = try C50IncumbentFileAdapterTestSupport.projectionAndScope(
            for: historic
        )
        let historicScope = historicExport.scope
        let historicRow = try IncumbentFileRowV1(
            ordinal: 1,
            projection: historicExport.projection,
            release: historic,
            scope: historicScope
        )
        let historicBytes = try IncumbentDelimitedTextCodecV1.encode(
            rows: [historicRow],
            scope: historicScope,
            release: historic
        )
        XCTAssertEqual(
            historicBytes,
            Data("Version,Asset ID,Note\nc50-v1,0,[]\n".utf8)
        )

        let disabledCoordinator = try IncumbentFileExchangeCoordinatorV1(
            registry: disabledRegistry,
            adapters: []
        )
        XCTAssertThrowsError(
            try disabledCoordinator.render(
                projections: [historicExport.projection],
                scope: historicScope,
                at: C50IncumbentFileAdapterTestSupport.fixedDate
            )
        ) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .noSelectedProfile)
        }
    }

    func testV23P03C50H01StrictHeadersEncodingBudgetsAndPrivacyFailClosed() throws {
        let corpus = try C50IncumbentFileAdapterTestSupport.corpus()
        XCTAssertEqual(
            Set(corpus.strictHostileCases),
            Set([
                "UNKNOWN_VERSION", "REORDERED_HEADERS", "DUPLICATE_HEADERS",
                "UTF8_INVALID_SEQUENCE", "NFC_NONCANONICAL_TEXT", "LF_INPUT",
                "CRLF_INPUT", "QUOTED_CELL", "EMBEDDED_NEWLINE", "CONTROL_SCALAR",
                "FORMULA_PREFIX", "DUPLICATE_MAPPING", "STALE_SELECTION", "OVERSIZE_BYTES",
                "OVERSIZE_ROWS", "OVERSIZE_SCALAR", "PRIVATE_FIELD_WITHOUT_APPROVAL",
                "TWO_CURRENT_PROFILES", "DIVERGENT_SAME_OPERATION"
            ])
        )

        let release = try C50IncumbentFileAdapterTestSupport.profile()
        let validDigest = C50IncumbentFileAdapterTestSupport.digest()
        XCTAssertThrowsError(
            try IncumbentFileDetectionV1(
                release: release,
                inputSHA256: validDigest,
                observedHeaders: ["Asset ID", "Version", "Note"],
                observedVersion: release.versionValue,
                rowCount: 1
            )
        ) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .headerMismatch)
        }
        XCTAssertThrowsError(
            try IncumbentFileDetectionV1(
                release: release,
                inputSHA256: validDigest,
                observedHeaders: release.orderedHeaders,
                observedVersion: "c50-v2",
                rowCount: 1
            )
        ) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .unsupportedVersion)
        }
        XCTAssertThrowsError(
            try IncumbentFileDetectionV1(
                release: release,
                inputSHA256: validDigest,
                observedHeaders: release.orderedHeaders,
                observedVersion: release.versionValue,
                rowCount: release.budget.maximumRowCount + 1
            )
        ) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .budgetExceeded)
        }

        XCTAssertThrowsError(
            try IncumbentMappingManifestV1(
                mappings: [release.mappingManifest.mappings[0], release.mappingManifest.mappings[0]]
            )
        )
        XCTAssertThrowsError(
            try IncumbentFileContractV1.requireToken("field\"quote")
        )
        XCTAssertThrowsError(
            try IncumbentFileContractV1.requireToken("field'single")
        )
        XCTAssertThrowsError(
            try IncumbentFileContractV1.requireToken("field\\slash")
        )
        XCTAssertThrowsError(
            try IncumbentFieldMappingV1(
                externalHeader: "Header\nBreak",
                canonicalField: "header_break",
                required: false
            )
        )

        let nfc = try IncumbentFileCellV1(
            field: .workMaterialTotals,
            value: "Cafe\u{301}",
            maximumScalars: release.budget.maximumScalarCountPerCell
        )
        XCTAssertEqual(nfc.value, "Café")
        let lf = try IncumbentFileCellV1(
            field: .workMaterialTotals,
            value: "line one\nline two",
            maximumScalars: release.budget.maximumScalarCountPerCell
        )
        let crlf = try IncumbentFileCellV1(
            field: .workMaterialTotals,
            value: "line one\r\nline two",
            maximumScalars: release.budget.maximumScalarCountPerCell
        )
        XCTAssertTrue(lf.value.contains("\n"))
        XCTAssertTrue(crlf.value.contains("\r\n"))
        XCTAssertTrue(corpus.golden.inputLineEndings.contains("LF"))
        XCTAssertTrue(corpus.golden.inputLineEndings.contains("CRLF"))
        XCTAssertTrue(corpus.golden.quotedCells)
        XCTAssertTrue(corpus.golden.embeddedNewlines)
        XCTAssertTrue(corpus.golden.nfcCanonicalization)
        XCTAssertThrowsError(
            try IncumbentFileCellV1(
                field: .workMaterialTotals,
                value: "control\u{1}",
                maximumScalars: release.budget.maximumScalarCountPerCell
            )
        ) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .budgetExceeded)
        }
        XCTAssertThrowsError(
            try IncumbentFileCellV1(
                field: .workMaterialTotals,
                value: String(repeating: "x", count: release.budget.maximumScalarCountPerCell + 1),
                maximumScalars: release.budget.maximumScalarCountPerCell
            )
        )

        let invalidUTF8 = try C50IncumbentFileAdapterTestSupport.input(
            bytes: Data([0xff, 0xfe, 0xfd])
        )
        let coordinator = try C50IncumbentFileAdapterTestSupport.coordinator(
            release: release,
            selection: try C50IncumbentFileAdapterTestSupport.enabledSelection(for: release)
        )
        let scope = try C50IncumbentFileAdapterTestSupport.scope(for: release)
        XCTAssertThrowsError(
            try coordinator.render(
                projections: [],
                scope: scope,
                at: C50IncumbentFileAdapterTestSupport.fixedDate
            )
        )
        XCTAssertThrowsError(
            try coordinator.preview(
                input: invalidUTF8,
                scope: scope,
                at: C50IncumbentFileAdapterTestSupport.fixedDate
            )
        ) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .unsupportedVersion)
        }
        XCTAssertThrowsError(
            try coordinator.preview(
                input: try C50IncumbentFileAdapterTestSupport.input(
                    bytes: Data(repeating: 0x61, count: Int(release.budget.maximumByteCount) + 1)
                ),
                scope: scope,
                at: C50IncumbentFileAdapterTestSupport.fixedDate
            )
        )

        XCTAssertThrowsError(
            try IncumbentFieldMappingV1(
                externalHeader: "Private Contact",
                canonicalField: "private.contact",
                fieldClass: .contact,
                required: false
            )
        ) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .fieldNotAllowed)
        }
        let ordinaryPrivateScope = try C50IncumbentFileAdapterTestSupport.scope(
            for: release,
            operationSlot: 13,
            ordinaryOnly: true
        )
        XCTAssertTrue(ordinaryPrivateScope.allowedCanonicalFields.contains(.workMaterialLineCount))
        XCTAssertFalse(ordinaryPrivateScope.allowedCanonicalFields.contains(.portableReviewPublicID))

        let staleSelection = try C50IncumbentFileAdapterTestSupport.enabledSelection(
            for: release,
            receiptSlot: 14,
            evidenceExpiresAt: C50IncumbentFileAdapterTestSupport.fixedDate.addingTimeInterval(1)
        )
        let staleRegistry = try ClosedIncumbentAdapterRegistryV1(
            currentProductionReleases: [release],
            selection: staleSelection,
            selectionHistory: [staleSelection],
            availabilityReceipt: try C50IncumbentFileAdapterTestSupport.availability(
                selected: true,
                release: release
            )
        )
        XCTAssertThrowsError(try staleRegistry.selectedRelease(
            at: C50IncumbentFileAdapterTestSupport.fixedDate.addingTimeInterval(2)
        )) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .staleSelection)
        }
        let secondRelease = try C50IncumbentFileAdapterTestSupport.successor(
            of: release,
            releaseSlot: 15
        )
        XCTAssertThrowsError(try ClosedIncumbentAdapterRegistryV1(
            currentProductionReleases: [release, secondRelease],
            selection: try C50IncumbentFileAdapterTestSupport.enabledSelection(for: release),
            selectionHistory: [try C50IncumbentFileAdapterTestSupport.enabledSelection(for: release)],
            availabilityReceipt: try C50IncumbentFileAdapterTestSupport.availability(
                selected: true,
                release: release
            )
        )) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .multipleSelectedProfiles)
        }
    }

    func testV23P03C50I01InterruptionCleanupAndLostCallbackAreIdempotent() async throws {
        let corpus = try C50IncumbentFileAdapterTestSupport.corpus()
        let release = try C50IncumbentFileAdapterTestSupport.profile()
        let selection = try C50IncumbentFileAdapterTestSupport.enabledSelection(for: release)
        let coordinator = try C50IncumbentFileAdapterTestSupport.coordinator(
            release: release,
            selection: selection
        )
        let input = try C50IncumbentFileAdapterTestSupport.input()
        let scope = try C50IncumbentFileAdapterTestSupport.scope(
            for: release,
            operationSlot: 20
        )
        let preview = try coordinator.preview(
            input: input,
            scope: scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        let plan = try C50IncumbentFileAdapterTestSupport.recoveryPlan(
            input: input,
            scope: scope,
            release: release,
            preview: preview.preview
        )
        let encodedForgedReference = try JSONEncoder().encode(
            C50ForgedCanonicalMutationReferenceV1(
                workspaceID: plan.workspaceID,
                mutationID: plan.expectedMutationID,
                commandBodySHA256: plan.expectedCommandBodySHA256,
                envelopeSHA256: C50IncumbentFileAdapterTestSupport.digest("e"),
                receiptSHA256: C50IncumbentFileAdapterTestSupport.digest("f"),
                expectedPlanSHA256: plan.planSHA256
            )
        )
        let decodedForgedReference = try JSONDecoder().decode(
            IncumbentCanonicalMutationReceiptReferenceV1.self,
            from: encodedForgedReference
        )
        XCTAssertThrowsError(try decodedForgedReference.requireAuthoritativelyBound()) {
            XCTAssertEqual($0 as? IncumbentFileContractFailureV1, .divergentRecovery)
        }
        XCTAssertThrowsError(try decodedForgedReference.validate(plan: plan)) {
            XCTAssertEqual($0 as? IncumbentFileContractFailureV1, .divergentRecovery)
        }
        let forgedRecovery = try coordinator.recover(
            plan: plan,
            observedSourceSHA256: input.byteSHA256,
            canonicalMutation: decodedForgedReference,
            cleanup: nil
        )
        XCTAssertEqual(forgedRecovery.disposition, .divergentQuarantined)
        XCTAssertFalse(forgedRecovery.canonicalReapplyOccurred)
        XCTAssertThrowsError(try IncumbentFileExchangeReceiptV1(
            scope: scope,
            release: release,
            inputOrOutputSHA256: input.byteSHA256,
            previewSHA256: preview.preview.previewSHA256,
            outcome: .importedCanonical,
            canonicalMutation: decodedForgedReference,
            recoveryPlan: plan,
            externalAvailability: .notAttempted,
            occurredAt: C50IncumbentFileAdapterTestSupport.fixedDate
        )) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .divergentRecovery)
        }
        let forgedReference = C50ForgedCanonicalMutationReferenceV1(
            workspaceID: plan.workspaceID,
            mutationID: plan.expectedMutationID,
            commandBodySHA256: plan.expectedCommandBodySHA256,
            envelopeSHA256: C50IncumbentFileAdapterTestSupport.digest("e"),
            receiptSHA256: C50IncumbentFileAdapterTestSupport.digest("f"),
            expectedPlanSHA256: plan.planSHA256
        )
        let forgedBasis = C50ForgedExchangeReceiptBasisV1(
            operationID: scope.operationID,
            workspaceID: scope.workspaceID,
            releaseSHA256: release.releaseSHA256,
            scopeSHA256: scope.scopeSHA256,
            inputOrOutputSHA256: input.byteSHA256,
            previewSHA256: preview.preview.previewSHA256,
            outcome: .importedCanonical,
            canonicalMutation: forgedReference,
            externalAvailability: .notAttempted,
            occurredAt: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        let forgedExchangeReceipt = C50ForgedExchangeReceiptV1(
            operationID: forgedBasis.operationID,
            workspaceID: forgedBasis.workspaceID,
            releaseSHA256: forgedBasis.releaseSHA256,
            scopeSHA256: forgedBasis.scopeSHA256,
            inputOrOutputSHA256: forgedBasis.inputOrOutputSHA256,
            previewSHA256: forgedBasis.previewSHA256,
            outcome: forgedBasis.outcome,
            canonicalMutation: forgedBasis.canonicalMutation,
            externalAvailability: forgedBasis.externalAvailability,
            occurredAt: forgedBasis.occurredAt,
            receiptSHA256: try IncumbentFileContractV1.digest(forgedBasis)
        )
        XCTAssertThrowsError(try IncumbentFileCanonicalCodecV1.decodeExchangeReceipt(
            from: try IncumbentFileCanonicalCodecV1.encode(forgedExchangeReceipt),
            scope: scope,
            release: release
        )) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .divergentRecovery)
        }
        let first = try coordinator.recover(
            plan: plan,
            observedSourceSHA256: input.byteSHA256,
            canonicalMutation: nil,
            cleanup: nil
        )
        let second = try coordinator.recover(
            plan: plan,
            observedSourceSHA256: input.byteSHA256,
            canonicalMutation: nil,
            cleanup: nil
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.disposition, .beforeCanonicalEffect)
        XCTAssertFalse(first.canonicalReapplyOccurred)
        XCTAssertEqual(first.expectedPlanSHA256, plan.planSHA256)
        XCTAssertEqual(corpus.lifecycle.interruptionDisposition, "BEFORE_CANONICAL_EFFECT")
        XCTAssertTrue(corpus.lifecycle.canonicalEffectBeforeReceipt)
        XCTAssertEqual(
            corpus.lifecycle.retryDisposition,
            "EXACT_EFFECT_AND_RECEIPT_OR_NO_EFFECT"
        )

        let lostCallback = try IncumbentFileExchangeReceiptV1(
            scope: scope,
            release: release,
            inputOrOutputSHA256: C50IncumbentFileAdapterTestSupport.digest("c"),
            previewSHA256: C50IncumbentFileAdapterTestSupport.digest("d"),
            outcome: .exportAvailabilityUnknown,
            canonicalMutation: nil,
            externalAvailability: .unknownAfterCallbackLoss,
            occurredAt: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        XCTAssertEqual(lostCallback.externalAvailability, .unknownAfterCallbackLoss)
        let decodedLostCallback = try IncumbentFileCanonicalCodecV1.decodeExchangeReceipt(
            from: try IncumbentFileCanonicalCodecV1.encode(lostCallback),
            scope: scope,
            release: release
        )
        XCTAssertEqual(decodedLostCallback, lostCallback)
        XCTAssertEqual(corpus.lifecycle.lostExportCallback, "EXTERNAL_AVAILABILITY_UNKNOWN")

        let exportRelease = try C50IncumbentFileAdapterTestSupport.profile(
            profileSlot: 30,
            releaseSlot: 31,
            direction: .exportOnly
        )
        let exportCoordinator = try C50IncumbentFileAdapterTestSupport.coordinator(
            release: exportRelease,
            selection: try C50IncumbentFileAdapterTestSupport.enabledSelection(
                for: exportRelease,
                receiptSlot: 32
            )
        )
        let exportScratch = C50IncumbentScratchSpy()
        let exportLifecycle = IncumbentFileExchangeLifecycleAdapterV1(scratch: exportScratch)
        func stagedExport(operationSlot: Int, leaseSlot: Int) async throws
            -> (binding: IncumbentFileExchangeScratchLeaseV1,
                output: Data,
                manifest: IncumbentFileExportManifestV1,
                scope: IncumbentExchangeScopeV1) {
            let export = try C50IncumbentFileAdapterTestSupport.projectionAndScope(
                for: exportRelease,
                operationSlot: operationSlot
            )
            let rendered = try exportCoordinator.render(
                projections: [export.projection],
                scope: export.scope,
                at: C50IncumbentFileAdapterTestSupport.fixedDate
            )
            let output = rendered.data
            let manifest = rendered.manifest
            let binding = try await exportLifecycle.acquireExport(
                output: output,
                manifest: manifest,
                release: exportRelease,
                scope: export.scope,
                createdAt: C50IncumbentFileAdapterTestSupport.fixedDate,
                expiresAt: C50IncumbentFileAdapterTestSupport.fixedDate.addingTimeInterval(60),
                leaseID: C50IncumbentFileAdapterTestSupport.id(leaseSlot)
            )
            _ = try await exportLifecycle.stageExport(
                output: output,
                manifest: manifest,
                release: exportRelease,
                scope: export.scope,
                binding: binding
            )
            XCTAssertEqual(binding.lease.request.purpose, .supportExport)
            XCTAssertEqual(binding.lease.request.owner, .supportExport)
            XCTAssertEqual(binding.inputSHA256, manifest.outputSHA256)
            XCTAssertEqual(binding.exportManifestSHA256, manifest.manifestSHA256)
            return (binding, output, manifest, export.scope)
        }
        let confirmedExport = try await stagedExport(operationSlot: 33, leaseSlot: 34)

        var forgedBytes = confirmedExport.output
        forgedBytes[0] = forgedBytes[0] ^ 0x01
        do {
            _ = try await exportLifecycle.acquireExport(
                output: forgedBytes,
                manifest: confirmedExport.manifest,
                release: exportRelease,
                scope: confirmedExport.scope,
                createdAt: C50IncumbentFileAdapterTestSupport.fixedDate,
                expiresAt: C50IncumbentFileAdapterTestSupport.fixedDate.addingTimeInterval(60),
                leaseID: C50IncumbentFileAdapterTestSupport.id(42)
            )
            XCTFail("acquireExport accepted bytes with a mismatched output digest")
        } catch {
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .invalidDigest)
        }
        do {
            _ = try await exportLifecycle.stageExport(
                output: forgedBytes,
                manifest: confirmedExport.manifest,
                release: exportRelease,
                scope: confirmedExport.scope,
                binding: confirmedExport.binding
            )
            XCTFail("stageExport accepted bytes with a mismatched output digest")
        } catch {
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .invalidDigest)
        }

        let foreignExport = try C50IncumbentFileAdapterTestSupport.projectionAndScope(
            for: exportRelease,
            operationSlot: 39
        )
        let wrongExportManifest = try exportCoordinator.render(
            projections: [foreignExport.projection],
            scope: foreignExport.scope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        ).manifest
        do {
            _ = try await exportLifecycle.stageExport(
                output: confirmedExport.output,
                manifest: wrongExportManifest,
                release: exportRelease,
                scope: confirmedExport.scope,
                binding: confirmedExport.binding
            )
            XCTFail("stageExport accepted a manifest bound to another scope")
        } catch {
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .invalidDigest)
        }

        let forgedManifest = try IncumbentFileExportManifestV1(
            scope: confirmedExport.scope,
            release: exportRelease,
            output: confirmedExport.output,
            rowCount: confirmedExport.manifest.rowCount + 1
        )
        do {
            _ = try await exportLifecycle.stageExport(
                output: confirmedExport.output,
                manifest: forgedManifest,
                release: exportRelease,
                scope: confirmedExport.scope,
                binding: confirmedExport.binding
            )
            XCTFail("stageExport accepted a manifest with a forged row-count digest")
        } catch {
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .headerMismatch)
        }

        let forgedRelease = try C50IncumbentFileAdapterTestSupport.profile(
            profileSlot: 31,
            releaseSlot: 39,
            direction: .exportOnly
        )
        do {
            _ = try await exportLifecycle.finishExport(
                binding: confirmedExport.binding,
                output: confirmedExport.output,
                manifest: confirmedExport.manifest,
                release: forgedRelease,
                scope: confirmedExport.scope,
                userCancelled: false,
                callbackConfirmedLocalFile: true,
                at: C50IncumbentFileAdapterTestSupport.fixedDate
            )
            XCTFail("finishExport accepted a manifest/release mismatch")
        } catch {
            XCTAssertNotNil(error as? IncumbentFileContractFailureV1)
        }

        do {
            _ = try await exportLifecycle.finish(
                binding: confirmedExport.binding,
                outcome: .exportedLocalFile,
                externalAvailability: .fileCreatedLocally,
                occurredAt: C50IncumbentFileAdapterTestSupport.fixedDate
            )
            XCTFail("generic finish exposed the export success terminal")
        } catch {
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .invalidValue)
        }

        let confirmedTerminal = try await exportLifecycle.finishExport(
            binding: confirmedExport.binding,
            output: confirmedExport.output,
            manifest: confirmedExport.manifest,
            release: exportRelease,
            scope: confirmedExport.scope,
            userCancelled: false,
            callbackConfirmedLocalFile: true,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        XCTAssertEqual(confirmedTerminal.outcome, .exportedLocalFile)
        XCTAssertEqual(confirmedTerminal.externalAvailability, .fileCreatedLocally)
        XCTAssertEqual(confirmedTerminal.scratchPurpose, .supportExport)
        XCTAssertEqual(
            confirmedTerminal.exportManifestSHA256,
            Optional(confirmedExport.manifest.manifestSHA256)
        )
        XCTAssertEqual(confirmedTerminal.scratchTerminal, .completed)
        let confirmedScratchTerminal = await exportScratch.terminal(
            for: confirmedExport.binding.lease.request.leaseID
        )
        XCTAssertEqual(confirmedScratchTerminal, .completed)

        let replay = try await exportLifecycle.finishExport(
            binding: confirmedExport.binding,
            output: confirmedExport.output,
            manifest: confirmedExport.manifest,
            release: exportRelease,
            scope: confirmedExport.scope,
            userCancelled: false,
            callbackConfirmedLocalFile: true,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        XCTAssertEqual(replay, confirmedTerminal)

        do {
            _ = try await exportLifecycle.finishExport(
                binding: confirmedExport.binding,
                output: confirmedExport.output,
                manifest: forgedManifest,
                release: exportRelease,
                scope: confirmedExport.scope,
                userCancelled: false,
                callbackConfirmedLocalFile: true,
                at: C50IncumbentFileAdapterTestSupport.fixedDate
            )
            XCTFail("finishExport replay accepted a forged manifest digest")
        } catch {
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .headerMismatch)
        }

        do {
            _ = try await exportLifecycle.finishExport(
                binding: confirmedExport.binding,
                output: forgedBytes,
                manifest: confirmedExport.manifest,
                release: exportRelease,
                scope: confirmedExport.scope,
                userCancelled: false,
                callbackConfirmedLocalFile: true,
                at: C50IncumbentFileAdapterTestSupport.fixedDate
            )
            XCTFail("finishExport accepted bytes with a forged output digest")
        } catch {
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .invalidDigest)
        }

        let unknownExport = try await stagedExport(operationSlot: 35, leaseSlot: 36)
        let unknownTerminal = try await exportLifecycle.finishExport(
            binding: unknownExport.binding,
            output: unknownExport.output,
            manifest: unknownExport.manifest,
            release: exportRelease,
            scope: unknownExport.scope,
            userCancelled: false,
            callbackConfirmedLocalFile: false,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        XCTAssertEqual(unknownTerminal.outcome, .exportAvailabilityUnknown)
        XCTAssertEqual(unknownTerminal.externalAvailability, .unknownAfterCallbackLoss)
        XCTAssertEqual(
            unknownTerminal.exportManifestSHA256,
            Optional(unknownExport.manifest.manifestSHA256)
        )
        XCTAssertEqual(unknownTerminal.scratchTerminal, .failed)
        let unknownScratchTerminal = await exportScratch.terminal(
            for: unknownExport.binding.lease.request.leaseID
        )
        XCTAssertEqual(unknownScratchTerminal, .failed)

        let cancelledExport = try await stagedExport(operationSlot: 37, leaseSlot: 38)
        let cancelledTerminal = try await exportLifecycle.finishExport(
            binding: cancelledExport.binding,
            output: cancelledExport.output,
            manifest: cancelledExport.manifest,
            release: exportRelease,
            scope: cancelledExport.scope,
            userCancelled: true,
            callbackConfirmedLocalFile: false,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        XCTAssertEqual(cancelledTerminal.outcome, .cancelled)
        XCTAssertEqual(cancelledTerminal.externalAvailability, .notAttempted)
        XCTAssertEqual(
            cancelledTerminal.exportManifestSHA256,
            Optional(cancelledExport.manifest.manifestSHA256)
        )
        XCTAssertEqual(cancelledTerminal.scratchTerminal, .cancelled)
        let cancelledScratchTerminal = await exportScratch.terminal(
            for: cancelledExport.binding.lease.request.leaseID
        )
        XCTAssertEqual(cancelledScratchTerminal, .cancelled)

        XCTAssertThrowsError(
            try IncumbentExchangeRecoveryReceiptV1(
                plan: plan,
                observedSourceSHA256: input.byteSHA256,
                observedReceiptSHA256: nil,
                cleanupEvidenceSHA256: nil,
                disposition: .appliedMatchingReceipt
            )
        ) { error in
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .divergentRecovery)
        }
        let lostSource = try coordinator.recover(
            plan: plan,
            observedSourceSHA256: C50IncumbentFileAdapterTestSupport.digest("f"),
            canonicalMutation: nil,
            cleanup: nil
        )
        XCTAssertEqual(lostSource.disposition, .divergentQuarantined)
        let cleanup = try IncumbentCleanupEvidenceV1(
            operationID: scope.operationID,
            sourceSHA256: input.byteSHA256,
            cleanupIdentitySHA256: plan.cleanupIdentitySHA256,
            cleanedAt: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        let incompleteCleanup = try coordinator.recover(
            plan: plan,
            observedSourceSHA256: input.byteSHA256,
            canonicalMutation: nil,
            cleanup: cleanup
        )
        XCTAssertEqual(incompleteCleanup.disposition, .divergentQuarantined)
        let observedReceiptSHA256 = C50IncumbentFileAdapterTestSupport.digest("e")
        let effectBeforeReceipt = try IncumbentExchangeRecoveryReceiptV1(
            plan: plan,
            observedSourceSHA256: input.byteSHA256,
            observedReceiptSHA256: observedReceiptSHA256,
            cleanupEvidenceSHA256: nil,
            disposition: .appliedMatchingReceipt
        )
        let repeatedAfterReceipt = try IncumbentExchangeRecoveryReceiptV1(
            plan: plan,
            observedSourceSHA256: input.byteSHA256,
            observedReceiptSHA256: observedReceiptSHA256,
            cleanupEvidenceSHA256: nil,
            disposition: .appliedMatchingReceipt
        )
        XCTAssertEqual(effectBeforeReceipt, repeatedAfterReceipt)
        XCTAssertEqual(Set([effectBeforeReceipt.expectedPlanSHA256,
                            repeatedAfterReceipt.expectedPlanSHA256]).count, 1)
        XCTAssertFalse(effectBeforeReceipt.canonicalReapplyOccurred)
        let cleanupOnly = try IncumbentExchangeRecoveryReceiptV1(
            plan: plan,
            observedSourceSHA256: input.byteSHA256,
            observedReceiptSHA256: observedReceiptSHA256,
            cleanupEvidenceSHA256: cleanup.evidenceSHA256,
            disposition: .cleanupOnly
        )
        XCTAssertEqual(cleanupOnly.disposition, .cleanupOnly)
        XCTAssertFalse(cleanupOnly.canonicalReapplyOccurred)

        let writerFixture = try C20PrivacyTransformTestSupport.makeFixture()
        let writerReceipt = try C20PrivacyTransformTestSupport.makeCanonicalMutationReceipt(
            for: writerFixture
        )
        let coldFields = C50IncumbentFileAdapterTestSupport.adapterFields(for: release)
        let coldBaseApproval = try C50IncumbentFileAdapterTestSupport.privacyApproval(
            workspaceID: writerFixture.workspace,
            slot: 90
        )
        let coldAdapterApproval = try C50IncumbentFileAdapterTestSupport.adapterApproval(
            privacyApproval: coldBaseApproval,
            allowedCanonicalFields: coldFields,
            slot: 230
        )
        let coldScope = try IncumbentExchangeScopeV1(
            operationID: C50IncumbentFileAdapterTestSupport.id(40),
            workspaceID: writerFixture.workspace,
            workspaceRevision: 1,
            release: release,
            direction: release.direction,
            allowedCanonicalFields: coldFields,
            privacyApproval: coldAdapterApproval
        )
        let coldPreview = try coordinator.preview(
            input: input,
            scope: coldScope,
            at: C50IncumbentFileAdapterTestSupport.fixedDate
        ).preview
        let coldPlan = try C50IncumbentFileAdapterTestSupport.recoveryPlan(
            input: input,
            scope: coldScope,
            release: release,
            preview: coldPreview,
            expectedMutationID: writerReceipt.mutationID,
            expectedCommandBodySHA256: writerReceipt.commandBodySHA256
        )
        let coldScratch = C50IncumbentScratchSpy()
        let interruptedLifecycle = IncumbentFileExchangeLifecycleAdapterV1(scratch: coldScratch)
        _ = try await interruptedLifecycle.acquire(
            input: input,
            scope: coldScope,
            createdAt: C50IncumbentFileAdapterTestSupport.fixedDate,
            expiresAt: C50IncumbentFileAdapterTestSupport.fixedDate.addingTimeInterval(60),
            leaseID: C50IncumbentFileAdapterTestSupport.id(41)
        )
        let coldStartWithoutBinding = true
        XCTAssertTrue(coldStartWithoutBinding)
        let relaunchedLifecycle = IncumbentFileExchangeLifecycleAdapterV1(scratch: coldScratch)
        let coldRecovered = try await relaunchedLifecycle.recoverColdStart(
            coordinator: coordinator,
            plan: coldPlan,
            observedSourceSHA256: input.byteSHA256,
            canonicalReceipt: writerReceipt
        )
        XCTAssertEqual(coldRecovered.recovery.disposition, .appliedMatchingReceipt)
        XCTAssertFalse(coldRecovered.recovery.canonicalReapplyOccurred)
        XCTAssertEqual(coldRecovered.scratchRecovery.recoveredExpiredLeaseCount, 1)
        XCTAssertEqual(coldRecovered.scratchRecovery.removedByteCount, 1)
        let coldRecoveryCallCount = await coldScratch.recoveryCallCount()
        XCTAssertEqual(coldRecoveryCallCount, 1)
        let coldFinishCount = await coldScratch.finishCount(
            for: C50IncumbentFileAdapterTestSupport.id(41)
        )
        XCTAssertEqual(coldFinishCount, 0)

        let coldStartDivergentAuthorityStillCleans = true
        XCTAssertTrue(coldStartDivergentAuthorityStillCleans)
        let corruptPlan = try C50IncumbentFileAdapterTestSupport.recoveryPlan(
            input: input,
            scope: coldScope,
            release: release,
            preview: coldPreview,
            expectedMutationID: try MutationIDV1(
                rawValue: C50IncumbentFileAdapterTestSupport.id(42)
            ),
            expectedCommandBodySHA256: writerReceipt.commandBodySHA256
        )
        let corruptScratch = C50IncumbentScratchSpy()
        let corruptLifecycle = IncumbentFileExchangeLifecycleAdapterV1(scratch: corruptScratch)
        _ = try await corruptLifecycle.acquire(
            input: input,
            scope: coldScope,
            createdAt: C50IncumbentFileAdapterTestSupport.fixedDate,
            expiresAt: C50IncumbentFileAdapterTestSupport.fixedDate.addingTimeInterval(60),
            leaseID: C50IncumbentFileAdapterTestSupport.id(43)
        )
        let corruptRelaunchedLifecycle = IncumbentFileExchangeLifecycleAdapterV1(
            scratch: corruptScratch
        )
        do {
            _ = try await corruptRelaunchedLifecycle.recoverColdStart(
                coordinator: coordinator,
                plan: corruptPlan,
                observedSourceSHA256: input.byteSHA256,
                canonicalReceipt: writerReceipt
            )
            XCTFail("cold-start accepted a receipt divergent from the recovery plan")
        } catch {
            XCTAssertEqual(error as? IncumbentFileContractFailureV1, .divergentRecovery)
        }
        let corruptRecoveryCallCount = await corruptScratch.recoveryCallCount()
        XCTAssertEqual(corruptRecoveryCallCount, 1)
        let corruptFinishCount = await corruptScratch.finishCount(
            for: C50IncumbentFileAdapterTestSupport.id(43)
        )
        XCTAssertEqual(corruptFinishCount, 0)

        let divergentScratch = C50IncumbentScratchSpy()
        let divergentLifecycle = IncumbentFileExchangeLifecycleAdapterV1(scratch: divergentScratch)
        _ = try await divergentLifecycle.acquire(
            input: input,
            scope: coldScope,
            createdAt: C50IncumbentFileAdapterTestSupport.fixedDate,
            expiresAt: C50IncumbentFileAdapterTestSupport.fixedDate.addingTimeInterval(60),
            leaseID: C50IncumbentFileAdapterTestSupport.id(44)
        )
        let divergentRelaunchedLifecycle = IncumbentFileExchangeLifecycleAdapterV1(
            scratch: divergentScratch
        )
        let divergentRecovered = try await divergentRelaunchedLifecycle.recoverColdStart(
            coordinator: coordinator,
            plan: coldPlan,
            observedSourceSHA256: C50IncumbentFileAdapterTestSupport.digest("f"),
            canonicalReceipt: nil
        )
        XCTAssertEqual(divergentRecovered.recovery.disposition, .divergentQuarantined)
        XCTAssertFalse(divergentRecovered.recovery.canonicalReapplyOccurred)
        XCTAssertEqual(divergentRecovered.scratchRecovery.recoveredExpiredLeaseCount, 1)
        let divergentRecoveryCallCount = await divergentScratch.recoveryCallCount()
        XCTAssertEqual(divergentRecoveryCallCount, 1)
        let divergentFinishCount = await divergentScratch.finishCount(
            for: C50IncumbentFileAdapterTestSupport.id(44)
        )
        XCTAssertEqual(divergentFinishCount, 0)

        let scratch = C50IncumbentScratchSpy()
        let lifecycle = IncumbentFileExchangeLifecycleAdapterV1(scratch: scratch)
        let binding = try await lifecycle.acquire(
            input: input,
            scope: scope,
            createdAt: C50IncumbentFileAdapterTestSupport.fixedDate,
            expiresAt: C50IncumbentFileAdapterTestSupport.fixedDate.addingTimeInterval(60),
            leaseID: C50IncumbentFileAdapterTestSupport.id(22)
        )
        _ = try await lifecycle.stage(input: input, binding: binding)
        let firstTerminal = try await lifecycle.finish(
            binding: binding,
            outcome: .failedNoEffect,
            externalAvailability: .notAttempted,
            occurredAt: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        let secondTerminal = try await lifecycle.finish(
            binding: binding,
            outcome: .failedNoEffect,
            externalAvailability: .notAttempted,
            occurredAt: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        XCTAssertEqual(firstTerminal, secondTerminal)
        XCTAssertTrue(firstTerminal.scratchDeleted)
        XCTAssertFalse(firstTerminal.canonicalEffectOccurred)
        let finishCount = await scratch.finishCount(for: binding.lease.leaseID)
        XCTAssertEqual(finishCount, 1)

        let interruptedScope = try C50IncumbentFileAdapterTestSupport.scope(
            for: release,
            operationSlot: 23
        )
        let interrupted = try await lifecycle.acquire(
            input: input,
            scope: interruptedScope,
            createdAt: C50IncumbentFileAdapterTestSupport.fixedDate,
            expiresAt: C50IncumbentFileAdapterTestSupport.fixedDate.addingTimeInterval(60),
            leaseID: C50IncumbentFileAdapterTestSupport.id(24)
        )
        _ = try await lifecycle.stage(input: input, binding: interrupted)
        let interruptionSummary = try await lifecycle.recoverAfterInterruption()
        XCTAssertEqual(interruptionSummary.recoveredExpiredLeaseCount, 1)
        let recoveryCallCount = await scratch.recoveryCallCount()
        XCTAssertEqual(recoveryCallCount, 1)
        let quarantine = try IncumbentFileQuarantineReceiptV1(
            operationID: scope.operationID,
            inputSHA256: C50IncumbentFileAdapterTestSupport.digest("e"),
            releaseSHA256: release.releaseSHA256,
            reason: .sourceChanged,
            quarantinedAt: C50IncumbentFileAdapterTestSupport.fixedDate
        )
        XCTAssertFalse(quarantine.canonicalEffectOccurred)
        XCTAssertTrue(C50IncumbentFileExchangeProtectedFileBoundaryV1.validate())
        XCTAssertEqual(corpus.recovery, [
            "BEFORE_EFFECT_ZERO",
            "EFFECT_BEFORE_RECEIPT_EXACTLY_ONE",
            "AFTER_RECEIPT_IDEMPOTENT",
            "LOST_CALLBACK_UNKNOWN_EXTERNAL_AVAILABILITY",
            "DIVERGENT_SAME_OPERATION_QUARANTINED",
            "HISTORIC_READ_EXPORT_PRESERVES_BYTES",
            "CLONE_FORK_HISTORY_ONLY",
            "ERASE_REMOVES_APP_OWNED_SCRATCH",
        ])
    }

    func testV23P03C50R01HistoricRebindCloneForkEraseAndPrivacyBoundaries() throws {
        let corpus = try C50IncumbentFileAdapterTestSupport.corpus()
        let release = try C50IncumbentFileAdapterTestSupport.profile()
        let historic = try C50IncumbentFileAdapterTestSupport.successor(of: release)
        let sourceRows = try C50IncumbentFileAdapterTestSupport.rows(for: release)
        let reboundRows = try C50IncumbentFileAdapterTestSupport.rows(for: historic)
        XCTAssertEqual(sourceRows, reboundRows)
        XCTAssertNotEqual(release.releaseID, historic.releaseID)
        XCTAssertNotEqual(release.releaseSHA256, historic.releaseSHA256)
        XCTAssertEqual(historic.predecessorReleaseID, release.releaseID)
        XCTAssertEqual(historic.predecessorReleaseSHA256, release.releaseSHA256)

        XCTAssertTrue(
            C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.validate(mode: .replaceExisting)
        )
        XCTAssertTrue(
            C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.validate(mode: .clone)
        )
        XCTAssertTrue(
            C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.validate(mode: .fork)
        )
        XCTAssertTrue(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.validate(.clone))
        XCTAssertTrue(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.validate(.fork))
        XCTAssertFalse(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.cloneForkCopiesSessionState)
        XCTAssertFalse(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.cloneForkCopiesSecurityBookmarks)
        XCTAssertFalse(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.cloneForkReinterpretsReleasedFiles)
        XCTAssertTrue(C50IncumbentFileExchangeEraseAllBoundaryV1.removesAppOwnedScratch)
        XCTAssertTrue(C50IncumbentFileExchangeEraseAllBoundaryV1.removesAppOwnedQuarantine)
        XCTAssertFalse(C50IncumbentFileExchangeEraseAllBoundaryV1.recallsEscapedFiles)
        XCTAssertTrue(C50IncumbentFileExchangeEraseIntentStoreBoundaryV1.appOwnedScratchParticipatesInEraseInventory)
        XCTAssertTrue(C50IncumbentFileExchangeEraseIntentStoreBoundaryV1.appOwnedQuarantineParticipatesInEraseInventory)
        XCTAssertTrue(C50IncumbentFileExchangeWholeSignDeletionServiceBoundaryV1.preservesCanonicalImportedRowsPerExistingGraph)
        XCTAssertTrue(C50IncumbentFileExchangeKernelDeletionEnrollmentV1.ordinaryDeletionPreservesCanonicalHistory)
        XCTAssertFalse(corpus.lifecycle.cloneForkCopySelection)
        XCTAssertTrue(corpus.lifecycle.eraseRemovesAppOwnedScratch)
        XCTAssertFalse(corpus.lifecycle.eraseRecallsExternalFiles)

        XCTAssertTrue(corpus.privacy.privateFieldsRequireExplicitApproval)
        XCTAssertFalse(corpus.privacy.diagnosticsContainCustomerRows)
        XCTAssertFalse(corpus.privacy.diagnosticsContainSourceBytes)
        XCTAssertFalse(corpus.privacy.accessibilityContainsPrivateValues)
        XCTAssertFalse(corpus.privacy.networkEndpoints)
        XCTAssertFalse(corpus.privacy.credentialsOrBookmarks)
        XCTAssertFalse(corpus.privacy.providerSDK)
        XCTAssertTrue(corpus.accessibility.errorFocusRequired)
        XCTAssertTrue(corpus.accessibility.dynamicTypeAndVoiceOver)
        XCTAssertTrue(corpus.accessibility.rtlSafe)
        XCTAssertTrue(corpus.accessibility.statusLabel.contains("no selected profile"))
        XCTAssertTrue(corpus.accessibility.previewLabel.contains("no workspace changes"))
        XCTAssertFalse(corpus.accessibility.statusLabel.contains("private.contact"))
        XCTAssertFalse(corpus.accessibility.previewLabel.contains("private@example.invalid"))
    }
}
