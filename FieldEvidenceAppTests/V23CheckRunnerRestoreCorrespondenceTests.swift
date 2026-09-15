import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V23CheckRunnerRestoreCorrespondenceTests: XCTestCase {
    func testAllIdentityKindsUseFixedNamespacesAndLiteralForkVectors() throws {
        let sourceID = restoreMapUUID("10000000-0000-4000-8000-000000000001")
        let destinationWorkspaceID = restoreMapUUID("20000000-0000-4000-8000-000000000002")
        let vectors: [RestoreIdentityVector] = [
            .init(.roundSession, nil, sourceID),
            .init(.roundItem, nil, sourceID),
            .init(.roundLaunchPlan, nil, sourceID),
            .init(.site, nil, sourceID),
            .init(.asset, nil, sourceID),
            .init(.issue, nil, sourceID),
            .init(.parentRecord, nil, sourceID),
            .init(.workflowRecord, nil, sourceID),
            .init(.evidenceFile, nil, sourceID),
            .init(.parentDraft, "draft", restoreMapUUID("4d303e30-8c7d-58b4-94f9-b87ea7e03541")),
            .init(.childDraft, "draft", restoreMapUUID("4d303e30-8c7d-58b4-94f9-b87ea7e03541")),
            .init(.stage, "stage", restoreMapUUID("7764c132-c27a-5f50-a236-280a995beef0")),
            .init(.draftCommitPlan, "plan", restoreMapUUID("c5c83f35-a23b-55cb-bcea-f4247ab10e34")),
            .init(.saga, "saga", restoreMapUUID("1d63ddc3-e8d3-52b5-9bad-f2c1c6c77b97")),
            .init(.reservation, "reservation", restoreMapUUID("ebb6825e-5647-5e75-87a4-c084a28e25c3")),
            .init(.commitReceipt, "receipt", restoreMapUUID("bd5abe9f-4bab-5d0e-a154-b6add1695f65")),
            .init(.discardReceipt, "receipt", restoreMapUUID("bd5abe9f-4bab-5d0e-a154-b6add1695f65")),
            .init(.scratchLease, "scratchLease", restoreMapUUID("0887584d-d59c-5226-b8d1-ff9609d62f65")),
            .init(.processingJob, "processingJob", restoreMapUUID("64c5227a-9841-5a45-9fbd-d365c840a3de")),
            .init(.planMutation, "mutation.plan", restoreMapUUID("0f557986-bc14-56f3-a0a9-eba842c8a3ea")),
            .init(.checkpointMutation, "mutation.checkpoint", restoreMapUUID("bd652e94-f527-5922-86fd-ce744587e942")),
            .init(.stageMutation, "mutation.stage", restoreMapUUID("510fb1de-55b7-5668-bb9b-9631bfbc11db")),
            .init(.sagaMutation, "mutation.saga", restoreMapUUID("5f814348-1b44-5ca1-8274-073a4510ed9a")),
            .init(.reservationMutation, "mutation.reservation", restoreMapUUID("72e1b22c-c5a0-5abb-8674-48174fb5db83")),
            .init(.commitTargetMutation, "mutation.target", restoreMapUUID("fdd52f49-3cc4-5c69-9fb4-13d4b226a466")),
            .init(.commitReceiptMutation, "mutation.commitReceipt", restoreMapUUID("c857f65b-5e19-54a3-a672-38d6c4e4100d")),
            .init(.discardReceiptMutation, "mutation.discardReceipt", restoreMapUUID("73b9614d-70ec-59ec-b5b4-5a5fd2d75882")),
            .init(.beginRecordMutation, "mutation.beginRecord", restoreMapUUID("994d01d7-7a55-5a11-8677-5c981aa1f82f")),
            .init(.beginTimeZoneMutation, "mutation.beginTimeZone", restoreMapUUID("df170095-9d76-5672-8297-fb67140d7513")),
        ]
        XCTAssertEqual(vectors.count, 29)
        XCTAssertEqual(CheckRunnerRestoreIdentityKindV1.allCases.map(\.rawValue), [
            "roundSession", "roundItem", "roundLaunchPlan", "site", "asset", "issue",
            "parentRecord", "workflowRecord", "evidenceFile", "parentDraft", "childDraft",
            "stage", "draftCommitPlan", "saga", "reservation", "commitReceipt",
            "discardReceipt", "scratchLease", "processingJob", "planMutation",
            "checkpointMutation", "stageMutation", "sagaMutation", "reservationMutation",
            "commitTargetMutation", "commitReceiptMutation", "discardReceiptMutation",
            "beginRecordMutation", "beginTimeZoneMutation",
        ])

        let identity = try restoreMapIdentity(
            mode: .fork,
            sourceWorkspaceID: restoreMapID(1),
            destinationWorkspaceID: destinationWorkspaceID
        )
        let sources = try vectors.map {
            try CheckRunnerRestoreIdentitySourceV1(kind: $0.kind, sourceID: sourceID)
        }
        let map = try XCTUnwrap(CheckRunnerRestoreIdentityMapV1.make(
            identity: identity,
            sources: Array(sources.reversed())
        ))
        XCTAssertEqual(map.pairs.count, 29)

        let otherDestination = restoreMapUUID("20000000-0000-4000-8000-000000000003")
        for vector in vectors {
            XCTAssertEqual(vector.kind.operationalNamespace, vector.namespace, vector.kind.rawValue)
            XCTAssertEqual(
                try map.destinationID(for: sourceID, kind: vector.kind),
                vector.expectedDestinationID,
                vector.kind.rawValue
            )
            if let namespace = vector.namespace {
                XCTAssertEqual(
                    identity.destinationFieldDraftID(for: sourceID, namespace: namespace),
                    vector.expectedDestinationID,
                    vector.kind.rawValue
                )
                XCTAssertEqual(
                    RestoreIdentityV1.destinationFieldDraftID(
                        for: sourceID,
                        namespace: namespace,
                        mode: .fork,
                        destinationWorkspaceID: destinationWorkspaceID
                    ),
                    vector.expectedDestinationID,
                    vector.kind.rawValue
                )
                XCTAssertNotEqual(
                    RestoreIdentityV1.destinationFieldDraftID(
                        for: sourceID,
                        namespace: namespace,
                        mode: .fork,
                        destinationWorkspaceID: otherDestination
                    ),
                    vector.expectedDestinationID,
                    vector.kind.rawValue
                )
            } else {
                XCTAssertEqual(identity.destinationRecordID(for: sourceID), sourceID)
                XCTAssertEqual(RestoreIdentityV1.destinationRecordID(for: sourceID), sourceID)
            }
        }
    }

    func testActualRestoreDecisionModesProduceOnlyTheAuthorizedIdentityDisposition() throws {
        let sourceWorkspaceID = restoreMapID(100)
        let destinationWorkspaceID = restoreMapID(101)
        let sources = try [
            CheckRunnerRestoreIdentitySourceV1(kind: .workflowRecord, sourceID: restoreMapID(110)),
            CheckRunnerRestoreIdentitySourceV1(kind: .parentDraft, sourceID: restoreMapID(111)),
            CheckRunnerRestoreIdentitySourceV1(kind: .beginRecordMutation, sourceID: restoreMapID(112)),
        ]
        let empty = try restoreMapIdentity(
            mode: .emptyInstall,
            sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: sourceWorkspaceID
        )
        let sameReplace = try restoreMapIdentity(
            mode: .replaceExisting,
            sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: sourceWorkspaceID
        )
        let crossReplace = try restoreMapIdentity(
            mode: .replaceExisting,
            sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: destinationWorkspaceID
        )
        let fork = try restoreMapIdentity(
            mode: .fork,
            sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: destinationWorkspaceID
        )
        let clone = try restoreMapIdentity(
            mode: .clone,
            sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: destinationWorkspaceID
        )

        let emptyMap = try XCTUnwrap(CheckRunnerRestoreIdentityMapV1.make(
            identity: empty, sources: sources
        ))
        let sameMap = try XCTUnwrap(CheckRunnerRestoreIdentityMapV1.make(
            identity: sameReplace, sources: sources
        ))
        let crossMap = try XCTUnwrap(CheckRunnerRestoreIdentityMapV1.make(
            identity: crossReplace, sources: sources
        ))
        let forkMap = try XCTUnwrap(CheckRunnerRestoreIdentityMapV1.make(
            identity: fork, sources: sources
        ))

        XCTAssertEqual(emptyMap.mode, .sameWorkspace)
        XCTAssertEqual(sameMap.mode, .sameWorkspace)
        XCTAssertEqual(crossMap.mode, .crossWorkspaceReplace)
        XCTAssertEqual(forkMap.mode, .fork)
        XCTAssertEqual(emptyMap.sourceWorkspaceID, sourceWorkspaceID)
        XCTAssertEqual(emptyMap.destinationWorkspaceID, sourceWorkspaceID)
        XCTAssertEqual(crossMap.destinationWorkspaceID, destinationWorkspaceID)
        for source in sources {
            XCTAssertEqual(
                try emptyMap.destinationID(for: source.sourceID, kind: source.kind),
                source.sourceID
            )
            XCTAssertEqual(
                try sameMap.destinationID(for: source.sourceID, kind: source.kind),
                source.sourceID
            )
            XCTAssertEqual(
                try crossMap.destinationID(for: source.sourceID, kind: source.kind),
                source.sourceID
            )
            let forkDestination = try forkMap.destinationID(
                for: source.sourceID,
                kind: source.kind
            )
            if source.kind.operationalNamespace == nil {
                XCTAssertEqual(forkDestination, source.sourceID)
            } else {
                XCTAssertNotEqual(forkDestination, source.sourceID)
            }
        }
        XCTAssertNil(try CheckRunnerRestoreIdentityMapV1.make(identity: clone, sources: sources))

        for identity in [empty, sameReplace, crossReplace, fork] {
            let map = try XCTUnwrap(CheckRunnerRestoreIdentityMapV1.make(
                identity: identity, sources: []
            ))
            XCTAssertTrue(map.pairs.isEmpty)
            try map.validate(requiredSources: [])
        }
        XCTAssertNil(try CheckRunnerRestoreIdentityMapV1.make(identity: clone, sources: []))
    }

    func testCanonicalSortingDigestRoundTripCoverageAndBidirectionalLookup() throws {
        let identity = try restoreMapIdentity(
            mode: .fork,
            sourceWorkspaceID: restoreMapID(200),
            destinationWorkspaceID: restoreMapID(201)
        )
        let sources = try [
            CheckRunnerRestoreIdentitySourceV1(kind: .stage, sourceID: restoreMapID(213)),
            CheckRunnerRestoreIdentitySourceV1(kind: .asset, sourceID: restoreMapID(211)),
            CheckRunnerRestoreIdentitySourceV1(kind: .stage, sourceID: restoreMapID(212)),
            CheckRunnerRestoreIdentitySourceV1(kind: .beginTimeZoneMutation, sourceID: restoreMapID(214)),
        ]
        let map = try XCTUnwrap(CheckRunnerRestoreIdentityMapV1.make(
            identity: identity, sources: sources
        ))
        let expectedOrder = map.pairs.sorted(by: restorePairPrecedes)
        XCTAssertEqual(map.pairs, expectedOrder)
        try map.validate()
        try map.validate(requiredSources: Array(sources.reversed()))

        let bytes = try FieldDraftCanonicalCodecV1.encode(map)
        let decoded = try FieldDraftCanonicalCodecV1.decode(
            CheckRunnerRestoreIdentityMapV1.self,
            from: bytes
        )
        XCTAssertEqual(decoded, map)
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), bytes)
        let independentlyRehashed = try restoreMapRehash(restoreMapJSONObject(bytes))
        XCTAssertEqual(independentlyRehashed["mapSHA256"] as? String, map.mapSHA256)

        let rebuilt = try CheckRunnerRestoreIdentityMapV1(
            mode: .fork,
            sourceWorkspaceID: map.sourceWorkspaceID,
            destinationWorkspaceID: map.destinationWorkspaceID,
            pairs: Array(map.pairs.reversed())
        )
        XCTAssertEqual(rebuilt, map)
        XCTAssertEqual(rebuilt.mapSHA256, map.mapSHA256)
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(rebuilt), bytes)

        for pair in map.pairs {
            XCTAssertEqual(
                try map.destinationID(for: pair.sourceID, kind: pair.kind),
                pair.destinationID
            )
            XCTAssertEqual(
                try map.sourceID(for: pair.destinationID, kind: pair.kind),
                pair.sourceID
            )
        }
    }

    func testConstructorsDeclaredCoverageAndLookupMissesFailClosed() throws {
        let zero = restoreMapUUID("00000000-0000-0000-0000-000000000000")
        XCTAssertThrowsError(try CheckRunnerRestoreIdentitySourceV1(kind: .asset, sourceID: zero)) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .invalidIdentity)
        }
        XCTAssertThrowsError(try CheckRunnerRestoreIdentityPairV1(
            kind: .asset,
            sourceID: restoreMapID(301),
            destinationID: zero
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .invalidIdentity)
        }

        let sourceWorkspaceID = restoreMapID(302)
        let destinationWorkspaceID = restoreMapID(303)
        let identity = try restoreMapIdentity(
            mode: .fork,
            sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: destinationWorkspaceID
        )
        let sources = try [
            CheckRunnerRestoreIdentitySourceV1(kind: .asset, sourceID: restoreMapID(304)),
            CheckRunnerRestoreIdentitySourceV1(kind: .parentDraft, sourceID: restoreMapID(305)),
        ]
        let map = try XCTUnwrap(CheckRunnerRestoreIdentityMapV1.make(
            identity: identity,
            sources: sources
        ))
        try map.validate(requiredSources: sources)

        XCTAssertThrowsError(try CheckRunnerRestoreIdentityMapV1.make(
            identity: identity,
            sources: [sources[0], sources[0]]
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .duplicateIdentity)
        }
        XCTAssertThrowsError(try map.validate(requiredSources: [sources[0]])) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .declaredCoverageMismatch)
        }
        let extra = try CheckRunnerRestoreIdentitySourceV1(
            kind: .issue,
            sourceID: restoreMapID(306)
        )
        XCTAssertThrowsError(try map.validate(requiredSources: sources + [extra])) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .declaredCoverageMismatch)
        }
        XCTAssertThrowsError(try map.validate(requiredSources: [sources[0], sources[0]])) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .duplicateIdentity)
        }

        XCTAssertThrowsError(try map.destinationID(for: restoreMapID(399), kind: .asset)) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .missingIdentity)
        }
        XCTAssertThrowsError(try map.destinationID(for: zero, kind: .asset)) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .invalidIdentity)
        }
        XCTAssertThrowsError(try map.sourceID(for: restoreMapID(398), kind: .asset)) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .missingIdentity)
        }
        XCTAssertThrowsError(try map.sourceID(for: zero, kind: .asset)) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .invalidIdentity)
        }
        let assetPair = try XCTUnwrap(map.pairs.first { $0.kind == .asset })
        XCTAssertThrowsError(try map.sourceID(
            for: assetPair.destinationID,
            kind: .site
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .missingIdentity)
        }

        let wrongMapped = try CheckRunnerRestoreIdentityPairV1(
            kind: .parentDraft,
            sourceID: sources[1].sourceID,
            destinationID: sources[1].sourceID
        )
        XCTAssertThrowsError(try CheckRunnerRestoreIdentityMapV1(
            mode: .fork,
            sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: destinationWorkspaceID,
            pairs: [wrongMapped]
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .identityMismatch)
        }

        let duplicateSource = try CheckRunnerRestoreIdentityPairV1(
            kind: .asset,
            sourceID: sources[0].sourceID,
            destinationID: sources[0].sourceID
        )
        XCTAssertThrowsError(try CheckRunnerRestoreIdentityMapV1(
            mode: .fork,
            sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: destinationWorkspaceID,
            pairs: [duplicateSource, duplicateSource]
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .duplicateIdentity)
        }

        for invalid in [
            (CheckRunnerRestoreModeV1.sameWorkspace, sourceWorkspaceID, destinationWorkspaceID),
            (.crossWorkspaceReplace, sourceWorkspaceID, sourceWorkspaceID),
            (.fork, sourceWorkspaceID, sourceWorkspaceID),
        ] {
            XCTAssertThrowsError(try CheckRunnerRestoreIdentityMapV1(
                mode: invalid.0,
                sourceWorkspaceID: invalid.1,
                destinationWorkspaceID: invalid.2,
                pairs: []
            )) { error in
                XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .invalidMode)
            }
        }

        let clone = try restoreMapIdentity(
            mode: .clone,
            sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: destinationWorkspaceID
        )
        XCTAssertThrowsError(try CheckRunnerRestoreIdentityMapV1.make(
            identity: clone,
            sources: [sources[0], sources[0]]
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .duplicateIdentity)
        }
        let sameWorkspaceClone = restoreMapUncheckedIdentity(
            mode: .clone,
            sourceWorkspaceID: sourceWorkspaceID,
            destinationWorkspaceID: sourceWorkspaceID
        )
        XCTAssertThrowsError(try CheckRunnerRestoreIdentityMapV1.make(
            identity: sameWorkspaceClone,
            sources: []
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .invalidMode)
        }
        let zeroWorkspaceClone = restoreMapUncheckedIdentity(
            mode: .clone,
            sourceWorkspaceID: zero,
            destinationWorkspaceID: destinationWorkspaceID
        )
        XCTAssertThrowsError(try CheckRunnerRestoreIdentityMapV1.make(
            identity: zeroWorkspaceClone,
            sources: []
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .invalidIdentity)
        }
    }

    func testClosedCanonicalDecodingRejectsMalformedKeysAndRehashedSemanticAttacks() throws {
        let identity = try restoreMapIdentity(
            mode: .fork,
            sourceWorkspaceID: restoreMapID(400),
            destinationWorkspaceID: restoreMapID(401)
        )
        let sources = try [
            CheckRunnerRestoreIdentitySourceV1(kind: .asset, sourceID: restoreMapID(410)),
            CheckRunnerRestoreIdentitySourceV1(kind: .parentDraft, sourceID: restoreMapID(411)),
            CheckRunnerRestoreIdentitySourceV1(kind: .stage, sourceID: restoreMapID(412)),
        ]
        let map = try XCTUnwrap(CheckRunnerRestoreIdentityMapV1.make(
            identity: identity,
            sources: sources
        ))

        let sourceBytes = try FieldDraftCanonicalCodecV1.encode(sources[0])
        XCTAssertEqual(
            try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerRestoreIdentitySourceV1.self,
                from: sourceBytes
            ),
            sources[0]
        )
        var sourceUnknown = try restoreMapJSONObject(sourceBytes)
        sourceUnknown["futureSourceAuthority"] = true
        assertRestoreMapDecodeFails(CheckRunnerRestoreIdentitySourceV1.self, sourceUnknown)
        var sourceMissing = try restoreMapJSONObject(sourceBytes)
        sourceMissing.removeValue(forKey: "kind")
        assertRestoreMapDecodeFails(CheckRunnerRestoreIdentitySourceV1.self, sourceMissing)

        let pair = try XCTUnwrap(map.pairs.first)
        let pairBytes = try FieldDraftCanonicalCodecV1.encode(pair)
        XCTAssertEqual(
            try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerRestoreIdentityPairV1.self,
                from: pairBytes
            ),
            pair
        )
        var pairUnknown = try restoreMapJSONObject(pairBytes)
        pairUnknown["futurePairAuthority"] = true
        assertRestoreMapDecodeFails(CheckRunnerRestoreIdentityPairV1.self, pairUnknown)
        var pairMissing = try restoreMapJSONObject(pairBytes)
        pairMissing.removeValue(forKey: "destinationID")
        assertRestoreMapDecodeFails(CheckRunnerRestoreIdentityPairV1.self, pairMissing)

        let mapBytes = try FieldDraftCanonicalCodecV1.encode(map)
        XCTAssertEqual(
            try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerRestoreIdentityMapV1.self,
                from: mapBytes
            ),
            map
        )
        let canonical = try restoreMapJSONObject(mapBytes)
        var unknownMap = canonical
        unknownMap["futureMapAuthority"] = true
        assertRestoreMapDecodeFails(CheckRunnerRestoreIdentityMapV1.self, unknownMap)
        var missingMap = canonical
        missingMap.removeValue(forKey: "mapSHA256")
        assertRestoreMapDecodeFails(CheckRunnerRestoreIdentityMapV1.self, missingMap)
        var unknownPair = canonical
        var unknownPairs = try XCTUnwrap(unknownPair["pairs"] as? [[String: Any]])
        unknownPairs[0]["futurePairAuthority"] = true
        unknownPair["pairs"] = unknownPairs
        assertRestoreMapDecodeFails(CheckRunnerRestoreIdentityMapV1.self, unknownPair)
        var missingPair = canonical
        var missingPairs = try XCTUnwrap(missingPair["pairs"] as? [[String: Any]])
        missingPairs[0].removeValue(forKey: "sourceID")
        missingPair["pairs"] = missingPairs
        assertRestoreMapDecodeFails(CheckRunnerRestoreIdentityMapV1.self, missingPair)
        var unknownMode = canonical
        unknownMode["mode"] = "futureMode"
        assertRestoreMapDecodeFails(CheckRunnerRestoreIdentityMapV1.self, unknownMode)
        var unknownKind = canonical
        var unknownKindPairs = try XCTUnwrap(unknownKind["pairs"] as? [[String: Any]])
        unknownKindPairs[0]["kind"] = "futureKind"
        unknownKind["pairs"] = unknownKindPairs
        assertRestoreMapDecodeFails(CheckRunnerRestoreIdentityMapV1.self, unknownKind)

        var semanticAttacks: [(
            String,
            [String: Any],
            CheckRunnerRestoreCorrespondenceFailureV1
        )] = []
        var wrongMapping = canonical
        var wrongMappingPairs = try XCTUnwrap(wrongMapping["pairs"] as? [[String: Any]])
        wrongMappingPairs[0]["destinationID"] = restoreMapID(490).uuidString
        wrongMapping["pairs"] = wrongMappingPairs
        semanticAttacks.append((
            "wrong-mapping",
            try restoreMapRehash(wrongMapping),
            .identityMismatch
        ))

        var noncanonicalOrder = canonical
        let reversedPairs = try XCTUnwrap(noncanonicalOrder["pairs"] as? [[String: Any]]).reversed()
        noncanonicalOrder["pairs"] = Array(reversedPairs)
        semanticAttacks.append((
            "noncanonical-order",
            try restoreMapRehash(noncanonicalOrder),
            .noncanonicalPairs
        ))

        var duplicateSource = canonical
        var duplicateSourcePairs = try XCTUnwrap(duplicateSource["pairs"] as? [[String: Any]])
        duplicateSourcePairs.append(duplicateSourcePairs[0])
        duplicateSource["pairs"] = restoreMapSortPairObjects(duplicateSourcePairs)
        semanticAttacks.append((
            "duplicate-source",
            try restoreMapRehash(duplicateSource),
            .duplicateIdentity
        ))

        var duplicateDestination = canonical
        var duplicateDestinationPairs = try XCTUnwrap(
            duplicateDestination["pairs"] as? [[String: Any]]
        )
        var destinationCollision = duplicateDestinationPairs[0]
        destinationCollision["sourceID"] = restoreMapID(491).uuidString
        duplicateDestinationPairs.append(destinationCollision)
        duplicateDestination["pairs"] = restoreMapSortPairObjects(duplicateDestinationPairs)
        semanticAttacks.append((
            "duplicate-destination",
            try restoreMapRehash(duplicateDestination),
            .duplicateIdentity
        ))

        var zeroPair = canonical
        var zeroPairs = try XCTUnwrap(zeroPair["pairs"] as? [[String: Any]])
        zeroPairs[0]["sourceID"] = "00000000-0000-0000-0000-000000000000"
        zeroPair["pairs"] = zeroPairs
        semanticAttacks.append((
            "zero-pair",
            try restoreMapRehash(zeroPair),
            .invalidIdentity
        ))

        var zeroWorkspace = canonical
        zeroWorkspace["destinationWorkspaceID"] = "00000000-0000-0000-0000-000000000000"
        semanticAttacks.append((
            "zero-workspace",
            try restoreMapRehash(zeroWorkspace),
            .invalidIdentity
        ))

        var wrongModeWorkspace = canonical
        wrongModeWorkspace["mode"] = "sameWorkspace"
        semanticAttacks.append((
            "wrong-mode-workspace",
            try restoreMapRehash(wrongModeWorkspace),
            .invalidMode
        ))

        var equalForkWorkspaces = canonical
        equalForkWorkspaces["destinationWorkspaceID"] = canonical["sourceWorkspaceID"]
        semanticAttacks.append((
            "equal-fork-workspaces",
            try restoreMapRehash(equalForkWorkspaces),
            .invalidMode
        ))

        var unsupportedSchema = canonical
        unsupportedSchema["schemaVersion"] = 2
        semanticAttacks.append((
            "unsupported-schema",
            try restoreMapRehash(unsupportedSchema),
            .unsupportedSchema
        ))

        for (label, hostile, expected) in semanticAttacks {
            XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerRestoreIdentityMapV1.self,
                from: restoreMapJSONData(hostile)
            ), label) { error in
                XCTAssertEqual(
                    error as? CheckRunnerRestoreCorrespondenceFailureV1,
                    expected,
                    label
                )
            }
        }

        var wrongDigest = canonical
        wrongDigest["mapSHA256"] = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(
            CheckRunnerRestoreIdentityMapV1.self,
            from: restoreMapJSONData(wrongDigest)
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreCorrespondenceFailureV1, .digestMismatch)
        }
    }
}

private struct RestoreIdentityVector {
    let kind: CheckRunnerRestoreIdentityKindV1
    let namespace: String?
    let expectedDestinationID: UUID

    init(
        _ kind: CheckRunnerRestoreIdentityKindV1,
        _ namespace: String?,
        _ expectedDestinationID: UUID
    ) {
        self.kind = kind
        self.namespace = namespace
        self.expectedDestinationID = expectedDestinationID
    }
}

private struct RestoreMapDigestPair: Encodable {
    let kind: CheckRunnerRestoreIdentityKindV1
    let sourceID: UUID
    let destinationID: UUID
}

private struct RestoreMapDigestBody: Encodable {
    let schemaVersion: Int
    let mode: CheckRunnerRestoreModeV1
    let sourceWorkspaceID: UUID
    let destinationWorkspaceID: UUID
    let pairs: [RestoreMapDigestPair]
}

private func restoreMapRehash(_ object: [String: Any]) throws -> [String: Any] {
    var result = object
    let schemaVersion = try XCTUnwrap(object["schemaVersion"] as? Int)
    let mode = try XCTUnwrap(CheckRunnerRestoreModeV1(
        rawValue: try XCTUnwrap(object["mode"] as? String)
    ))
    let sourceWorkspaceID = try XCTUnwrap(UUID(
        uuidString: try XCTUnwrap(object["sourceWorkspaceID"] as? String)
    ))
    let destinationWorkspaceID = try XCTUnwrap(UUID(
        uuidString: try XCTUnwrap(object["destinationWorkspaceID"] as? String)
    ))
    let objects = try XCTUnwrap(object["pairs"] as? [[String: Any]])
    let pairs = try objects.map { pair in
        RestoreMapDigestPair(
            kind: try XCTUnwrap(CheckRunnerRestoreIdentityKindV1(
                rawValue: try XCTUnwrap(pair["kind"] as? String)
            )),
            sourceID: try XCTUnwrap(UUID(
                uuidString: try XCTUnwrap(pair["sourceID"] as? String)
            )),
            destinationID: try XCTUnwrap(UUID(
                uuidString: try XCTUnwrap(pair["destinationID"] as? String)
            ))
        )
    }
    result["mapSHA256"] = try FieldDraftCanonicalCodecV1.sha256(RestoreMapDigestBody(
        schemaVersion: schemaVersion,
        mode: mode,
        sourceWorkspaceID: sourceWorkspaceID,
        destinationWorkspaceID: destinationWorkspaceID,
        pairs: pairs
    ))
    return result
}

private func restoreMapSortPairObjects(
    _ pairs: [[String: Any]]
) -> [[String: Any]] {
    pairs.sorted {
        let left = [
            $0["kind"] as? String ?? "",
            ($0["sourceID"] as? String ?? "").lowercased(),
            ($0["destinationID"] as? String ?? "").lowercased(),
        ]
        let right = [
            $1["kind"] as? String ?? "",
            ($1["sourceID"] as? String ?? "").lowercased(),
            ($1["destinationID"] as? String ?? "").lowercased(),
        ]
        return left.lexicographicallyPrecedes(right)
    }
}

private func restoreMapIdentity(
    mode: BackupRestoreMode,
    sourceWorkspaceID: UUID,
    destinationWorkspaceID: UUID
) throws -> RestoreIdentityV1 {
    let oldWorkspaceID: UUID
    switch mode {
    case .replaceExisting:
        oldWorkspaceID = destinationWorkspaceID
    case .emptyInstall, .clone, .fork:
        oldWorkspaceID = restoreMapID(8_001)
    }
    let sourceReplicaID = restoreMapID(8_002)
    let oldPointer = RestorePointerIdentityV1(
        generationID: restoreMapID(8_003),
        generationManifestSHA256: String(repeating: "a", count: 64),
        workspaceID: oldWorkspaceID,
        replicaID: restoreMapID(8_004)
    )
    return try RestoreIdentityDecisionV1.decide(.init(
        mode: mode,
        source: .init(workspaceID: sourceWorkspaceID, replicaID: sourceReplicaID),
        oldPointer: oldPointer,
        targetGenerationID: restoreMapID(8_005),
        targetGenerationManifestSHA256: String(repeating: "b", count: 64),
        allocatedWorkspaceID: mode == .clone || mode == .fork
            ? destinationWorkspaceID
            : nil,
        allocatedReplicaID: restoreMapID(8_006)
    ))
}

private func restoreMapUncheckedIdentity(
    mode: BackupRestoreMode,
    sourceWorkspaceID: UUID,
    destinationWorkspaceID: UUID
) -> RestoreIdentityV1 {
    let pointer = RestorePointerIdentityV1(
        generationID: restoreMapID(8_101),
        generationManifestSHA256: String(repeating: "c", count: 64),
        workspaceID: destinationWorkspaceID,
        replicaID: restoreMapID(8_102)
    )
    return RestoreIdentityV1(
        mode: mode,
        source: .init(workspaceID: sourceWorkspaceID, replicaID: restoreMapID(8_103)),
        oldPointer: pointer,
        targetPointer: pointer,
        recordIdentityDisposition: .preserve
    )
}

private func restorePairPrecedes(
    _ lhs: CheckRunnerRestoreIdentityPairV1,
    _ rhs: CheckRunnerRestoreIdentityPairV1
) -> Bool {
    if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
    if lhs.sourceID != rhs.sourceID {
        return lhs.sourceID.uuidString.lowercased() < rhs.sourceID.uuidString.lowercased()
    }
    return lhs.destinationID.uuidString.lowercased()
        < rhs.destinationID.uuidString.lowercased()
}

private func restoreMapJSONObject(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func restoreMapJSONData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func assertRestoreMapDecodeFails<Value: Codable>(
    _ type: Value.Type,
    _ object: [String: Any],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(
        try FieldDraftCanonicalCodecV1.decode(
            type,
            from: restoreMapJSONData(object)
        ),
        file: file,
        line: line
    )
}

private func restoreMapID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", value))!
}

private func restoreMapUUID(_ value: String) -> UUID {
    UUID(uuidString: value)!
}
