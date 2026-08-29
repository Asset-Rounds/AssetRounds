import CryptoKit
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

private final class C45AssetLocatorCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityShortCodeUsesExistingExternalKeyAuthority() throws {
        let code = try ManualShortCodeV1(randomBody: "23456789AB")
        let key = try code.externalKey()
        XCTAssertEqual(key.namespaceID, ManualShortCodeV1.externalKeyNamespace)
        XCTAssertEqual(key.normalization, .asciiCaseInsensitive)
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.createsSecondLocatorStore)
    }
}

private final class C30EvidenceContextAnchorV9_41AssetLocator: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

@MainActor
final class V9_41AssetLocatorTests: XCTestCase {
    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    func testV23P03C27G01StableLocatorResolutionHasEightClosedOutcomesAndSourceParity() async throws {
        let workspaceID = Self.workspace(1)
        let active = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(2),
            locatorID: Self.id(3),
            value: "tag-1",
            mutationSlot: 4
        )
        let retired = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(5),
            locatorID: Self.id(6),
            value: "tag-retired",
            mutationSlot: 7,
            state: .retired
        )
        let revoked = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(8),
            locatorID: Self.id(9),
            value: "tag-revoked",
            mutationSlot: 10,
            state: .revoked
        )
        let replacement = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(11),
            locatorID: Self.id(12),
            value: "tag-replacement",
            mutationSlot: 13
        )
        let replaced = try Self.successor(
            of: active,
            value: "tag-1",
            mutationSlot: 14,
            state: .replaced,
            replacementID: replacement.locatorID
        )
        let candidateA = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(15),
            locatorID: Self.id(16),
            value: "same-key",
            mutationSlot: 17
        )
        let candidateB = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(18),
            locatorID: Self.id(19),
            value: "same-key",
            mutationSlot: 20
        )

        XCTAssertEqual(
            Set(LocatorInputSourceV1.allCases),
            [.camera, .manual, .imported]
        )
        XCTAssertEqual(
            Set(AssetLocatorStateV1.allCases),
            [.active, .retired, .revoked, .replaced]
        )
        XCTAssertEqual(LocatorResolutionOutcomeV1.allCases.count, 8)
        XCTAssertEqual(
            Set(LocatorBindingActionV1.allCases),
            [.bind, .rebind, .retire, .revoke, .replace, .rotateSigningKey]
        )

        let outcomeMatrix: [(LocatorResolutionOutcomeV1, AssetLocatorV1?, UUID?, [AssetLocatorV1])] = [
            (.matched, active, nil, []),
            (.noMatch, nil, nil, []),
            (.foreignWorkspace, nil, nil, []),
            (.ambiguous, nil, nil, [candidateA, candidateB]),
            (.damagedOrIncomplete, nil, nil, []),
            (.retired, retired, nil, []),
            (.revoked, revoked, nil, []),
            (.replaced, replaced, replacement.locatorID, [])
        ]
        for (outcome, locator, replacementID, candidates) in outcomeMatrix {
            let resolution = try LocatorResolutionV1(
                workspaceID: workspaceID,
                source: .manual,
                inputSHA256: Self.digest("a"),
                outcome: outcome,
                matchedLocator: try locator?.reference,
                matchedAssetID: locator?.assetID,
                replacementLocatorID: replacementID,
                candidateLocators: try candidates.map { try $0.reference },
                evaluatedAt: Self.date(21)
            )
            try resolution.validate()
        }
        XCTAssertEqual(
            Set(outcomeMatrix.map(\.0)),
            Set(LocatorResolutionOutcomeV1.allCases)
        )

        let key = try ExternalKeyV1(
            namespaceID: "asset",
            normalization: .asciiCaseInsensitive,
            suppliedValue: "TAG-1"
        )
        let bytes = Data("tag-1".utf8)
        let query = Self.query([active])
        let coordinator = AssetLocatorCoordinatorV1(
            resolver: OfflineAssetLocatorResolverV1(
                query: query,
                signatureVerifier: Ed25519LocalLocatorSignatureVerifierV1()
            )
        )
        let decoder = AssetLocatorInputDecoderV1()
        var results: [LocatorResolutionV1] = []
        for source in LocatorInputSourceV1.allCases {
            let input = try decoder.externalKey(
                bytes,
                namespaceID: "asset",
                normalization: .asciiCaseInsensitive,
                source: source
            )
            let result = try await Self.resolve(
                coordinator,
                input: input,
                workspaceID: workspaceID,
                source: source,
                evaluatedAt: Self.date(22)
            )
            results.append(result)
            XCTAssertEqual(result.source, source)
            XCTAssertEqual(result.outcome, .matched)
            XCTAssertEqual(result.matchedLocator, try active.reference)
            XCTAssertEqual(result.matchedAssetID, active.assetID)
        }
        XCTAssertEqual(Set(results.map(\.outcome)), [.matched])
        XCTAssertEqual(Set(results.compactMap(\.matchedAssetID)), [active.assetID])
        XCTAssertEqual(results.map(\.inputSHA256), Array(repeating: KernelCanonicalHashV1.sha256(bytes), count: 3))
        XCTAssertEqual(key.lookupKey, active.lookupKey)

        let encoded = try AssetLocatorCanonicalCodecV1.encode(active)
        XCTAssertEqual(try AssetLocatorCanonicalCodecV1.decode(AssetLocatorV1.self, from: encoded), active)
        XCTAssertEqual(encoded, try AssetLocatorCanonicalCodecV1.encode(active))
    }

    func testV23P03C27A01CanonicalKeysSignaturesBindingsAndRowsRemainImmutable() async throws {
        let workspaceID = Self.workspace(30)
        let nfcDecomposed = try ExternalKeyV1(
            namespaceID: "equipment",
            normalization: .exactNFC,
            suppliedValue: "Cafe\u{301}"
        )
        let nfcComposed = try ExternalKeyV1(
            namespaceID: "equipment",
            normalization: .exactNFC,
            suppliedValue: "Café"
        )
        XCTAssertEqual(nfcDecomposed, nfcComposed)
        XCTAssertEqual(
            try ExternalKeyV1(
                namespaceID: "equipment",
                normalization: .asciiCaseInsensitive,
                suppliedValue: "asset-42"
            ),
            try ExternalKeyV1(
                namespaceID: "equipment",
                normalization: .asciiCaseInsensitive,
                suppliedValue: "ASSET-42"
            )
        )
        let normalizedBytes = try AssetLocatorCanonicalCodecV1.encode(nfcComposed)
        XCTAssertFalse(String(decoding: normalizedBytes, as: UTF8.self).contains("Café"))

        let active = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(31),
            locatorID: Self.id(32),
            value: "tag-a",
            mutationSlot: 33
        )
        let successor = try Self.successor(
            of: active,
            value: "tag-b",
            mutationSlot: 34
        )
        let replacement = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(35),
            locatorID: Self.id(36),
            value: "tag-c",
            mutationSlot: 37
        )
        let coordinator = AssetLocatorCoordinatorV1(
            resolver: OfflineAssetLocatorResolverV1(
                query: Self.query([active]),
                signatureVerifier: Ed25519LocalLocatorSignatureVerifierV1()
            )
        )
        let bindPreview = try coordinator.preview(
            action: .bind,
            before: nil,
            after: active,
            replacement: nil,
            generatedAt: Self.date(38)
        )
        let actor = try Self.actor(workspaceID: workspaceID, slot: 39)
        let bindReceipt = try LocatorBindingReceiptV1(
            receiptID: Self.id(40),
            preview: bindPreview,
            recordedBy: actor,
            predecessor: nil,
            revision: 1,
            mutationID: try Self.mutation(33),
            recordedAt: Self.date(42)
        )
        let rebindPreview = try coordinator.preview(
            action: .rebind,
            before: active,
            after: successor,
            replacement: nil,
            generatedAt: Self.date(43)
        )
        let rebindReceipt = try LocatorBindingReceiptV1(
            receiptID: Self.id(44),
            preview: rebindPreview,
            recordedBy: actor,
            predecessor: bindReceipt,
            revision: 2,
            mutationID: try Self.mutation(34),
            recordedAt: Self.date(46)
        )
        try rebindReceipt.validate(preview: rebindPreview, predecessor: bindReceipt)
        let replacementBindPreview = try coordinator.preview(
            action: .bind,
            before: nil,
            after: replacement,
            replacement: nil,
            generatedAt: Self.date(47)
        )
        let replacementBindReceipt = try LocatorBindingReceiptV1(
            receiptID: Self.id(48),
            preview: replacementBindPreview,
            recordedBy: actor,
            predecessor: nil,
            revision: 1,
            mutationID: try Self.mutation(37),
            recordedAt: Self.date(50)
        )

        let closure = try AssetLocatorLifecycleClosureV1(
            locators: [active, successor, replacement],
            receipts: [bindReceipt, rebindReceipt, replacementBindReceipt]
        )
        try AssetLocatorLifecycleAdapterV1(
            resolver: coordinator.resolver
        ).validateClosure(locators: closure.locators, receipts: closure.receipts)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.scanMutatesCanonicalState)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionGrantsAccess)

        let locatorRow = try AssetLocatorRow(active)
        XCTAssertEqual(try locatorRow.value(), active)
        try locatorRow.replace(with: successor, expectedRevision: active.revision)
        XCTAssertEqual(try locatorRow.value(), successor)

        let receiptRow = try LocatorBindingReceiptRow(bindReceipt)
        XCTAssertEqual(try receiptRow.value(predecessor: nil), bindReceipt)

        let local = try Self.signedLocalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(47),
            locatorID: Self.id(48),
            mutationSlot: 49
        )
        guard case .localSigned(let payload) = local.representation else {
            return XCTFail("canonical local locator representation disappeared")
        }
        let localInput = try AssetLocatorInputDecoderV1().localSigned(
            try AssetLocatorCanonicalCodecV1.encode(payload),
            source: .camera
        )
        let localResult = try await coordinatorFor(local).resolveCamera(
            localInput,
            workspaceID: workspaceID,
            evaluatedAt: Self.date(50)
        )
        XCTAssertEqual(localResult.outcome, .matched)
        XCTAssertEqual(localResult.matchedAssetID, local.assetID)

        let frozen = try FrozenAssetLocatorInterpretationV1(
            locator: try active.reference,
            receipt: bindReceipt,
            assetID: active.assetID
        )
        try frozen.validate()
        XCTAssertEqual(frozen.locator, try active.reference)
        XCTAssertEqual(frozen.bindingReceiptSHA256, bindReceipt.receiptSHA256)

        let replacePreview = try coordinator.preview(
            action: .replace,
            before: active,
            after: try Self.successor(
                of: active,
                value: "tag-a",
                mutationSlot: 51,
                state: .replaced,
                replacementID: replacement.locatorID
            ),
            replacement: replacement,
            generatedAt: Self.date(52)
        )
        XCTAssertEqual(replacePreview.action, .replace)
        XCTAssertNotNil(replacePreview.replacement)
    }

    func testV23P03C27H01ForeignRevokedPartialOversizedCollisionAndStaleInputsFailClosed() async throws {
        let workspaceID = Self.workspace(60)
        let foreignWorkspaceID = Self.workspace(61)
        let foreign = try Self.signedLocalLocator(
            workspaceID: foreignWorkspaceID,
            assetID: Self.id(62),
            locatorID: Self.id(63),
            mutationSlot: 64
        )
        guard case .localSigned(let foreignPayload) = foreign.representation else {
            return XCTFail("expected a signed local payload")
        }
        let decoder = AssetLocatorInputDecoderV1()
        let foreignInput = try decoder.localSigned(
            try AssetLocatorCanonicalCodecV1.encode(foreignPayload),
            source: .imported
        )
        let foreignResult = try await coordinatorFor(foreign).resolveImported(
            foreignInput,
            workspaceID: workspaceID,
            evaluatedAt: Self.date(65)
        )
        XCTAssertEqual(foreignResult.outcome, .foreignWorkspace)

        let revoked = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(66),
            locatorID: Self.id(67),
            value: "revoked",
            mutationSlot: 68,
            state: .revoked
        )
        let replacement = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(69),
            locatorID: Self.id(70),
            value: "replacement",
            mutationSlot: 71
        )
        let replaced = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(72),
            locatorID: Self.id(73),
            value: "replaced",
            mutationSlot: 74,
            state: .replaced,
            replacementID: replacement.locatorID
        )
        let outcomeResolver = coordinatorFor([revoked, replaced, replacement])
        for (locator, rawValue, expected) in [
            (revoked, "revoked", LocatorResolutionOutcomeV1.revoked),
            (replaced, "replaced", LocatorResolutionOutcomeV1.replaced)
        ] {
            let input = try decoder.externalKey(
                Data(rawValue.utf8),
                namespaceID: "asset",
                normalization: .asciiCaseInsensitive,
                source: .manual
            )
            let result = try await outcomeResolver.resolveManual(
                input,
                workspaceID: workspaceID,
                evaluatedAt: Self.date(75)
            )
            XCTAssertEqual(result.outcome, expected)
        }

        let partial = try decoder.localSigned(Data("partial".utf8), source: .camera)
        let partialResult = try await coordinatorFor([]).resolveCamera(
            partial,
            workspaceID: workspaceID,
            evaluatedAt: Self.date(76)
        )
        XCTAssertEqual(partialResult.outcome, .damagedOrIncomplete)
        let oversizedBytes = Data(repeating: 0, count: AssetLocatorLimitsV1.maximumInputBytes + 1)
        XCTAssertThrowsError(
            try LocatorResolutionInputV1(
                source: .camera,
                rawBytes: oversizedBytes,
                decoded: .damagedOrIncomplete
            )
        )
        let oversized = try decoder.externalKey(
            oversizedBytes,
            namespaceID: "asset",
            normalization: .asciiCaseInsensitive,
            source: .camera
        )
        let oversizedResult = try await coordinatorFor([]).resolveCamera(
            oversized,
            workspaceID: workspaceID,
            evaluatedAt: Self.date(77)
        )
        XCTAssertEqual(oversizedResult.outcome, .damagedOrIncomplete)
        XCTAssertThrowsError(
            try ExternalKeyV1(
                namespaceID: String(repeating: "n", count: AssetLocatorLimitsV1.maximumNamespaceBytes + 1),
                normalization: .exactNFC,
                suppliedValue: "x"
            )
        )
        XCTAssertThrowsError(
            try ExternalKeyV1(
                namespaceID: "asset",
                normalization: .exactNFC,
                suppliedValue: "bad\u{202E}value"
            )
        )

        let collisionA = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(78),
            locatorID: Self.id(79),
            value: "collision",
            mutationSlot: 80
        )
        let collisionB = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(81),
            locatorID: Self.id(82),
            value: "collision",
            mutationSlot: 83
        )
        let collisionInput = try decoder.externalKey(
            Data("collision".utf8),
            namespaceID: "asset",
            normalization: .asciiCaseInsensitive,
            source: .manual
        )
        let collisionResult = try await coordinatorFor([collisionA, collisionB]).resolveManual(
            collisionInput,
            workspaceID: workspaceID,
            evaluatedAt: Self.date(84)
        )
        XCTAssertEqual(collisionResult.outcome, .ambiguous)
        XCTAssertEqual(collisionResult.candidateLocators.count, 2)
        XCTAssertThrowsError(
            try AssetLocatorLifecycleClosureV1(locators: [collisionA, collisionB], receipts: [])
        )

        let many = try (0..<33).map { index in
            try Self.externalLocator(
                workspaceID: workspaceID,
                assetID: Self.id(UInt8(90 + index)),
                locatorID: Self.id(UInt8(120 + index)),
                value: "many",
                mutationSlot: UInt8(index + 1)
            )
        }
        let manyInput = try decoder.externalKey(
            Data("many".utf8),
            namespaceID: "asset",
            normalization: .asciiCaseInsensitive,
            source: .manual
        )
        let manyResult = try await coordinatorFor(many).resolveManual(
            manyInput,
            workspaceID: workspaceID,
            evaluatedAt: Self.date(126)
        )
        XCTAssertEqual(manyResult.outcome, .ambiguous)
        XCTAssertEqual(manyResult.candidateLocators.count, AssetLocatorLimitsV1.maximumCandidates)

        let staleBase = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(160),
            locatorID: Self.id(161),
            value: "stale",
            mutationSlot: 162
        )
        let staleCoordinator = coordinatorFor([staleBase])
        XCTAssertThrowsError(
            try staleCoordinator.preview(
                action: .rebind,
                before: staleBase,
                after: staleBase,
                replacement: nil,
                generatedAt: Self.date(163)
            )
        )
        let staleSuccessor = try Self.successor(of: staleBase, value: "stale-2", mutationSlot: 164)
        let staleRow = try AssetLocatorRow(staleBase)
        XCTAssertThrowsError(try staleRow.replace(with: staleSuccessor, expectedRevision: 999))
        let invalidReference = AssetLocatorReferenceV1(
            locatorID: Self.id(165),
            revision: 1,
            locatorSHA256: String(repeating: "z", count: 64)
        )
        XCTAssertThrowsError(
            try LocatorBindingPreviewV1(
                workspaceID: workspaceID,
                action: .bind,
                before: nil,
                after: invalidReference,
                replacement: nil,
                generatedAt: Self.date(166)
            )
        )

        let basePreview = try staleCoordinator.preview(
            action: .bind,
            before: nil,
            after: staleBase,
            replacement: nil,
            generatedAt: Self.date(167)
        )
        let baseReceipt = try LocatorBindingReceiptV1(
            receiptID: Self.id(168),
            preview: basePreview,
            recordedBy: try Self.actor(workspaceID: workspaceID, slot: 169),
            predecessor: nil,
            revision: 1,
            mutationID: try Self.mutation(162),
            recordedAt: Self.date(171)
        )
        let nextPreview = try staleCoordinator.preview(
            action: .rebind,
            before: staleBase,
            after: staleSuccessor,
            replacement: nil,
            generatedAt: Self.date(172)
        )
        let forkA = try LocatorBindingReceiptV1(
            receiptID: Self.id(173),
            preview: nextPreview,
            recordedBy: try Self.actor(workspaceID: workspaceID, slot: 174),
            predecessor: baseReceipt,
            revision: 2,
            mutationID: try Self.mutation(164),
            recordedAt: Self.date(176)
        )
        let forkB = try LocatorBindingReceiptV1(
            receiptID: Self.id(177),
            preview: nextPreview,
            recordedBy: try Self.actor(workspaceID: workspaceID, slot: 178),
            predecessor: baseReceipt,
            revision: 2,
            mutationID: try Self.mutation(164),
            recordedAt: Self.date(180)
        )
        XCTAssertThrowsError(
            try AssetLocatorLifecycleClosureV1(
                locators: [staleBase, staleSuccessor],
                receipts: [baseReceipt, forkA, forkB]
            )
        )
        XCTAssertThrowsError(
            try LocatorBindingReceiptV1(
                receiptID: Self.id(181),
                preview: nextPreview,
                recordedBy: try Self.actor(workspaceID: workspaceID, slot: 182),
                predecessor: baseReceipt,
                revision: UInt64.max,
                mutationID: try Self.mutation(183),
                recordedAt: Self.date(184)
            )
        )

        do {
            _ = try await staleCoordinator.resolveCamera(
                try decoder.externalKey(
                    Data("stale".utf8),
                    namespaceID: "asset",
                    normalization: .asciiCaseInsensitive,
                    source: .manual
                ),
                workspaceID: workspaceID,
                evaluatedAt: Self.date(185)
            )
            XCTFail("source-specific resolver must reject a manual input")
        } catch {
            XCTAssertEqual(error as? AssetLocatorFailureV1, .invalidValue)
        }
    }

    func testV23P03C27I01CanonicalRowsRetryFromOnlyOldOrNewStateAndReplayDeterministically() async throws {
        let workspaceID = Self.workspace(190)
        let original = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(191),
            locatorID: Self.id(192),
            value: "retry",
            mutationSlot: 193
        )
        let successor = try Self.successor(
            of: original,
            value: "retry-next",
            mutationSlot: 194
        )
        let adapter = AssetLocatorLifecycleAdapterV1(
            resolver: OfflineAssetLocatorResolverV1(
                query: Self.query([original]),
                signatureVerifier: Ed25519LocalLocatorSignatureVerifierV1()
            )
        )
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.scanMutatesCanonicalState)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionGrantsAccess)

        let row = try AssetLocatorRow(original)
        XCTAssertEqual(try row.value(), original)
        try row.replace(with: successor, expectedRevision: original.revision)
        XCTAssertEqual(try row.value(), successor)
        XCTAssertThrowsError(try row.replace(with: successor, expectedRevision: original.revision))
        XCTAssertThrowsError(try row.replace(with: original, expectedRevision: successor.revision))

        let preview = try LocatorBindingPreviewV1(
            workspaceID: workspaceID,
            action: .bind,
            before: nil,
            after: try original.reference,
            replacement: nil,
            generatedAt: Self.date(195)
        )
        let receipt = try LocatorBindingReceiptV1(
            receiptID: Self.id(196),
            preview: preview,
            recordedBy: try Self.actor(workspaceID: workspaceID, slot: 197),
            predecessor: nil,
            revision: 1,
            mutationID: try Self.mutation(193),
            recordedAt: Self.date(199)
        )
        let receiptRow = try LocatorBindingReceiptRow(receipt)
        XCTAssertEqual(try receiptRow.value(predecessor: nil), receipt)
        receiptRow.canonicalData.append(0x20)
        XCTAssertThrowsError(try receiptRow.value())

        let input = try AssetLocatorInputDecoderV1().externalKey(
            Data("retry".utf8),
            namespaceID: "asset",
            normalization: .asciiCaseInsensitive,
            source: .manual
        )
        let coordinator = AssetLocatorCoordinatorV1(
            resolver: OfflineAssetLocatorResolverV1(
                query: Self.query([original]),
                signatureVerifier: Ed25519LocalLocatorSignatureVerifierV1()
            )
        )
        let first = try await coordinator.resolveManual(
            input,
            workspaceID: workspaceID,
            evaluatedAt: Self.date(200)
        )
        let replay = try await coordinator.resolveManual(
            input,
            workspaceID: workspaceID,
            evaluatedAt: Self.date(200)
        )
        XCTAssertEqual(first, replay)
        XCTAssertEqual(first.outcome, .matched)
        XCTAssertEqual(first.matchedAssetID, original.assetID)

        try adapter.validateClosure(locators: [original], receipts: [receipt])
        let canonical = try AssetLocatorCanonicalCodecV1.encode(original)
        XCTAssertEqual(try AssetLocatorCanonicalCodecV1.decode(AssetLocatorV1.self, from: canonical), original)
        let nonCanonical = canonical + Data([0x20])
        XCTAssertThrowsError(
            try AssetLocatorCanonicalCodecV1.decode(AssetLocatorV1.self, from: nonCanonical)
        )
    }

    func testV23P03C27R01RetirementReplacementAndFrozenHistorySurviveOfflineRecovery() async throws {
        let workspaceID = Self.workspace(210)
        let active = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(211),
            locatorID: Self.id(212),
            value: "historic",
            mutationSlot: 213
        )
        let retired = try Self.successor(
            of: active,
            value: "historic",
            mutationSlot: 214,
            state: .retired
        )
        let replacement = try Self.externalLocator(
            workspaceID: workspaceID,
            assetID: Self.id(215),
            locatorID: Self.id(216),
            value: "new-locator",
            mutationSlot: 218
        )
        let replaced = try Self.successor(
            of: active,
            value: "historic",
            mutationSlot: 218,
            state: .replaced,
            replacementID: replacement.locatorID
        )
        let coordinator = AssetLocatorCoordinatorV1(
            resolver: OfflineAssetLocatorResolverV1(
                query: Self.query([retired, replacement]),
                signatureVerifier: Ed25519LocalLocatorSignatureVerifierV1()
            )
        )
        let bindPreview = try coordinator.preview(
            action: .bind,
            before: nil,
            after: active,
            replacement: nil,
            generatedAt: Self.date(219)
        )
        let actor = try Self.actor(workspaceID: workspaceID, slot: 220)
        let bindReceipt = try LocatorBindingReceiptV1(
            receiptID: Self.id(221),
            preview: bindPreview,
            recordedBy: actor,
            predecessor: nil,
            revision: 1,
            mutationID: try Self.mutation(213),
            recordedAt: Self.date(223)
        )
        let retirePreview = try coordinator.preview(
            action: .retire,
            before: active,
            after: retired,
            replacement: nil,
            generatedAt: Self.date(224)
        )
        let retireReceipt = try LocatorBindingReceiptV1(
            receiptID: Self.id(225),
            preview: retirePreview,
            recordedBy: actor,
            predecessor: bindReceipt,
            revision: 2,
            mutationID: try Self.mutation(214),
            recordedAt: Self.date(227)
        )
        let retiredClosure = try AssetLocatorLifecycleClosureV1(
            locators: [active, retired],
            receipts: [bindReceipt, retireReceipt]
        )
        try retiredClosure.validate()

        let frozen = try FrozenAssetLocatorInterpretationV1(
            locator: try active.reference,
            receipt: bindReceipt,
            assetID: active.assetID
        )
        try frozen.validate()
        XCTAssertNotEqual(try retired.reference, frozen.locator)
        XCTAssertEqual(frozen.locator, try active.reference)
        XCTAssertEqual(frozen.assetIDAtCapture, active.assetID)
        XCTAssertEqual(frozen.resolutionOutcome, .matched)

        let historicInput = try AssetLocatorInputDecoderV1().externalKey(
            Data("historic".utf8),
            namespaceID: "asset",
            normalization: .asciiCaseInsensitive,
            source: .manual
        )
        let historicResult = try await coordinator.resolveManual(
            historicInput,
            workspaceID: workspaceID,
            evaluatedAt: Self.date(228)
        )
        XCTAssertEqual(historicResult.outcome, .retired)
        XCTAssertEqual(historicResult.matchedAssetID, active.assetID)

        let replacementPreview = try coordinator.preview(
            action: .replace,
            before: active,
            after: replaced,
            replacement: replacement,
            generatedAt: Self.date(229)
        )
        XCTAssertEqual(replacementPreview.action, .replace)
        XCTAssertEqual(replacementPreview.replacement, try replacement.reference)
        let replacementReceipt = try LocatorBindingReceiptV1(
            receiptID: Self.id(230),
            preview: replacementPreview,
            recordedBy: actor,
            predecessor: bindReceipt,
            revision: 2,
            mutationID: try Self.mutation(218),
            recordedAt: Self.date(232)
        )
        let replacementClosure = try AssetLocatorLifecycleClosureV1(
            locators: [active, replaced, replacement],
            receipts: [bindReceipt, replacementReceipt]
        )
        try replacementClosure.validate()
        try frozen.validate()

        let foreignWorkspace = Self.workspace(233)
        let foreignLocal = try Self.signedLocalLocator(
            workspaceID: foreignWorkspace,
            assetID: active.assetID,
            locatorID: active.locatorID,
            mutationSlot: 234
        )
        guard case .localSigned(let foreignPayload) = foreignLocal.representation else {
            return XCTFail("expected a local signed payload")
        }
        XCTAssertThrowsError(
            try AssetLocatorV1(
                locatorID: active.locatorID,
                workspaceID: workspaceID,
                assetID: active.assetID,
                representation: .localSigned(foreignPayload),
                state: .active,
                revision: 1,
                mutationID: try Self.mutation(235),
                recordedAt: Self.date(236)
            )
        )
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.scanMutatesCanonicalState)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionGrantsAccess)
    }

    private func coordinatorFor(_ locator: AssetLocatorV1) -> AssetLocatorCoordinatorV1 {
        coordinatorFor([locator])
    }

    private func coordinatorFor(_ locators: [AssetLocatorV1]) -> AssetLocatorCoordinatorV1 {
        AssetLocatorCoordinatorV1(
            resolver: OfflineAssetLocatorResolverV1(
                query: Self.query(locators),
                signatureVerifier: Ed25519LocalLocatorSignatureVerifierV1()
            )
        )
    }

    private static func resolve(
        _ coordinator: AssetLocatorCoordinatorV1,
        input: LocatorResolutionInputV1,
        workspaceID: WorkspaceID,
        source: LocatorInputSourceV1,
        evaluatedAt: Date
    ) async throws -> LocatorResolutionV1 {
        switch source {
        case .camera:
            return try await coordinator.resolveCamera(input, workspaceID: workspaceID, evaluatedAt: evaluatedAt)
        case .manual:
            return try await coordinator.resolveManual(input, workspaceID: workspaceID, evaluatedAt: evaluatedAt)
        case .imported:
            return try await coordinator.resolveImported(input, workspaceID: workspaceID, evaluatedAt: evaluatedAt)
        }
    }

    private static func query(_ locators: [AssetLocatorV1]) -> C27LocatorQuery {
        C27LocatorQuery(
            byID: Dictionary(uniqueKeysWithValues: locators.map { ($0.locatorID, $0) }),
            byLookup: Dictionary(grouping: locators, by: \.lookupKey)
        )
    }

    private static func externalLocator(
        workspaceID: WorkspaceID,
        assetID: UUID,
        locatorID: UUID,
        value: String,
        mutationSlot: UInt8,
        state: AssetLocatorStateV1 = .active,
        replacementID: UUID? = nil,
        revision: UInt64 = 1,
        predecessor: String? = nil
    ) throws -> AssetLocatorV1 {
        try AssetLocatorV1(
            locatorID: locatorID,
            workspaceID: workspaceID,
            assetID: assetID,
            representation: .externalKey(
                try ExternalKeyV1(
                    namespaceID: "asset",
                    normalization: .asciiCaseInsensitive,
                    suppliedValue: value
                )
            ),
            state: state,
            replacedByLocatorID: replacementID,
            predecessorLocatorSHA256: predecessor,
            revision: revision,
            mutationID: try mutation(mutationSlot),
            recordedAt: date(Double(mutationSlot))
        )
    }

    private static func successor(
        of old: AssetLocatorV1,
        value: String,
        mutationSlot: UInt8,
        state: AssetLocatorStateV1 = .active,
        replacementID: UUID? = nil
    ) throws -> AssetLocatorV1 {
        try externalLocator(
            workspaceID: old.workspaceID,
            assetID: old.assetID,
            locatorID: old.locatorID,
            value: value,
            mutationSlot: mutationSlot,
            state: state,
            replacementID: replacementID,
            revision: old.revision + 1,
            predecessor: old.locatorSHA256
        )
    }

    private static func signedLocalLocator(
        workspaceID: WorkspaceID,
        assetID: UUID,
        locatorID: UUID,
        mutationSlot: UInt8
    ) throws -> AssetLocatorV1 {
        let privateKey = Curve25519.Signing.PrivateKey()
        let signingKey = try LocatorSigningKeyReferenceV1(
            publicKeyData: privateKey.publicKey.rawRepresentation
        )
        let unsignedPayload = try SignedLocalAssetLocatorPayloadV1(
            workspaceID: workspaceID,
            locatorID: locatorID,
            locatorRevision: 1,
            assetID: assetID,
            signingKey: signingKey,
            signatureData: Data(repeating: 0, count: AssetLocatorLimitsV1.ed25519SignatureBytes)
        )
        let signature = try privateKey.signature(for: unsignedPayload.unsignedCanonicalData())
        let payload = try SignedLocalAssetLocatorPayloadV1(
            workspaceID: workspaceID,
            locatorID: locatorID,
            locatorRevision: 1,
            assetID: assetID,
            signingKey: signingKey,
            signatureData: signature
        )
        return try AssetLocatorV1(
            locatorID: locatorID,
            workspaceID: workspaceID,
            assetID: assetID,
            representation: .localSigned(payload),
            state: .active,
            revision: 1,
            mutationID: try mutation(mutationSlot),
            recordedAt: date(Double(mutationSlot))
        )
    }

    private static func actor(workspaceID: WorkspaceID, slot: UInt8) throws -> ActorSnapshotV1 {
        let actorReference = try LocalActorReferenceV1(
            actorReferenceID: id(slot),
            workspaceID: workspaceID,
            displayName: "C27 local actor"
        )
        return try ActorSnapshotV1(
            snapshotID: id(slot &+ 1),
            workspaceID: workspaceID,
            actor: actorReference,
            responsibility: .recordedBy,
            displayNameAtTime: "C27 local actor",
            capturedAt: date(Double(slot))
        )
    }

    private static func workspace(_ slot: UInt8) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    private static func mutation(_ slot: UInt8) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    private static func id(_ slot: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, slot))
    }

    private static func digest(_ hex: Character) -> String {
        String(repeating: hex, count: 64)
    }

    private static func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }
}

private struct C27LocatorQuery: AssetLocatorQueryingV1 {
    let byID: [UUID: AssetLocatorV1]
    let byLookup: [String: [AssetLocatorV1]]

    func locator(id: UUID, workspaceID: WorkspaceID) async throws -> AssetLocatorV1? {
        guard let locator = byID[id], locator.workspaceID == workspaceID else { return nil }
        return locator
    }

    func locators(lookupKey: String, workspaceID: WorkspaceID) async throws -> [AssetLocatorV1] {
        byLookup[lookupKey, default: []].filter { $0.workspaceID == workspaceID }
    }
}
private final class C31LightingAnchorV941AssetLocatorTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C33TemporalEvidenceAnchorV941AssetLocator: XCTestCase {
    func testC33V941AssetLocatorCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "locator.temporal-target-facts",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "locator.temporal-target-facts",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV941AssetLocator: XCTestCase {
    func testC32V941AssetLocatorCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .assetLocator,
            fieldID: "asset-locator.no-auto-merge",
            value: .text("one-shot location candidate")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .assetLocator,
            fieldID: "asset-locator.no-auto-merge",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V941LocatorCompatibilityTests: XCTestCase {
    func testC46AssetLocatorNeverAliasesContactPointID() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "asset-locator",
            kind: .phone,
            handoff: .text,
            slot: 46041
        )
    }
}
