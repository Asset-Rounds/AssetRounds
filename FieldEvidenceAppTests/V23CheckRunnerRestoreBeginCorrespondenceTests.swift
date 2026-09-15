import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V23CheckRunnerRestoreBeginCorrespondenceTests: XCTestCase {
    func testDependencyStateSeparatesPresenceFromZeroAndMaximumRevision() throws {
        let digest = String(repeating: "a", count: 64)
        let values: [CheckRunnerDependencyStateV1] = [
            .absent(revision: 0),
            .absent(revision: 41),
            .absent(revision: .max),
            .present(revision: 0, semanticSHA256: digest),
            .present(revision: 41, semanticSHA256: digest),
            .present(revision: .max, semanticSHA256: digest),
        ]

        for value in values {
            try value.validate()
            let bytes = try FieldDraftCanonicalCodecV1.encode(value)
            XCTAssertEqual(
                try FieldDraftCanonicalCodecV1.decode(CheckRunnerDependencyStateV1.self, from: bytes),
                value
            )
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(
                FieldDraftCanonicalCodecV1.decode(CheckRunnerDependencyStateV1.self, from: bytes)
            ), bytes)
        }

        XCTAssertEqual(try restoreBeginObject(values[0]).keys.sorted(), ["revision", "state"])
        XCTAssertEqual(
            try restoreBeginObject(values[3]).keys.sorted(),
            ["revision", "semanticSHA256", "state"]
        )
    }

    func testDependencyStateRejectsInvalidDigestAndHostileClosedShapes() throws {
        let invalid = CheckRunnerDependencyStateV1.present(
            revision: 1,
            semanticSHA256: String(repeating: "A", count: 64)
        )
        XCTAssertThrowsError(try invalid.validate()) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidDependency)
        }
        XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.encode(invalid)) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidDependency)
        }

        let hostile: [[String: Any]] = [
            ["state": "UNKNOWN", "revision": 0],
            ["state": "absent", "revision": 0],
            ["state": "ABSENT"],
            ["state": "ABSENT", "revision": 0, "semanticSHA256": String(repeating: "a", count: 64)],
            ["state": "ABSENT", "revision": 0, "future": true],
            ["state": "PRESENT", "revision": 0],
            ["state": "PRESENT", "revision": 0, "semanticSHA256": String(repeating: "g", count: 64)],
            ["state": "PRESENT", "revision": -1, "semanticSHA256": String(repeating: "a", count: 64)],
        ]
        for object in hostile {
            assertRestoreBeginDecodeFails(CheckRunnerDependencyStateV1.self, object)
        }
    }

    func testDestinationDependencyRetainsIndependentStatesAndValidatesMappingRoles() throws {
        let sourceID = restoreBeginID(101)
        // Operational record identities are preserved even when field-draft
        // identities fork into the destination workspace.
        let destinationID = sourceID
        let sourceIdentity = try WorkspaceEntityIdentityV1(kind: .asset, id: sourceID)
        let destinationIdentity = try WorkspaceEntityIdentityV1(kind: .asset, id: destinationID)
        let dependency = try CheckRunnerDestinationDependencyV1(
            sourceIdentity: sourceIdentity,
            sourceState: .present(revision: .max, semanticSHA256: String(repeating: "b", count: 64)),
            destinationIdentity: destinationIdentity,
            destinationStateAtMapping: .absent(revision: 0)
        )
        XCTAssertEqual(dependency.sourceState.revision, .max)
        XCTAssertEqual(dependency.destinationStateAtMapping.revision, 0)

        let map = try CheckRunnerRestoreIdentityMapV1(
            mode: .fork,
            sourceWorkspaceID: restoreBeginID(103),
            destinationWorkspaceID: restoreBeginID(104),
            pairs: [try CheckRunnerRestoreIdentityPairV1(
                kind: .asset,
                sourceID: sourceID,
                destinationID: destinationID
            )]
        )
        try dependency.validate(map: map, kind: .asset)
        let bytes = try FieldDraftCanonicalCodecV1.encode(dependency)
        XCTAssertEqual(
            try FieldDraftCanonicalCodecV1.decode(CheckRunnerDestinationDependencyV1.self, from: bytes),
            dependency
        )

        XCTAssertThrowsError(try dependency.validate(map: map, kind: .site)) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidDependency)
        }
        XCTAssertThrowsError(try dependency.validate(map: map, kind: .roundSession)) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidDependency)
        }
        let wrongDestination = try CheckRunnerDestinationDependencyV1(
            sourceIdentity: sourceIdentity,
            sourceState: .absent(revision: 9),
            destinationIdentity: try WorkspaceEntityIdentityV1(kind: .asset, id: restoreBeginID(105)),
            destinationStateAtMapping: .present(
                revision: 17,
                semanticSHA256: String(repeating: "c", count: 64)
            )
        )
        XCTAssertThrowsError(try wrongDestination.validate(map: map, kind: .asset)) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidDependency)
        }

        for role in [CheckRunnerRestoreIdentityKindV1.parentRecord, .workflowRecord] {
            let recordID = restoreBeginID(role == .parentRecord ? 106 : 107)
            let recordIdentity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: recordID)
            let recordDependency = try CheckRunnerDestinationDependencyV1(
                sourceIdentity: recordIdentity,
                sourceState: .absent(revision: 0),
                destinationIdentity: recordIdentity,
                destinationStateAtMapping: .present(
                    revision: .max,
                    semanticSHA256: String(repeating: "d", count: 64)
                )
            )
            let recordMap = try CheckRunnerRestoreIdentityMapV1(
                mode: .sameWorkspace,
                sourceWorkspaceID: restoreBeginID(108),
                destinationWorkspaceID: restoreBeginID(108),
                pairs: [try CheckRunnerRestoreIdentityPairV1(
                    kind: role,
                    sourceID: recordID,
                    destinationID: recordID
                )]
            )
            try recordDependency.validate(map: recordMap, kind: role)
        }

        for (role, entityKind, value) in [
            (CheckRunnerRestoreIdentityKindV1.site, WorkspaceEntityKindV1.site, 109),
            (.issue, .issue, 110),
        ] {
            let recordID = restoreBeginID(value)
            let recordIdentity = try WorkspaceEntityIdentityV1(kind: entityKind, id: recordID)
            let recordDependency = try CheckRunnerDestinationDependencyV1(
                sourceIdentity: recordIdentity,
                sourceState: .present(
                    revision: 0,
                    semanticSHA256: String(repeating: "e", count: 64)
                ),
                destinationIdentity: recordIdentity,
                destinationStateAtMapping: .absent(revision: .max)
            )
            let recordMap = try CheckRunnerRestoreIdentityMapV1(
                mode: .sameWorkspace,
                sourceWorkspaceID: restoreBeginID(111),
                destinationWorkspaceID: restoreBeginID(111),
                pairs: [try CheckRunnerRestoreIdentityPairV1(
                    kind: role,
                    sourceID: recordID,
                    destinationID: recordID
                )]
            )
            try recordDependency.validate(map: recordMap, kind: role)
        }
    }

    func testDestinationDependencyRejectsKindsNestedIdentityCorruptionAndUnknownKeys() throws {
        XCTAssertThrowsError(try CheckRunnerDestinationDependencyV1(
            sourceIdentity: WorkspaceEntityIdentityV1(kind: .site, id: restoreBeginID(201)),
            sourceState: .absent(revision: 0),
            destinationIdentity: WorkspaceEntityIdentityV1(kind: .asset, id: restoreBeginID(202)),
            destinationStateAtMapping: .absent(revision: 0)
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidDependency)
        }
        let packet = try WorkspaceEntityIdentityV1(kind: .packet, id: restoreBeginID(203))
        XCTAssertThrowsError(try CheckRunnerDestinationDependencyV1(
            sourceIdentity: packet,
            sourceState: .absent(revision: 0),
            destinationIdentity: packet,
            destinationStateAtMapping: .absent(revision: 0)
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidDependency)
        }

        let valid = try CheckRunnerDestinationDependencyV1(
            sourceIdentity: WorkspaceEntityIdentityV1(kind: .site, id: restoreBeginID(204)),
            sourceState: .absent(revision: 3),
            destinationIdentity: WorkspaceEntityIdentityV1(kind: .site, id: restoreBeginID(205)),
            destinationStateAtMapping: .present(
                revision: 4,
                semanticSHA256: String(repeating: "e", count: 64)
            )
        )
        let base = try restoreBeginObject(valid)
        XCTAssertEqual(try restoreBeginJSONData(base), try FieldDraftCanonicalCodecV1.encode(valid))
        var topUnknown = base
        topUnknown["future"] = true
        assertRestoreBeginDecodeFails(CheckRunnerDestinationDependencyV1.self, topUnknown)

        var nestedUnknown = base
        var source = try XCTUnwrap(nestedUnknown["sourceIdentity"] as? [String: Any])
        source["future"] = true
        nestedUnknown["sourceIdentity"] = source
        assertRestoreBeginDecodeFails(CheckRunnerDestinationDependencyV1.self, nestedUnknown)

        var unknownKind = base
        var destination = try XCTUnwrap(unknownKind["destinationIdentity"] as? [String: Any])
        destination["kind"] = "futureEntity"
        unknownKind["destinationIdentity"] = destination
        assertRestoreBeginDecodeFails(CheckRunnerDestinationDependencyV1.self, unknownKind)

        var missingID = base
        var missingSource = try XCTUnwrap(missingID["sourceIdentity"] as? [String: Any])
        missingSource.removeValue(forKey: "id")
        missingID["sourceIdentity"] = missingSource
        assertRestoreBeginDecodeFails(CheckRunnerDestinationDependencyV1.self, missingID)
    }

    func testExpectedSourceEvidenceRoundTripsAuthenticCanonicalHistoryWithoutLosingProvenance() throws {
        let fixture = try restoreBeginFixture(seed: 301)
        let exact = CheckRunnerExpectedSourceBeginEvidenceV1.exact(fixture.evidence)
        try exact.validate(
            sourceWorkspaceID: fixture.workspaceID,
            sourceMutationID: fixture.mutationID
        )
        let bytes = try FieldDraftCanonicalCodecV1.encode(exact)
        let decoded = try FieldDraftCanonicalCodecV1.decode(
            CheckRunnerExpectedSourceBeginEvidenceV1.self,
            from: bytes
        )
        XCTAssertEqual(decoded, exact)
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), bytes)

        guard case let .exact(retained) = decoded else {
            return XCTFail("Expected exact source evidence")
        }
        XCTAssertEqual(try retained.envelope.canonicalData(), try fixture.evidence.envelope.canonicalData())
        XCTAssertEqual(try retained.receipt.canonicalData(), try fixture.evidence.receipt.canonicalData())
        XCTAssertEqual(retained.envelope.generationID, fixture.generationID)
        XCTAssertEqual(retained.envelope.replicaID, fixture.replicaID)
        XCTAssertEqual(retained.envelope.expectedRevision.workspaceRevision, 40)
        XCTAssertEqual(retained.receipt.resultingRevision.workspaceRevision, 41)
        XCTAssertEqual(retained.receipt.identity.localSequence, 77)
        XCTAssertEqual(retained.receipt.committedAt, fixture.committedAt)
        XCTAssertEqual(retained.receipt.expectedRevision.entityRevisions.count, 2)
        XCTAssertEqual(retained.receipt.resultingRevision.entityRevisions.count, 2)

        let absent = CheckRunnerExpectedSourceBeginEvidenceV1.absent
        try absent.validate(
            sourceWorkspaceID: WorkspaceID(rawValue: restoreBeginID(399)),
            sourceMutationID: MutationIDV1(rawValue: restoreBeginID(398))
        )
        XCTAssertEqual(try restoreBeginObject(absent).keys.sorted(), ["state"])
        XCTAssertEqual(
            try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerExpectedSourceBeginEvidenceV1.self,
                from: FieldDraftCanonicalCodecV1.encode(absent)
            ),
            absent
        )
    }

    func testExpectedSourceEvidenceRejectsForeignKeyMalformedMismatchAndNoncanonicalBytes() throws {
        let fixture = try restoreBeginFixture(seed: 401)
        let exact = CheckRunnerExpectedSourceBeginEvidenceV1.exact(fixture.evidence)
        XCTAssertThrowsError(try exact.validate(
            sourceWorkspaceID: WorkspaceID(rawValue: restoreBeginID(402)),
            sourceMutationID: fixture.mutationID
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidEvidence)
        }
        XCTAssertThrowsError(try exact.validate(
            sourceWorkspaceID: fixture.workspaceID,
            sourceMutationID: MutationIDV1(rawValue: fixture.workspaceID.rawValue)
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidEvidence)
        }

        let other = try restoreBeginFixture(seed: 403)
        let base = try restoreBeginObject(exact)
        XCTAssertEqual(try restoreBeginJSONData(base), try FieldDraftCanonicalCodecV1.encode(exact))
        var mismatched = base
        mismatched["receiptCanonicalData"] = try other.evidence.receipt.canonicalData().base64EncodedString()
        assertRestoreBeginDecodeFails(CheckRunnerExpectedSourceBeginEvidenceV1.self, mismatched)

        var noncanonical = base
        var envelopeBytes = try XCTUnwrap(Data(
            base64Encoded: try XCTUnwrap(base["envelopeCanonicalData"] as? String)
        ))
        envelopeBytes.append(0x20)
        noncanonical["envelopeCanonicalData"] = envelopeBytes.base64EncodedString()
        assertRestoreBeginDecodeFails(CheckRunnerExpectedSourceBeginEvidenceV1.self, noncanonical)

        var noncanonicalReceipt = base
        var receiptBytes = try XCTUnwrap(Data(
            base64Encoded: try XCTUnwrap(base["receiptCanonicalData"] as? String)
        ))
        receiptBytes.append(0x20)
        noncanonicalReceipt["receiptCanonicalData"] = receiptBytes.base64EncodedString()
        assertRestoreBeginDecodeFails(CheckRunnerExpectedSourceBeginEvidenceV1.self, noncanonicalReceipt)

        var missingReceipt = base
        missingReceipt.removeValue(forKey: "receiptCanonicalData")
        assertRestoreBeginDecodeFails(CheckRunnerExpectedSourceBeginEvidenceV1.self, missingReceipt)

        var unknown = base
        unknown["future"] = true
        assertRestoreBeginDecodeFails(CheckRunnerExpectedSourceBeginEvidenceV1.self, unknown)

        for malformed in [
            ["state": "exact"],
            ["state": "UNKNOWN"],
            ["state": "ABSENT", "envelopeCanonicalData": "AA=="],
        ] as [[String: Any]] {
            assertRestoreBeginDecodeFails(CheckRunnerExpectedSourceBeginEvidenceV1.self, malformed)
        }
    }

    func testDestinationBindingPreservesSourceBytesAndMapsOnlyOperationalMutationIDs() throws {
        let fixture = try restoreBindingFixture(seed: 1_000, recheck: true, includesTimeZone: true)
        let sourceCommandBytes = try FieldDraftCanonicalCodecV1.encode(fixture.source.recordCommand)

        for mode in [
            CheckRunnerRestoreModeV1.sameWorkspace,
            .crossWorkspaceReplace,
            .fork,
        ] {
            let map = try fixture.map(mode: mode)
            let basis = try fixture.recordBasis(targetPresent: false)
            let binding = try CheckRunnerDestinationBeginBindingV1(
                source: fixture.source,
                map: map,
                recordMappedDependencyBasis: Array(basis.reversed()),
                timeZoneMappedDependencyBasis: [try fixture.siteDependency()]
            )
            try binding.validate(source: fixture.source, map: map)

            XCTAssertEqual(binding.destinationWorkspaceID.rawValue, map.destinationWorkspaceID)
            XCTAssertEqual(
                binding.recordMutationID.rawValue,
                try map.destinationID(for: fixture.recordID, kind: .beginRecordMutation)
            )
            XCTAssertEqual(
                binding.timeZoneMutationID?.rawValue,
                try map.destinationID(for: fixture.timeZoneMutationID, kind: .beginTimeZoneMutation)
            )
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(binding.recordCommand), sourceCommandBytes)
            XCTAssertEqual(binding.recordCommittedAt, fixture.source.recordCommittedAt)
            XCTAssertEqual(binding.timeZoneCommand, fixture.source.timeZone?.command)
            XCTAssertEqual(binding.timeZoneCommittedAt, fixture.source.timeZone?.committedAt)
            XCTAssertEqual(fixture.source.recordMutationID.rawValue, fixture.source.recordCommand.recordID)
            XCTAssertTrue(binding.recordMappedDependencyBasis.allSatisfy {
                $0.sourceIdentity == $0.destinationIdentity
            })
            if let boundZone = binding.timeZoneCommand,
               let sourceZone = fixture.source.timeZone?.command {
                XCTAssertEqual(
                    try FieldDraftCanonicalCodecV1.encode(boundZone),
                    try FieldDraftCanonicalCodecV1.encode(sourceZone)
                )
            } else {
                XCTFail("Expected retained time-zone commands")
            }

            if mode == .fork {
                XCTAssertNotEqual(binding.recordMutationID.rawValue, fixture.source.recordMutationID.rawValue)
                XCTAssertNotEqual(binding.timeZoneMutationID, fixture.source.timeZone?.mutationID)
            } else {
                XCTAssertEqual(binding.recordMutationID, fixture.source.recordMutationID)
                XCTAssertEqual(binding.timeZoneMutationID, fixture.source.timeZone?.mutationID)
            }

            let bytes = try FieldDraftCanonicalCodecV1.encode(binding)
            let decoded = try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerDestinationBeginBindingV1.self,
                from: bytes
            )
            XCTAssertEqual(decoded, binding)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), bytes)
            XCTAssertEqual(try decoded.canonicalSHA256(), try binding.canonicalSHA256())
            try decoded.validate(source: fixture.source, map: map)
        }
    }

    func testDestinationBindingRequiresExactDependencyCardinalityAndPresentReferents() throws {
        let recheck = try restoreBindingFixture(seed: 1_100, recheck: true, includesTimeZone: true)
        let map = try recheck.map(mode: .fork)
        let absentTarget = try CheckRunnerDestinationBeginBindingV1(
            source: recheck.source,
            map: map,
            recordMappedDependencyBasis: try recheck.recordBasis(targetPresent: false),
            timeZoneMappedDependencyBasis: [try recheck.siteDependency()]
        )
        let presentTarget = try CheckRunnerDestinationBeginBindingV1(
            source: recheck.source,
            map: map,
            recordMappedDependencyBasis: try recheck.recordBasis(targetPresent: true),
            timeZoneMappedDependencyBasis: [try recheck.siteDependency()]
        )
        XCTAssertEqual(absentTarget.recordMappedDependencyBasis.count, 5)
        XCTAssertEqual(presentTarget.recordMappedDependencyBasis.count, 5)
        let target = try XCTUnwrap(presentTarget.recordMappedDependencyBasis.first {
            $0.sourceIdentity.kind == .workflowRecord && $0.sourceIdentity.id == recheck.recordID
        })
        guard case .present(revision: 0, semanticSHA256: _) = target.sourceState,
              case .present(revision: .max, semanticSHA256: _) = target.destinationStateAtMapping else {
            return XCTFail("Expected present target observations at zero and maximum revision")
        }
        for dependency in presentTarget.recordMappedDependencyBasis where
            dependency.sourceIdentity != target.sourceIdentity {
            guard case .present = dependency.sourceState,
                  case .present = dependency.destinationStateAtMapping else {
                return XCTFail("Every referenced dependency must be present on both sides")
            }
        }

        for sourceTargetPresent in [false, true] {
            for destinationTargetPresent in [false, true] {
                let combination = try CheckRunnerDestinationBeginBindingV1(
                    source: recheck.source,
                    map: map,
                    recordMappedDependencyBasis: recheck.recordBasis(
                        sourceTargetPresent: sourceTargetPresent,
                        destinationTargetPresent: destinationTargetPresent
                    ),
                    timeZoneMappedDependencyBasis: [recheck.siteDependency()]
                )
                let combinationTarget = try XCTUnwrap(
                    combination.recordMappedDependencyBasis.first {
                        $0.sourceIdentity.kind == .workflowRecord
                            && $0.sourceIdentity.id == recheck.recordID
                    }
                )
                if sourceTargetPresent {
                    guard case .present(revision: 0, semanticSHA256: _) = combinationTarget.sourceState else {
                        return XCTFail("Expected zero-revision PRESENT source target")
                    }
                } else {
                    guard case .absent(revision: 17) = combinationTarget.sourceState else {
                        return XCTFail("Expected positive-revision ABSENT source target")
                    }
                }
                if destinationTargetPresent {
                    guard case .present(revision: .max, semanticSHA256: _)
                            = combinationTarget.destinationStateAtMapping else {
                        return XCTFail("Expected maximum-revision PRESENT destination target")
                    }
                } else {
                    guard case .absent(revision: 19) = combinationTarget.destinationStateAtMapping else {
                        return XCTFail("Expected positive-revision ABSENT destination target")
                    }
                }
                try combination.validate(source: recheck.source, map: map)
            }
        }

        let check = try restoreBindingFixture(seed: 1_200, recheck: false, includesTimeZone: false)
        let checkMap = try check.map(mode: .sameWorkspace)
        let checkBinding = try CheckRunnerDestinationBeginBindingV1(
            source: check.source,
            map: checkMap,
            recordMappedDependencyBasis: try check.recordBasis(targetPresent: false),
            timeZoneMappedDependencyBasis: nil
        )
        XCTAssertEqual(checkBinding.recordMappedDependencyBasis.count, 3)
        XCTAssertNil(checkBinding.timeZoneMutationID)
        XCTAssertNil(checkBinding.timeZoneCommand)
        XCTAssertNil(checkBinding.timeZoneMappedDependencyBasis)
        XCTAssertNil(checkBinding.timeZoneCommittedAt)

        // These are decoded binding shapes only. CheckRunnerFrozenBeginAttemptV1
        // intentionally imposes stronger entry/source relationships, so neither
        // single-optional command is presented as a valid full frozen attempt.
        let bothOptionalsObject = try restoreBeginObject(absentTarget)
        XCTAssertEqual(
            try restoreBeginJSONData(bothOptionalsObject),
            try FieldDraftCanonicalCodecV1.encode(absentTarget)
        )
        let optionalShapes: [(
            label: String,
            omittedCommandKey: String,
            omittedID: UUID,
            includedKind: WorkspaceEntityKindV1,
            includedID: UUID
        )] = [
            (
                "issue-only",
                "parentRecordID",
                try XCTUnwrap(recheck.parentRecordID),
                .issue,
                try XCTUnwrap(recheck.issueID)
            ),
            (
                "parent-only",
                "issueID",
                try XCTUnwrap(recheck.issueID),
                .workflowRecord,
                try XCTUnwrap(recheck.parentRecordID)
            ),
        ]
        for shape in optionalShapes {
            let omittedDependency = try XCTUnwrap(
                absentTarget.recordMappedDependencyBasis.first {
                    $0.sourceIdentity.id == shape.omittedID
                }
            )
            let exactFour = absentTarget.recordMappedDependencyBasis.filter {
                $0.sourceIdentity.id != shape.omittedID
            }
            var shapeObject = bothOptionalsObject
            var shapeCommand = try XCTUnwrap(shapeObject["recordCommand"] as? [String: Any])
            shapeCommand.removeValue(forKey: shape.omittedCommandKey)
            shapeObject["recordCommand"] = shapeCommand
            shapeObject["recordMappedDependencyBasis"] = try exactFour.map {
                try restoreBeginJSONValue($0)
            }
            let decodedShape = try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerDestinationBeginBindingV1.self,
                from: restoreBeginJSONData(shapeObject)
            )
            XCTAssertEqual(decodedShape.recordMappedDependencyBasis.count, 4, shape.label)
            try decodedShape.validate()
            XCTAssertThrowsError(
                try decodedShape.validate(source: recheck.source, map: map),
                shape.label
            ) { error in
                XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidBinding)
            }

            let missingBasis = exactFour.filter { $0.sourceIdentity.id != shape.includedID }
            var missingObject = shapeObject
            missingObject["recordMappedDependencyBasis"] = try missingBasis.map {
                try restoreBeginJSONValue($0)
            }
            assertRestoreBeginDecodeFails(
                CheckRunnerDestinationBeginBindingV1.self,
                missingObject
            )

            var extraObject = shapeObject
            let extraBasis = (exactFour + [omittedDependency]).sorted {
                $0.sourceIdentity.stableKey < $1.sourceIdentity.stableKey
            }
            extraObject["recordMappedDependencyBasis"] = try extraBasis.map {
                try restoreBeginJSONValue($0)
            }
            assertRestoreBeginDecodeFails(
                CheckRunnerDestinationBeginBindingV1.self,
                extraObject
            )

            var substitutedBasis = exactFour
            let includedIndex = try XCTUnwrap(substitutedBasis.firstIndex {
                $0.sourceIdentity.kind == shape.includedKind
                    && $0.sourceIdentity.id == shape.includedID
            })
            substitutedBasis[includedIndex] = try recheck.dependency(
                kind: shape.includedKind,
                id: restoreBeginID(shape.label == "issue-only" ? 91_001 : 91_002),
                sourceState: .present(
                    revision: 0,
                    semanticSHA256: String(repeating: "b", count: 64)
                ),
                destinationState: .present(
                    revision: .max,
                    semanticSHA256: String(repeating: "c", count: 64)
                )
            )
            substitutedBasis.sort { $0.sourceIdentity.stableKey < $1.sourceIdentity.stableKey }
            var substituteObject = shapeObject
            substituteObject["recordMappedDependencyBasis"] = try substitutedBasis.map {
                try restoreBeginJSONValue($0)
            }
            assertRestoreBeginDecodeFails(
                CheckRunnerDestinationBeginBindingV1.self,
                substituteObject
            )
        }

        let validBasis = try recheck.recordBasis(targetPresent: false)
        for invalid in [
            Array(validBasis.dropLast()),
            validBasis + [try recheck.extraDependency()],
            validBasis + [validBasis[0]],
        ] {
            XCTAssertThrowsError(try CheckRunnerDestinationBeginBindingV1(
                source: recheck.source,
                map: map,
                recordMappedDependencyBasis: invalid,
                timeZoneMappedDependencyBasis: [try recheck.siteDependency()]
            )) { error in
                XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidBinding)
            }
        }

        let referents: [(WorkspaceEntityKindV1, UUID)] = [
            (.asset, recheck.assetID),
            (.site, recheck.siteID),
            (.issue, try XCTUnwrap(recheck.issueID)),
            (.workflowRecord, try XCTUnwrap(recheck.parentRecordID)),
        ]
        for (kind, id) in referents {
            for (side, mutateSource) in [("source", true), ("destination", false)] {
                var absentReferent = validBasis
                let index = try XCTUnwrap(absentReferent.firstIndex {
                    $0.sourceIdentity.kind == kind && $0.sourceIdentity.id == id
                })
                let retained = absentReferent[index]
                absentReferent[index] = try recheck.dependency(
                    kind: kind,
                    id: id,
                    sourceState: mutateSource
                        ? .absent(revision: retained.sourceState.revision)
                        : retained.sourceState,
                    destinationState: mutateSource
                        ? retained.destinationStateAtMapping
                        : .absent(revision: retained.destinationStateAtMapping.revision)
                )
                let coherentSite = try XCTUnwrap(absentReferent.first {
                    $0.sourceIdentity.kind == .site
                })
                XCTAssertThrowsError(try CheckRunnerDestinationBeginBindingV1(
                    source: recheck.source,
                    map: map,
                    recordMappedDependencyBasis: absentReferent,
                    timeZoneMappedDependencyBasis: [coherentSite]
                ), "\(kind.rawValue) \(side) absence") { error in
                    XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidBinding)
                }
            }
        }
    }

    func testDestinationBindingRejectsTimeZoneOptionalAndBasisDivergence() throws {
        let fixture = try restoreBindingFixture(seed: 1_300, recheck: true, includesTimeZone: true)
        let map = try fixture.map(mode: .fork)
        let binding = try CheckRunnerDestinationBeginBindingV1(
            source: fixture.source,
            map: map,
            recordMappedDependencyBasis: try fixture.recordBasis(targetPresent: false),
            timeZoneMappedDependencyBasis: [try fixture.siteDependency()]
        )
        let base = try restoreBeginObject(binding)
        XCTAssertEqual(try restoreBeginJSONData(base), try FieldDraftCanonicalCodecV1.encode(binding))

        for key in [
            "timeZoneMutationID",
            "timeZoneCommand",
            "timeZoneMappedDependencyBasis",
            "timeZoneCommittedAt",
        ] {
            var missing = base
            missing.removeValue(forKey: key)
            assertRestoreBeginDecodeFails(CheckRunnerDestinationBeginBindingV1.self, missing)
        }

        var divergentBasis = base
        var zoneBasis = try XCTUnwrap(
            divergentBasis["timeZoneMappedDependencyBasis"] as? [[String: Any]]
        )
        var state = try XCTUnwrap(zoneBasis[0]["sourceState"] as? [String: Any])
        state["revision"] = 77
        zoneBasis[0]["sourceState"] = state
        divergentBasis["timeZoneMappedDependencyBasis"] = zoneBasis
        assertRestoreBeginDecodeFails(CheckRunnerDestinationBeginBindingV1.self, divergentBasis)

        var extraZoneBasis = base
        var twoSites = try XCTUnwrap(extraZoneBasis["timeZoneMappedDependencyBasis"] as? [[String: Any]])
        twoSites.append(twoSites[0])
        extraZoneBasis["timeZoneMappedDependencyBasis"] = twoSites
        assertRestoreBeginDecodeFails(CheckRunnerDestinationBeginBindingV1.self, extraZoneBasis)

        let withoutZone = try restoreBindingFixture(seed: 1_400, recheck: false, includesTimeZone: false)
        XCTAssertThrowsError(try CheckRunnerDestinationBeginBindingV1(
            source: withoutZone.source,
            map: withoutZone.map(mode: .sameWorkspace),
            recordMappedDependencyBasis: withoutZone.recordBasis(targetPresent: false),
            timeZoneMappedDependencyBasis: [withoutZone.siteDependency()]
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidBinding)
        }
    }

    func testDestinationBindingClosedDecodeAndFullCorrespondenceRejectHostileChanges() throws {
        let fixture = try restoreBindingFixture(seed: 1_500, recheck: true, includesTimeZone: true)
        let map = try fixture.map(mode: .fork)
        let binding = try CheckRunnerDestinationBeginBindingV1(
            source: fixture.source,
            map: map,
            recordMappedDependencyBasis: try fixture.recordBasis(targetPresent: false),
            timeZoneMappedDependencyBasis: [try fixture.siteDependency()]
        )
        let base = try restoreBeginObject(binding)
        XCTAssertEqual(try restoreBeginJSONData(base), try FieldDraftCanonicalCodecV1.encode(binding))

        var topUnknown = base
        topUnknown["future"] = true
        assertRestoreBeginDecodeFails(CheckRunnerDestinationBeginBindingV1.self, topUnknown)

        var workspaceUnknown = base
        var workspace = try XCTUnwrap(workspaceUnknown["destinationWorkspaceID"] as? [String: Any])
        workspace["future"] = true
        workspaceUnknown["destinationWorkspaceID"] = workspace
        assertRestoreBeginDecodeFails(CheckRunnerDestinationBeginBindingV1.self, workspaceUnknown)

        var commandUnknown = base
        var command = try XCTUnwrap(commandUnknown["recordCommand"] as? [String: Any])
        command["future"] = true
        commandUnknown["recordCommand"] = command
        assertRestoreBeginDecodeFails(CheckRunnerDestinationBeginBindingV1.self, commandUnknown)

        var zoneUnknown = base
        var zone = try XCTUnwrap(zoneUnknown["timeZoneCommand"] as? [String: Any])
        zone["future"] = true
        zoneUnknown["timeZoneCommand"] = zone
        assertRestoreBeginDecodeFails(CheckRunnerDestinationBeginBindingV1.self, zoneUnknown)

        var missing = base
        missing.removeValue(forKey: "recordCommittedAt")
        assertRestoreBeginDecodeFails(CheckRunnerDestinationBeginBindingV1.self, missing)

        var noncanonicalOrder = base
        let orderedBasis = try XCTUnwrap(
            noncanonicalOrder["recordMappedDependencyBasis"] as? [[String: Any]]
        )
        noncanonicalOrder["recordMappedDependencyBasis"] = Array(orderedBasis.reversed())
        assertRestoreBeginDecodeFails(CheckRunnerDestinationBeginBindingV1.self, noncanonicalOrder)

        var trailing = try FieldDraftCanonicalCodecV1.encode(binding)
        trailing.append(0x20)
        XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(
            CheckRunnerDestinationBeginBindingV1.self,
            from: trailing
        )) { error in
            XCTAssertNotNil(error)
        }

        var wrongMappedObject = base
        var mappedBasis = try XCTUnwrap(
            wrongMappedObject["recordMappedDependencyBasis"] as? [[String: Any]]
        )
        let assetIndex = try XCTUnwrap(mappedBasis.firstIndex {
            (($0["sourceIdentity"] as? [String: Any])?["kind"] as? String) == "asset"
        })
        var destination = try XCTUnwrap(mappedBasis[assetIndex]["destinationIdentity"] as? [String: Any])
        destination["id"] = restoreBeginID(1_599).uuidString
        mappedBasis[assetIndex]["destinationIdentity"] = destination
        wrongMappedObject["recordMappedDependencyBasis"] = mappedBasis
        let wrongMapped = try FieldDraftCanonicalCodecV1.decode(
            CheckRunnerDestinationBeginBindingV1.self,
            from: restoreBeginJSONData(wrongMappedObject)
        )
        XCTAssertThrowsError(try wrongMapped.validate(source: fixture.source, map: map)) { error in
            XCTAssertNotNil(error)
        }

        var alteredCommandObject = base
        var alteredCommand = try XCTUnwrap(alteredCommandObject["recordCommand"] as? [String: Any])
        alteredCommand["afterDarkAcknowledgementCopy"] = "Altered retained copy"
        alteredCommandObject["recordCommand"] = alteredCommand
        let alteredCommandBinding = try FieldDraftCanonicalCodecV1.decode(
            CheckRunnerDestinationBeginBindingV1.self,
            from: restoreBeginJSONData(alteredCommandObject)
        )
        XCTAssertThrowsError(try alteredCommandBinding.validate(source: fixture.source, map: map)) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidBinding)
        }

        var alteredTimeObject = base
        alteredTimeObject["recordCommittedAt"] = 1_800_000_999_000
        let alteredTimeBinding = try FieldDraftCanonicalCodecV1.decode(
            CheckRunnerDestinationBeginBindingV1.self,
            from: restoreBeginJSONData(alteredTimeObject)
        )
        XCTAssertThrowsError(try alteredTimeBinding.validate(source: fixture.source, map: map)) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidBinding)
        }

        var alteredZoneTimeObject = base
        alteredZoneTimeObject["timeZoneCommittedAt"] = 1_800_001_111_000
        let alteredZoneTimeBinding = try FieldDraftCanonicalCodecV1.decode(
            CheckRunnerDestinationBeginBindingV1.self,
            from: restoreBeginJSONData(alteredZoneTimeObject)
        )
        XCTAssertThrowsError(try alteredZoneTimeBinding.validate(
            source: fixture.source,
            map: map
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidBinding)
        }

        let foreignSource = try restoreBindingFixture(
            seed: 1_600,
            recheck: true,
            includesTimeZone: true
        ).source
        XCTAssertThrowsError(try binding.validate(source: foreignSource, map: map)) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidBinding)
        }
        XCTAssertThrowsError(try binding.validate(
            source: fixture.source,
            map: fixture.map(mode: .crossWorkspaceReplace)
        )) { error in
            XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidBinding)
        }
    }
}

private struct RestoreBindingFixture {
    let source: CheckRunnerFrozenBeginAttemptV1
    let destinationWorkspaceID: UUID
    let recordID: UUID
    let assetID: UUID
    let issueID: UUID?
    let parentRecordID: UUID?
    let siteID: UUID
    let timeZoneMutationID: UUID

    func map(mode: CheckRunnerRestoreModeV1) throws -> CheckRunnerRestoreIdentityMapV1 {
        let destinationWorkspace = mode == .sameWorkspace
            ? source.sourceWorkspaceID.rawValue
            : destinationWorkspaceID
        var sources: [(CheckRunnerRestoreIdentityKindV1, UUID)] = [
            (.workflowRecord, recordID),
            (.asset, assetID),
            (.site, siteID),
            (.beginRecordMutation, recordID),
        ]
        if let issueID { sources.append((.issue, issueID)) }
        if let parentRecordID { sources.append((.parentRecord, parentRecordID)) }
        if source.timeZone != nil { sources.append((.beginTimeZoneMutation, timeZoneMutationID)) }
        let pairs = try sources.map { kind, sourceID in
            let destinationID: UUID
            if mode == .fork, let namespace = kind.operationalNamespace {
                destinationID = try XCTUnwrap(RestoreIdentityV1.destinationFieldDraftID(
                    for: sourceID,
                    namespace: namespace,
                    mode: .fork,
                    destinationWorkspaceID: destinationWorkspace
                ))
            } else {
                destinationID = sourceID
            }
            return try CheckRunnerRestoreIdentityPairV1(
                kind: kind,
                sourceID: sourceID,
                destinationID: destinationID
            )
        }
        return try CheckRunnerRestoreIdentityMapV1(
            mode: mode,
            sourceWorkspaceID: source.sourceWorkspaceID.rawValue,
            destinationWorkspaceID: destinationWorkspace,
            pairs: pairs
        )
    }

    func dependency(
        kind: WorkspaceEntityKindV1,
        id: UUID,
        sourceState: CheckRunnerDependencyStateV1,
        destinationState: CheckRunnerDependencyStateV1
    ) throws -> CheckRunnerDestinationDependencyV1 {
        let identity = try WorkspaceEntityIdentityV1(kind: kind, id: id)
        return try CheckRunnerDestinationDependencyV1(
            sourceIdentity: identity,
            sourceState: sourceState,
            destinationIdentity: identity,
            destinationStateAtMapping: destinationState
        )
    }

    func siteDependency() throws -> CheckRunnerDestinationDependencyV1 {
        try dependency(
            kind: .site,
            id: siteID,
            sourceState: .present(
                revision: 0,
                semanticSHA256: String(repeating: "1", count: 64)
            ),
            destinationState: .present(
                revision: .max,
                semanticSHA256: String(repeating: "2", count: 64)
            )
        )
    }

    func recordBasis(targetPresent: Bool) throws -> [CheckRunnerDestinationDependencyV1] {
        try recordBasis(
            sourceTargetState: targetPresent
                ? .present(revision: 0, semanticSHA256: String(repeating: "3", count: 64))
                : .absent(revision: 0),
            destinationTargetState: targetPresent
                ? .present(revision: .max, semanticSHA256: String(repeating: "4", count: 64))
                : .absent(revision: .max)
        )
    }

    func recordBasis(
        sourceTargetPresent: Bool,
        destinationTargetPresent: Bool
    ) throws -> [CheckRunnerDestinationDependencyV1] {
        try recordBasis(
            sourceTargetState: sourceTargetPresent
                ? .present(revision: 0, semanticSHA256: String(repeating: "3", count: 64))
                : .absent(revision: 17),
            destinationTargetState: destinationTargetPresent
                ? .present(revision: .max, semanticSHA256: String(repeating: "4", count: 64))
                : .absent(revision: 19)
        )
    }

    private func recordBasis(
        sourceTargetState: CheckRunnerDependencyStateV1,
        destinationTargetState: CheckRunnerDependencyStateV1
    ) throws -> [CheckRunnerDestinationDependencyV1] {
        var values = try [
            dependency(
                kind: .workflowRecord,
                id: recordID,
                sourceState: sourceTargetState,
                destinationState: destinationTargetState
            ),
            dependency(
                kind: .asset,
                id: assetID,
                sourceState: .present(
                    revision: .max,
                    semanticSHA256: String(repeating: "5", count: 64)
                ),
                destinationState: .present(
                    revision: 0,
                    semanticSHA256: String(repeating: "6", count: 64)
                )
            ),
            siteDependency(),
        ]
        if let issueID {
            values.append(try dependency(
                kind: .issue,
                id: issueID,
                sourceState: .present(
                    revision: 7,
                    semanticSHA256: String(repeating: "7", count: 64)
                ),
                destinationState: .present(
                    revision: 8,
                    semanticSHA256: String(repeating: "8", count: 64)
                )
            ))
        }
        if let parentRecordID {
            values.append(try dependency(
                kind: .workflowRecord,
                id: parentRecordID,
                sourceState: .present(
                    revision: 9,
                    semanticSHA256: String(repeating: "9", count: 64)
                ),
                destinationState: .present(
                    revision: 10,
                    semanticSHA256: String(repeating: "a", count: 64)
                )
            ))
        }
        return values.sorted { $0.sourceIdentity.stableKey < $1.sourceIdentity.stableKey }
    }

    func extraDependency() throws -> CheckRunnerDestinationDependencyV1 {
        try dependency(
            kind: .site,
            id: restoreBeginID(99_999),
            sourceState: .present(
                revision: 1,
                semanticSHA256: String(repeating: "b", count: 64)
            ),
            destinationState: .present(
                revision: 1,
                semanticSHA256: String(repeating: "c", count: 64)
            )
        )
    }
}

private func restoreBindingFixture(
    seed: Int,
    recheck: Bool,
    includesTimeZone: Bool
) throws -> RestoreBindingFixture {
    let workspaceID = WorkspaceID(rawValue: restoreBeginID(seed))
    let destinationWorkspaceID = restoreBeginID(seed + 1)
    let recordID = restoreBeginID(seed + 2)
    let assetID = restoreBeginID(seed + 3)
    let siteID = restoreBeginID(seed + 4)
    let issueID = recheck ? restoreBeginID(seed + 5) : nil
    let parentRecordID = recheck ? restoreBeginID(seed + 6) : nil
    let timeZoneMutationID = restoreBeginID(seed + 7)
    let observedAt = Date(timeIntervalSince1970: 1_789_223_456.123)
    let committedAt = Date(timeIntervalSince1970: 1_789_223_500.456)
    let frozenTime = try TimeContextRule.freeze(
        observedAtUTC: observedAt,
        confirmedTimeZoneID: "America/New_York"
    )
    let command = CheckDraftMutationV1(
        recordID: recordID,
        assetID: assetID,
        issueID: issueID,
        parentRecordID: parentRecordID,
        stage: recheck ? WorkflowStage.recheck.rawValue : WorkflowStage.check.rawValue,
        draftStepKey: WorkflowDraftStep.wide.rawValue,
        startedAt: observedAt,
        observedAtUTC: frozenTime.observedAtUTC,
        timeZoneID: frozenTime.timeZoneID,
        utcOffsetMinutes: frozenTime.utcOffsetMinutes,
        localDate: frozenTime.localDate,
        localTime: frozenTime.localTime,
        afterDarkAcknowledgementKey: "after_dark",
        afterDarkAcknowledgementCopy: "After-dark conditions acknowledged",
        afterDarkAcknowledgementVersion: "1",
        afterDarkAcknowledgementAccepted: true,
        safePositionAcknowledgementKey: "safe_authorized_position",
        safePositionAcknowledgementCopy: "Safe position acknowledged",
        safePositionAcknowledgementVersion: "1",
        safePositionAcknowledgementAccepted: true,
        packID: ShippingIlluminatedSignAdapterV1.packageID,
        packSchemaVersion: 1,
        packContentVersion: 1,
        pdfTemplateID: "illuminated-sign-report",
        pdfTemplateVersion: 1
    )
    let source = try restoreBindingSource(
        seed: seed,
        workspaceID: workspaceID,
        assetID: assetID,
        siteID: siteID,
        issueID: issueID
    )
    var expected = try [
        WorkspaceEntityRevisionV1(
            identity: WorkspaceEntityIdentityV1(kind: .workflowRecord, id: recordID),
            revision: 0
        ),
        WorkspaceEntityRevisionV1(
            identity: WorkspaceEntityIdentityV1(kind: .asset, id: assetID),
            revision: 5
        ),
    ]
    if let issueID {
        expected.append(WorkspaceEntityRevisionV1(
            identity: try WorkspaceEntityIdentityV1(kind: .issue, id: issueID),
            revision: 6
        ))
    }
    if let parentRecordID {
        expected.append(WorkspaceEntityRevisionV1(
            identity: try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: parentRecordID),
            revision: 7
        ))
    }
    expected.sort { $0.identity.stableKey < $1.identity.stableKey }
    let timeZone: CheckRunnerBeginTimeZoneAttemptV1? = includesTimeZone
        ? try .init(
            command: .init(
                siteID: siteID,
                timeZoneID: "America/New_York",
                confirmedAt: observedAt
            ),
            mutationID: MutationIDV1(rawValue: timeZoneMutationID),
            expectedSiteRevision: .max - 1,
            committedAt: committedAt
        )
        : nil
    let attempt = try CheckRunnerFrozenBeginAttemptV1(
        source: source,
        sourceWorkspaceID: workspaceID,
        recordCommand: command,
        recordMutationID: MutationIDV1(rawValue: recordID),
        recordExpectedEntityRevisions: expected,
        recordCommittedAt: committedAt,
        timeZone: timeZone,
        siteID: siteID,
        resolvedSiteTimeZoneID: "America/New_York"
    )
    return RestoreBindingFixture(
        source: attempt,
        destinationWorkspaceID: destinationWorkspaceID,
        recordID: recordID,
        assetID: assetID,
        issueID: issueID,
        parentRecordID: parentRecordID,
        siteID: siteID,
        timeZoneMutationID: timeZoneMutationID
    )
}

private func restoreBindingSource(
    seed: Int,
    workspaceID: WorkspaceID,
    assetID: UUID,
    siteID: UUID,
    issueID: UUID?
) throws -> CheckRunnerRoundItemSourceV1 {
    let package = try RoundPackageReleaseReferenceV1(
        packageReleaseID: String(repeating: "d", count: 64),
        packageID: ShippingIlluminatedSignAdapterV1.packageID,
        packageContentVersion: 1,
        packageSHA256: String(repeating: "e", count: 64),
        workflowSHA256: String(repeating: "f", count: 64)
    )
    let requirement = try RoundPackageContentRequirementV1(
        packageRelease: package,
        requiredContent: []
    )
    let selection = try RoundAssetSelectionV1(
        assetID: assetID,
        siteID: siteID,
        labelAtSelection: "Binding fixture asset"
    )
    let original = try RoundItemV1(
        itemID: restoreBeginID(seed + 20),
        order: 0,
        selection: selection,
        requirement: requirement
    )
    let actorReference = try LocalActorReferenceV1(
        actorReferenceID: restoreBeginID(seed + 21),
        workspaceID: workspaceID,
        displayName: "Binding fixture actor"
    )
    let actor = try ActorSnapshotV1(
        snapshotID: restoreBeginID(seed + 22),
        workspaceID: workspaceID,
        actor: actorReference,
        responsibility: .recordedBy,
        displayNameAtTime: "Binding fixture actor",
        capturedAt: Date(timeIntervalSince1970: 1_789_200_000)
    )
    let entered = try RoundItemV1(
        itemID: original.itemID,
        order: original.order,
        selection: original.selection,
        requirement: original.requirement,
        disposition: .visited,
        visit: RoundItemVisitV1(
            visitedAt: Date(timeIntervalSince1970: 1_789_200_100),
            recordedBy: actor
        )
    )
    let sourceCheckpoint = try restoreBeginDecodeObject(
        RepetitiveCaptureSourceCheckpointReferenceV1.self,
        [
            "draftID": restoreBeginID(seed + 23).uuidString,
            "draftRevision": 1,
            "checkpointSHA256": String(repeating: "1", count: 64),
            "mutationID": restoreBeginID(seed + 24).uuidString,
        ]
    )
    let entryCheckpoint = try restoreBeginDecodeObject(
        RepetitiveCaptureSourceCheckpointReferenceV1.self,
        [
            "draftID": restoreBeginID(seed + 25).uuidString,
            "draftRevision": 2,
            "checkpointSHA256": String(repeating: "2", count: 64),
            "mutationID": restoreBeginID(seed + 26).uuidString,
        ]
    )
    let requested = issueID.map { CheckRunnerRequestedEntryV1.recheck(issueID: $0) } ?? .check
    let values: [String: Any] = [
        "sourceCheckpoint": try restoreBeginJSONValue(sourceCheckpoint),
        "entryProgressCheckpoint": try restoreBeginJSONValue(entryCheckpoint),
        "roundAtEntry": try restoreBeginJSONValue(RoundSessionReferenceV1(
            workspaceID: workspaceID,
            sessionID: restoreBeginID(seed + 27),
            revision: 3,
            sessionSHA256: String(repeating: "3", count: 64)
        )),
        "originalItem": try restoreBeginJSONValue(original),
        "itemAtEntry": try restoreBeginJSONValue(entered),
        "assetID": assetID.uuidString,
        "packageRelease": try restoreBeginJSONValue(package),
        "legacyPackageIdentity": try restoreBeginJSONValue(PackageReleaseIdentityV1(
            packageID: ShippingIlluminatedSignAdapterV1.packageID,
            schemaVersion: 1,
            contentVersion: 1
        )),
        "requestedEntry": try restoreBeginJSONValue(requested),
    ]
    return try restoreBeginDecodeObject(CheckRunnerRoundItemSourceV1.self, values)
}

private struct RestoreBeginFixture {
    let workspaceID: WorkspaceID
    let replicaID: ReplicaID
    let generationID: UUID
    let mutationID: MutationIDV1
    let committedAt: Date
    let evidence: CheckRunnerBeginCommittedEvidenceV1
}

private func restoreBeginFixture(seed: Int) throws -> RestoreBeginFixture {
    let workspaceID = WorkspaceID(rawValue: restoreBeginID(seed))
    let replicaID = ReplicaID(rawValue: restoreBeginID(seed + 1))
    let generationID = restoreBeginID(seed + 2)
    let writerID = restoreBeginID(seed + 3)
    let mutationID = try MutationIDV1(rawValue: restoreBeginID(seed + 4))
    let siteID = restoreBeginID(seed + 5)
    let unrelatedID = restoreBeginID(seed + 6)
    let committedAt = Date(timeIntervalSince1970: 1_725_555_123.456)
    let site = try WorkspaceEntityIdentityV1(kind: .site, id: siteID)
    let unrelated = try WorkspaceEntityIdentityV1(kind: .asset, id: unrelatedID)
    let before = try WorkspaceExpectedRevisionV1(
        workspaceID: workspaceID,
        generationID: generationID,
        writerInstanceID: writerID,
        workspaceRevision: 40,
        entityRevisions: [
            .init(identity: unrelated, revision: 19),
            .init(identity: site, revision: 8),
        ]
    )
    let command = SiteTimeZoneMutationV1(
        siteID: siteID,
        timeZoneID: "America/New_York",
        confirmedAt: Date(timeIntervalSince1970: 1_725_555_000.125)
    )
    let envelope = try MutationEnvelopeV1(
        request: WorkspaceMutationRequestV1(
            mutationID: mutationID,
            expectedRevision: before,
            command: .updateSiteTimeZone(command)
        ),
        identity: WorkspaceReplicaIdentityV1(workspaceID: workspaceID, replicaID: replicaID),
        sourceKind: .importedHistory,
        contentDependencyIDs: ["pack:retained-v1"]
    )
    let after = try MutationPortableExpectedRevisionV1(WorkspaceExpectedRevisionV1(
        workspaceID: workspaceID,
        generationID: generationID,
        writerInstanceID: writerID,
        workspaceRevision: 41,
        entityRevisions: [
            .init(identity: unrelated, revision: 19),
            .init(identity: site, revision: 9),
        ]
    ))
    let receipt = try MutationReceiptV1(
        identity: MutationReceiptIdentityV1(
            workspaceID: workspaceID,
            replicaID: replicaID,
            localSequence: 77
        ),
        envelope: envelope,
        resultingRevision: after,
        postImages: [.site(
            id: siteID,
            revision: 9,
            semanticSHA256: String(repeating: "f", count: 64)
        )],
        committedAt: committedAt
    )
    return RestoreBeginFixture(
        workspaceID: workspaceID,
        replicaID: replicaID,
        generationID: generationID,
        mutationID: mutationID,
        committedAt: committedAt,
        evidence: try CheckRunnerBeginCommittedEvidenceV1(envelope: envelope, receipt: receipt)
    )
}

private func restoreBeginObject<Value: Codable>(_ value: Value) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(
        with: FieldDraftCanonicalCodecV1.encode(value)
    ) as? [String: Any])
}

private func restoreBeginJSONData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
}

private func restoreBeginJSONValue<Value: Codable>(_ value: Value) throws -> Any {
    try JSONSerialization.jsonObject(with: FieldDraftCanonicalCodecV1.encode(value))
}

private func restoreBeginDecodeObject<Value: Codable>(
    _ type: Value.Type,
    _ object: [String: Any]
) throws -> Value {
    try FieldDraftCanonicalCodecV1.decode(type, from: restoreBeginJSONData(object))
}

private func assertRestoreBeginDecodeFails<Value: Codable>(
    _ type: Value.Type,
    _ object: [String: Any],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(
        try FieldDraftCanonicalCodecV1.decode(type, from: restoreBeginJSONData(object)),
        file: file,
        line: line
    ) { error in
        XCTAssertNotNil(error, file: file, line: line)
    }
}

private func restoreBeginID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", value))!
}

extension V23CheckRunnerRestoreBeginCorrespondenceTests {
    func testBeginMutationCorrespondenceCoversEveryModeAndBothRolesWithWrappedHashes() throws {
        let fixture = try restoreBindingFixture(seed: 2_000, recheck: true, includesTimeZone: true)
        for mode in [CheckRunnerRestoreModeV1.sameWorkspace, .crossWorkspaceReplace, .fork] {
            let map = try fixture.map(mode: mode)
            let binding = try restoreMutationBinding(fixture, map: map)
            let record = try CheckRunnerBeginMutationCorrespondenceV1.record(
                source: fixture.source,
                binding: binding,
                map: map,
                expectedSourceEvidence: .absent,
                destinationReceipt: nil
            )
            let timeZone = try XCTUnwrap(CheckRunnerBeginMutationCorrespondenceV1.timeZone(
                source: fixture.source,
                binding: binding,
                map: map,
                expectedSourceEvidence: .absent,
                destinationReceipt: nil
            ))

            XCTAssertEqual(record.role, .record)
            XCTAssertEqual(timeZone.role, .timeZone)
            XCTAssertEqual(record.sourceCommandCanonicalSHA256, try WorkspaceMutationCanonicalV1.sha256(
                WorkspaceCommandV1.createCheckDraft(fixture.source.recordCommand)
            ))
            XCTAssertEqual(timeZone.sourceCommandCanonicalSHA256, try WorkspaceMutationCanonicalV1.sha256(
                WorkspaceCommandV1.updateSiteTimeZone(try XCTUnwrap(fixture.source.timeZone).command)
            ))
            XCTAssertNotEqual(record.sourceCommandCanonicalSHA256, try FieldDraftCanonicalCodecV1.sha256(
                fixture.source.recordCommand
            ))
            XCTAssertNotEqual(timeZone.sourceCommandCanonicalSHA256, try FieldDraftCanonicalCodecV1.sha256(
                try XCTUnwrap(fixture.source.timeZone).command
            ))
            for correspondence in [record, timeZone] {
                try correspondence.validate(source: fixture.source, binding: binding, map: map)
                let bytes = try FieldDraftCanonicalCodecV1.encode(correspondence)
                let decoded = try FieldDraftCanonicalCodecV1.decode(
                    CheckRunnerBeginMutationCorrespondenceV1.self,
                    from: bytes
                )
                XCTAssertEqual(decoded, correspondence)
                XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), bytes)
            }
            XCTAssertEqual(record.hasIdenticalKeys, mode == .sameWorkspace)
            XCTAssertEqual(timeZone.hasIdenticalKeys, mode == .sameWorkspace)
        }
    }

    func testBeginMutationExactEvidenceRequiresFrozenRevisionSubsetAndAllowsUnrelatedRows() throws {
        let fixture = try restoreBindingFixture(seed: 2_100, recheck: true, includesTimeZone: true)
        let map = try fixture.map(mode: .crossWorkspaceReplace)
        let binding = try restoreMutationBinding(fixture, map: map)
        let extra = try WorkspaceEntityRevisionV1(
            identity: .init(kind: .savedSmartView, id: restoreBeginID(92_100)),
            revision: 31
        )
        let evidence = try restoreMutationEvidence(
            workspaceID: fixture.source.sourceWorkspaceID,
            mutationID: fixture.source.recordMutationID,
            command: .createCheckDraft(fixture.source.recordCommand),
            expectedEntities: fixture.source.recordExpectedEntityRevisions + [extra],
            committedAt: fixture.source.recordCommittedAt,
            seed: 92_110,
            sourceKind: .importedHistory,
            correlationID: restoreBeginID(92_111)
        )
        let correspondence = try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source,
            binding: binding,
            map: map,
            expectedSourceEvidence: .exact(evidence),
            destinationReceipt: nil
        )
        try correspondence.validate(source: fixture.source, binding: binding, map: map)
        XCTAssertEqual(correspondence.expectedSourceEvidence, .exact(evidence))
        XCTAssertEqual(evidence.envelope.sourceKind, .importedHistory)
        XCTAssertEqual(evidence.envelope.correlationID, restoreBeginID(92_111))
        guard case let .exact(retained) = correspondence.expectedSourceEvidence else {
            return XCTFail("Expected exact retained source evidence")
        }
        XCTAssertEqual(try retained.envelope.canonicalData(), try evidence.envelope.canonicalData())
        XCTAssertEqual(try retained.receipt.canonicalData(), try evidence.receipt.canonicalData())
        XCTAssertEqual(retained.receipt.sourceKind, evidence.envelope.sourceKind)
        XCTAssertEqual(retained.receipt.correlationID, evidence.envelope.correlationID)

        let required = fixture.source.recordExpectedEntityRevisions
        let missingEvidence = try restoreMutationEvidence(
            workspaceID: fixture.source.sourceWorkspaceID,
            mutationID: fixture.source.recordMutationID,
            command: .createCheckDraft(fixture.source.recordCommand),
            expectedEntities: required.filter { $0.identity.kind != .asset } + [extra],
            committedAt: fixture.source.recordCommittedAt,
            seed: 92_120
        )
        XCTAssertThrowsError(try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .exact(missingEvidence), destinationReceipt: nil
        ))
        var mismatched = required
        mismatched[0] = try .init(identity: mismatched[0].identity, revision: mismatched[0].revision + 1)
        let mismatchedEvidence = try restoreMutationEvidence(
            workspaceID: fixture.source.sourceWorkspaceID,
            mutationID: fixture.source.recordMutationID,
            command: .createCheckDraft(fixture.source.recordCommand),
            expectedEntities: mismatched + [extra],
            committedAt: fixture.source.recordCommittedAt,
            seed: 92_130
        )
        XCTAssertThrowsError(try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .exact(mismatchedEvidence), destinationReceipt: nil
        ))

        let zoneAttempt = try XCTUnwrap(fixture.source.timeZone)
        let requiredSite = try WorkspaceEntityRevisionV1(
            identity: .init(kind: .site, id: fixture.siteID),
            revision: zoneAttempt.expectedSiteRevision
        )
        let zoneEvidence = try restoreMutationEvidence(
            workspaceID: fixture.source.sourceWorkspaceID,
            mutationID: zoneAttempt.mutationID,
            command: .updateSiteTimeZone(zoneAttempt.command),
            expectedEntities: [requiredSite, extra],
            committedAt: zoneAttempt.committedAt,
            seed: 92_140
        )
        let zone = try XCTUnwrap(CheckRunnerBeginMutationCorrespondenceV1.timeZone(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .exact(zoneEvidence), destinationReceipt: nil
        ))
        try zone.validate(source: fixture.source, binding: binding, map: map)
        let staleSiteEvidence = try restoreMutationEvidence(
            workspaceID: fixture.source.sourceWorkspaceID,
            mutationID: zoneAttempt.mutationID,
            command: .updateSiteTimeZone(zoneAttempt.command),
            expectedEntities: [try .init(
                identity: requiredSite.identity,
                revision: zoneAttempt.expectedSiteRevision - 1
            ), extra],
            committedAt: zoneAttempt.committedAt,
            seed: 92_150
        )
        XCTAssertThrowsError(try CheckRunnerBeginMutationCorrespondenceV1.timeZone(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .exact(staleSiteEvidence), destinationReceipt: nil
        ))
    }

    func testBeginMutationFreshSourceReadSeparatesSameKeyCandidateFromExactEquality() throws {
        let fixture = try restoreBindingFixture(seed: 2_200, recheck: true, includesTimeZone: false)
        let sameMap = try fixture.map(mode: .sameWorkspace)
        let sameBinding = try restoreMutationBinding(fixture, map: sameMap)
        let sourceEvidence = try restoreMutationEvidence(
            workspaceID: fixture.source.sourceWorkspaceID,
            mutationID: fixture.source.recordMutationID,
            command: .createCheckDraft(fixture.source.recordCommand),
            expectedEntities: fixture.source.recordExpectedEntityRevisions,
            committedAt: fixture.source.recordCommittedAt,
            seed: 92_200,
            correlationID: restoreBeginID(92_201)
        )
        let sameAbsent = try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: sameBinding, map: sameMap,
            expectedSourceEvidence: .absent, destinationReceipt: nil
        )
        XCTAssertEqual(try sameAbsent.validateFreshSourceRead(nil), .expectationMatched)
        XCTAssertEqual(try sameAbsent.validateFreshSourceRead(sourceEvidence), .sameKeyPresentCandidate)

        let sameExact = try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: sameBinding, map: sameMap,
            expectedSourceEvidence: .exact(sourceEvidence),
            destinationReceipt: try .init(evidence: sourceEvidence)
        )
        XCTAssertEqual(try sameExact.validateFreshSourceRead(sourceEvidence), .expectationMatched)
        XCTAssertThrowsError(try sameExact.validateFreshSourceRead(nil))
        let drift = try restoreMutationEvidence(
            workspaceID: fixture.source.sourceWorkspaceID,
            mutationID: fixture.source.recordMutationID,
            command: .createCheckDraft(fixture.source.recordCommand),
            expectedEntities: fixture.source.recordExpectedEntityRevisions,
            committedAt: fixture.source.recordCommittedAt,
            seed: 92_210,
            correlationID: restoreBeginID(92_211)
        )
        XCTAssertThrowsError(try sameExact.validateFreshSourceRead(drift))

        let forkMap = try fixture.map(mode: .fork)
        let forkBinding = try restoreMutationBinding(fixture, map: forkMap)
        let forkAbsent = try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: forkBinding, map: forkMap,
            expectedSourceEvidence: .absent, destinationReceipt: nil
        )
        XCTAssertEqual(try forkAbsent.validateFreshSourceRead(nil), .expectationMatched)
        XCTAssertThrowsError(try forkAbsent.validateFreshSourceRead(sourceEvidence))
        let forkExact = try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: forkBinding, map: forkMap,
            expectedSourceEvidence: .exact(sourceEvidence), destinationReceipt: nil
        )
        XCTAssertEqual(try forkExact.validateFreshSourceRead(sourceEvidence), .expectationMatched)
        let foreign = try restoreMutationEvidence(
            workspaceID: fixture.source.sourceWorkspaceID,
            mutationID: try MutationIDV1(rawValue: restoreBeginID(92_220)),
            command: .createCheckDraft(fixture.source.recordCommand),
            expectedEntities: fixture.source.recordExpectedEntityRevisions,
            committedAt: fixture.source.recordCommittedAt,
            seed: 92_220
        )
        XCTAssertThrowsError(try forkAbsent.validateFreshSourceRead(foreign))
    }

    func testBeginMutationDestinationEvidenceAuthenticatesEveryReferenceField() throws {
        let fixture = try restoreBindingFixture(seed: 2_300, recheck: true, includesTimeZone: true)
        let map = try fixture.map(mode: .fork)
        let binding = try restoreMutationBinding(fixture, map: map)
        let destinationEvidence = try restoreMutationEvidence(
            workspaceID: binding.destinationWorkspaceID,
            mutationID: binding.recordMutationID,
            command: .createCheckDraft(binding.recordCommand),
            expectedEntities: fixture.source.recordExpectedEntityRevisions,
            committedAt: binding.recordCommittedAt,
            seed: 92_300,
            sourceKind: .localRecovery,
            correlationID: restoreBeginID(92_301)
        )
        let correspondence = try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .absent,
            destinationReceipt: try .init(evidence: destinationEvidence)
        )
        try correspondence.validateDestinationEvidence(destinationEvidence)
        XCTAssertEqual(correspondence.destinationReceipt?.sourceKind, .localRecovery)
        XCTAssertEqual(destinationEvidence.envelope.correlationID, restoreBeginID(92_301))

        let differentReceipt = try restoreMutationEvidence(
            workspaceID: binding.destinationWorkspaceID,
            mutationID: binding.recordMutationID,
            command: .createCheckDraft(binding.recordCommand),
            expectedEntities: fixture.source.recordExpectedEntityRevisions,
            committedAt: binding.recordCommittedAt,
            seed: 92_310,
            sourceKind: .importedHistory,
            correlationID: restoreBeginID(92_311)
        )
        XCTAssertThrowsError(try correspondence.validateDestinationEvidence(differentReceipt))
        let zoneEvidence = try restoreMutationEvidence(
            workspaceID: binding.destinationWorkspaceID,
            mutationID: try XCTUnwrap(binding.timeZoneMutationID),
            command: .updateSiteTimeZone(try XCTUnwrap(binding.timeZoneCommand)),
            expectedEntities: [try .init(
                identity: .init(kind: .site, id: fixture.siteID),
                revision: try XCTUnwrap(fixture.source.timeZone).expectedSiteRevision
            )],
            committedAt: try XCTUnwrap(binding.timeZoneCommittedAt),
            seed: 92_320
        )
        XCTAssertThrowsError(try correspondence.validateDestinationEvidence(zoneEvidence))
    }

    func testBeginMutationTimeZoneAbsenceRejectsDiscardedProvidedHistory() throws {
        let withoutZone = try restoreBindingFixture(seed: 2_400, recheck: false, includesTimeZone: false)
        let map = try withoutZone.map(mode: .sameWorkspace)
        let binding = try restoreMutationBinding(withoutZone, map: map)
        XCTAssertNil(try CheckRunnerBeginMutationCorrespondenceV1.timeZone(
            source: withoutZone.source, binding: binding, map: map,
            expectedSourceEvidence: .absent, destinationReceipt: nil
        ))

        let unrelated = try restoreBeginFixture(seed: 92_400).evidence
        XCTAssertThrowsError(try CheckRunnerBeginMutationCorrespondenceV1.timeZone(
            source: withoutZone.source, binding: binding, map: map,
            expectedSourceEvidence: .exact(unrelated), destinationReceipt: nil
        ))
        XCTAssertThrowsError(try CheckRunnerBeginMutationCorrespondenceV1.timeZone(
            source: withoutZone.source, binding: binding, map: map,
            expectedSourceEvidence: .absent,
            destinationReceipt: try .init(evidence: unrelated)
        ))
    }

    func testBeginMutationClosedDecodeRejectsHostileRoleKeysHashesTimesAndReferences() throws {
        let fixture = try restoreBindingFixture(seed: 2_500, recheck: true, includesTimeZone: false)
        let map = try fixture.map(mode: .sameWorkspace)
        let binding = try restoreMutationBinding(fixture, map: map)
        let evidence = try restoreMutationEvidence(
            workspaceID: fixture.source.sourceWorkspaceID,
            mutationID: fixture.source.recordMutationID,
            command: .createCheckDraft(fixture.source.recordCommand),
            expectedEntities: fixture.source.recordExpectedEntityRevisions,
            committedAt: fixture.source.recordCommittedAt,
            seed: 92_500
        )
        let correspondence = try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .exact(evidence),
            destinationReceipt: try .init(evidence: evidence)
        )
        let base = try restoreBeginObject(correspondence)
        for mutation in [
            { (object: inout [String: Any]) in object["future"] = true },
            { (object: inout [String: Any]) in object["schemaVersion"] = 2 },
            { (object: inout [String: Any]) in object["role"] = "UNKNOWN" },
            { (object: inout [String: Any]) in object["sourceCommandCanonicalSHA256"] = String(repeating: "A", count: 64) },
            { (object: inout [String: Any]) in object["destinationCommandCanonicalSHA256"] = String(repeating: "0", count: 64) },
            { (object: inout [String: Any]) in object["frozenCommittedAt"] = -1 },
        ] as [(inout [String: Any]) -> Void] {
            var hostile = base
            mutation(&hostile)
            assertRestoreBeginDecodeFails(CheckRunnerBeginMutationCorrespondenceV1.self, hostile)
        }
        var wrongReference = base
        var reference = try XCTUnwrap(wrongReference["destinationReceipt"] as? [String: Any])
        reference["sourceKind"] = MutationSourceKindV1.localRecovery.rawValue
        wrongReference["destinationReceipt"] = reference
        assertRestoreBeginDecodeFails(CheckRunnerBeginMutationCorrespondenceV1.self, wrongReference)
    }

    func testParentChildCorrespondenceCanonicalizesDependencyUnionAndDigestInEveryMode() throws {
        let fixture = try restoreBindingFixture(seed: 2_600, recheck: true, includesTimeZone: true)
        for mode in [CheckRunnerRestoreModeV1.sameWorkspace, .crossWorkspaceReplace, .fork] {
            let map = try fixture.map(mode: mode)
            let binding = try restoreMutationBinding(fixture, map: map)
            let record = try CheckRunnerBeginMutationCorrespondenceV1.record(
                source: fixture.source, binding: binding, map: map,
                expectedSourceEvidence: .absent, destinationReceipt: nil
            )
            let timeZone = try CheckRunnerBeginMutationCorrespondenceV1.timeZone(
                source: fixture.source, binding: binding, map: map,
                expectedSourceEvidence: .absent, destinationReceipt: nil
            )
            let correspondence = try CheckRunnerParentChildRestoreCorrespondenceV1(
                source: fixture.source, binding: binding, map: map,
                recordBegin: record, timeZoneBegin: timeZone,
                childCheckpointPairs: [], childTargetReceiptPairs: []
            )
            try correspondence.validate(source: fixture.source)
            XCTAssertEqual(correspondence.mode, mode)
            XCTAssertEqual(correspondence.identityPairs, map.pairs)
            XCTAssertEqual(correspondence.dependencies, binding.recordMappedDependencyBasis)
            XCTAssertEqual(correspondence.dependencies.filter {
                $0.sourceIdentity.kind == .site && $0.sourceIdentity.id == fixture.siteID
            }.count, 1)
            XCTAssertEqual(correspondence.sourceAttemptSHA256, try FieldDraftCanonicalCodecV1.sha256(fixture.source))
            XCTAssertEqual(correspondence.destinationBindingSHA256, try binding.canonicalSHA256())
            let bytes = try FieldDraftCanonicalCodecV1.encode(correspondence)
            let decoded = try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerParentChildRestoreCorrespondenceV1.self, from: bytes
            )
            XCTAssertEqual(decoded, correspondence)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), bytes)
        }
    }

    func testParentChildCorrespondenceRejectsParallelMapBindingSourceAndDigestDrift() throws {
        let fixture = try restoreBindingFixture(seed: 2_700, recheck: true, includesTimeZone: true)
        let map = try fixture.map(mode: .fork)
        let binding = try restoreMutationBinding(fixture, map: map)
        let record = try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .absent, destinationReceipt: nil
        )
        let timeZone = try CheckRunnerBeginMutationCorrespondenceV1.timeZone(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .absent, destinationReceipt: nil
        )
        let correspondence = try CheckRunnerParentChildRestoreCorrespondenceV1(
            source: fixture.source, binding: binding, map: map,
            recordBegin: record, timeZoneBegin: timeZone,
            childCheckpointPairs: [], childTargetReceiptPairs: []
        )
        let base = try restoreBeginObject(correspondence)
        for change in [
            { (object: inout [String: Any]) in object["future"] = true },
            { (object: inout [String: Any]) in object["mappingSHA256"] = String(repeating: "0", count: 64) },
            { (object: inout [String: Any]) in object["sourceAttemptSHA256"] = String(repeating: "1", count: 64) },
            { (object: inout [String: Any]) in object["destinationBindingSHA256"] = String(repeating: "2", count: 64) },
            { (object: inout [String: Any]) in object["mode"] = CheckRunnerRestoreModeV1.sameWorkspace.rawValue },
            { (object: inout [String: Any]) in
                var pairs = object["identityPairs"] as! [[String: Any]]
                pairs.removeLast()
                object["identityPairs"] = pairs
            },
            { (object: inout [String: Any]) in
                var dependencies = object["dependencies"] as! [[String: Any]]
                dependencies.append(dependencies[0])
                object["dependencies"] = dependencies
            },
        ] as [(inout [String: Any]) -> Void] {
            var hostile = base
            change(&hostile)
            assertRestoreBeginDecodeFails(CheckRunnerParentChildRestoreCorrespondenceV1.self, hostile)
        }
        let foreign = try restoreBindingFixture(seed: 2_710, recheck: true, includesTimeZone: true).source
        XCTAssertThrowsError(try correspondence.validate(source: foreign))
    }

    func testParentChildCorrespondencePhaseValidationIsStrictlyShapeBased() throws {
        let fixture = try restoreBindingFixture(seed: 2_800, recheck: true, includesTimeZone: true)
        let map = try fixture.map(mode: .crossWorkspaceReplace)
        let binding = try restoreMutationBinding(fixture, map: map)
        let preparedRecord = try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .absent, destinationReceipt: nil
        )
        let preparedZone = try CheckRunnerBeginMutationCorrespondenceV1.timeZone(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .absent, destinationReceipt: nil
        )
        let prepared = try CheckRunnerParentChildRestoreCorrespondenceV1(
            source: fixture.source, binding: binding, map: map,
            recordBegin: preparedRecord, timeZoneBegin: preparedZone,
            childCheckpointPairs: [], childTargetReceiptPairs: []
        )
        try prepared.validate(phase: .prepared)
        XCTAssertThrowsError(try prepared.validate(phase: .bound))

        let recordEvidence = try restoreMutationEvidence(
            workspaceID: binding.destinationWorkspaceID, mutationID: binding.recordMutationID,
            command: .createCheckDraft(binding.recordCommand),
            expectedEntities: fixture.source.recordExpectedEntityRevisions,
            committedAt: binding.recordCommittedAt, seed: 92_800
        )
        let zoneAttempt = try XCTUnwrap(fixture.source.timeZone)
        let zoneEvidence = try restoreMutationEvidence(
            workspaceID: binding.destinationWorkspaceID,
            mutationID: try XCTUnwrap(binding.timeZoneMutationID),
            command: .updateSiteTimeZone(try XCTUnwrap(binding.timeZoneCommand)),
            expectedEntities: [try .init(
                identity: .init(kind: .site, id: fixture.siteID),
                revision: zoneAttempt.expectedSiteRevision
            )],
            committedAt: try XCTUnwrap(binding.timeZoneCommittedAt), seed: 92_810
        )
        let boundRecord = try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .absent,
            destinationReceipt: try .init(evidence: recordEvidence)
        )
        let boundZone = try CheckRunnerBeginMutationCorrespondenceV1.timeZone(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .absent,
            destinationReceipt: try .init(evidence: zoneEvidence)
        )
        let bound = try CheckRunnerParentChildRestoreCorrespondenceV1(
            source: fixture.source, binding: binding, map: map,
            recordBegin: boundRecord, timeZoneBegin: boundZone,
            childCheckpointPairs: [], childTargetReceiptPairs: []
        )
        try bound.validate(phase: .bound)
        XCTAssertThrowsError(try bound.validate(phase: .prepared))
    }

    func testChildCheckpointCorrespondenceDerivesExactProjectionAndPreservesHistoricalRevision() throws {
        let fixture = try restoreBindingFixture(seed: 2_900, recheck: false, includesTimeZone: false)
        let sourceDraftID = restoreBeginID(92_900)
        let sourceMutationID = try MutationIDV1(rawValue: restoreBeginID(92_901))
        let secondMutationID = try MutationIDV1(rawValue: restoreBeginID(92_904))
        let destinationDraftID = sourceDraftID
        let destinationMutationID = sourceMutationID
        let map = try restoreMutationMap(
            fixture: fixture, mode: .crossWorkspaceReplace,
            additions: [
                (.childDraft, sourceDraftID, destinationDraftID),
                (.checkpointMutation, sourceMutationID.rawValue, destinationMutationID.rawValue),
                (.checkpointMutation, secondMutationID.rawValue, secondMutationID.rawValue),
            ]
        )
        let source = try restoreCheckpoint(
            workspaceID: fixture.source.sourceWorkspaceID, draftID: sourceDraftID,
            mutationID: sourceMutationID, draftRevision: 7, seed: 92_910
        )
        let destination = try restoreCheckpoint(
            workspaceID: WorkspaceID(rawValue: map.destinationWorkspaceID), draftID: destinationDraftID,
            mutationID: destinationMutationID, draftRevision: 7, seed: 92_920
        )
        let pair = try CheckRunnerChildCheckpointCorrespondenceV1(
            source: source, destination: destination, map: map
        )
        XCTAssertEqual(pair.sourceDraftRevision, 7)
        XCTAssertEqual(pair.destinationDraftRevision, 7)
        XCTAssertEqual(pair.sourceCheckpointSHA256, source.checkpointSHA256)
        XCTAssertEqual(pair.destinationCheckpointSHA256, destination.checkpointSHA256)
        XCTAssertNotEqual(pair.sourceCheckpointSHA256, pair.destinationCheckpointSHA256)
        try pair.validate(source: source, destination: destination, map: map)

        let secondSource = try restoreCheckpoint(
            workspaceID: fixture.source.sourceWorkspaceID, draftID: sourceDraftID,
            mutationID: secondMutationID, draftRevision: 8, seed: 92_930
        )
        let secondDestination = try restoreCheckpoint(
            workspaceID: WorkspaceID(rawValue: map.destinationWorkspaceID), draftID: destinationDraftID,
            mutationID: secondMutationID, draftRevision: 8, seed: 92_940
        )
        let secondPair = try CheckRunnerChildCheckpointCorrespondenceV1(
            source: secondSource, destination: secondDestination, map: map
        )
        let binding = try restoreMutationBinding(fixture, map: map)
        let record = try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .absent, destinationReceipt: nil
        )
        let whole = try CheckRunnerParentChildRestoreCorrespondenceV1(
            source: fixture.source, binding: binding, map: map,
            recordBegin: record, timeZoneBegin: nil,
            childCheckpointPairs: [secondPair, pair], childTargetReceiptPairs: []
        )
        XCTAssertEqual(whole.childCheckpointPairs.map(\.sourceDraftRevision), [7, 8])
        try whole.validate(source: fixture.source)

        let wrongRevision = try restoreCheckpoint(
            workspaceID: WorkspaceID(rawValue: map.destinationWorkspaceID), draftID: destinationDraftID,
            mutationID: destinationMutationID, draftRevision: 8, seed: 92_920
        )
        XCTAssertThrowsError(try CheckRunnerChildCheckpointCorrespondenceV1(
            source: source, destination: wrongRevision, map: map
        ))
        var hostile = try restoreBeginObject(pair)
        hostile["sourceCheckpointSHA256"] = String(repeating: "0", count: 64)
        let decoded = try FieldDraftCanonicalCodecV1.decode(
            CheckRunnerChildCheckpointCorrespondenceV1.self,
            from: restoreBeginJSONData(hostile)
        )
        XCTAssertThrowsError(try decoded.validate(source: source, destination: destination, map: map))
    }

    func testChildTargetReceiptCorrespondenceBindsResultDigestAndOriginalTimes() throws {
        let fixture = try restoreBindingFixture(seed: 3_000, recheck: false, includesTimeZone: false)
        let sourceDraftID = restoreBeginID(93_000)
        let destinationDraftID = sourceDraftID
        let sourceCommitID = restoreBeginID(93_002)
        let destinationCommitID = sourceCommitID
        let sourceTargetID = try MutationIDV1(rawValue: restoreBeginID(93_004))
        let destinationTargetID = sourceTargetID
        let map = try restoreMutationMap(
            fixture: fixture, mode: .crossWorkspaceReplace,
            additions: [
                (.childDraft, sourceDraftID, destinationDraftID),
                (.commitReceipt, sourceCommitID, destinationCommitID),
                (.commitTargetMutation, sourceTargetID.rawValue, destinationTargetID.rawValue),
            ]
        )
        let committedAt = Date(timeIntervalSince1970: 1_789_333_444.555)
        let destinationCommittedAt = committedAt.addingTimeInterval(60)
        let sourceTarget = try restoreMutationEvidence(
            workspaceID: fixture.source.sourceWorkspaceID, mutationID: sourceTargetID,
            command: .createCheckDraft(fixture.source.recordCommand),
            expectedEntities: fixture.source.recordExpectedEntityRevisions,
            committedAt: committedAt, seed: 93_010
        ).receipt
        let destinationTarget = try restoreMutationEvidence(
            workspaceID: WorkspaceID(rawValue: map.destinationWorkspaceID), mutationID: destinationTargetID,
            command: .createCheckDraft(fixture.source.recordCommand),
            expectedEntities: fixture.source.recordExpectedEntityRevisions,
            committedAt: destinationCommittedAt, seed: 93_020
        ).receipt
        let sourceCommit = try restoreCommitReceipt(
            workspaceID: fixture.source.sourceWorkspaceID, draftID: sourceDraftID,
            receiptID: sourceCommitID, target: sourceTarget, seed: 93_030
        )
        let destinationCommit = try restoreCommitReceipt(
            workspaceID: WorkspaceID(rawValue: map.destinationWorkspaceID), draftID: destinationDraftID,
            receiptID: destinationCommitID, target: destinationTarget, seed: 93_040
        )
        let pair = try CheckRunnerChildTargetReceiptCorrespondenceV1(
            sourceCommitReceipt: sourceCommit, sourceTargetReceipt: sourceTarget,
            destinationCommitReceipt: destinationCommit, destinationTargetReceipt: destinationTarget,
            map: map
        )
        XCTAssertEqual(pair.sourceTargetResultSHA256, sourceTarget.resultSHA256)
        XCTAssertEqual(pair.destinationTargetResultSHA256, destinationTarget.resultSHA256)
        XCTAssertEqual(pair.sourceTargetCommittedAt, committedAt)
        XCTAssertEqual(pair.destinationTargetCommittedAt, destinationCommittedAt)
        XCTAssertNotEqual(pair.sourceTargetCommittedAt, pair.destinationTargetCommittedAt)
        XCTAssertNotEqual(pair.sourceCommitReceiptSHA256, sourceTarget.resultSHA256)
        try pair.validate(
            sourceCommitReceipt: sourceCommit, sourceTargetReceipt: sourceTarget,
            destinationCommitReceipt: destinationCommit, destinationTargetReceipt: destinationTarget,
            map: map
        )
        let binding = try restoreMutationBinding(fixture, map: map)
        let record = try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .absent, destinationReceipt: nil
        )
        let whole = try CheckRunnerParentChildRestoreCorrespondenceV1(
            source: fixture.source, binding: binding, map: map,
            recordBegin: record, timeZoneBegin: nil,
            childCheckpointPairs: [], childTargetReceiptPairs: [pair]
        )
        XCTAssertEqual(whole.childTargetReceiptPairs, [pair])
        try whole.validate(source: fixture.source)

        let wrongTime = try DraftCommitReceiptV1(
            receiptID: sourceCommit.receiptID, workspaceID: sourceCommit.workspaceID,
            draftID: sourceCommit.draftID, sagaID: sourceCommit.sagaID,
            commitPlanSHA256: sourceCommit.commitPlanSHA256,
            sagaEventSHA256Chain: sourceCommit.sagaEventSHA256Chain,
            targetMutationID: sourceCommit.targetMutationID,
            targetReceiptSHA256: sourceCommit.targetReceiptSHA256,
            consumedStageToContentID: sourceCommit.consumedStageToContentID,
            committedAt: committedAt.addingTimeInterval(1), mutationID: sourceCommit.mutationID
        )
        XCTAssertThrowsError(try CheckRunnerChildTargetReceiptCorrespondenceV1(
            sourceCommitReceipt: wrongTime, sourceTargetReceipt: sourceTarget,
            destinationCommitReceipt: destinationCommit, destinationTargetReceipt: destinationTarget,
            map: map
        ))

        let wrongLink = try DraftCommitReceiptV1(
            receiptID: sourceCommit.receiptID, workspaceID: sourceCommit.workspaceID,
            draftID: sourceCommit.draftID, sagaID: sourceCommit.sagaID,
            commitPlanSHA256: sourceCommit.commitPlanSHA256,
            sagaEventSHA256Chain: sourceCommit.sagaEventSHA256Chain,
            targetMutationID: sourceCommit.targetMutationID,
            targetReceiptSHA256: String(repeating: "0", count: 64),
            consumedStageToContentID: sourceCommit.consumedStageToContentID,
            committedAt: sourceCommit.committedAt, mutationID: sourceCommit.mutationID
        )
        XCTAssertThrowsError(try CheckRunnerChildTargetReceiptCorrespondenceV1(
            sourceCommitReceipt: wrongLink, sourceTargetReceipt: sourceTarget,
            destinationCommitReceipt: destinationCommit, destinationTargetReceipt: destinationTarget,
            map: map
        ))
    }

    func testParentChildCorrespondenceRejectsChildCollisionsAndClonePublishesNoOperationalValue() throws {
        let fixture = try restoreBindingFixture(seed: 3_100, recheck: false, includesTimeZone: false)
        let sourceDraftID = restoreBeginID(93_100)
        let destinationDraftID = sourceDraftID
        let sourceMutationID = try MutationIDV1(rawValue: restoreBeginID(93_102))
        let destinationMutationID = sourceMutationID
        let map = try restoreMutationMap(
            fixture: fixture, mode: .crossWorkspaceReplace,
            additions: [
                (.childDraft, sourceDraftID, destinationDraftID),
                (.checkpointMutation, sourceMutationID.rawValue, destinationMutationID.rawValue),
            ]
        )
        let binding = try restoreMutationBinding(fixture, map: map)
        let record = try CheckRunnerBeginMutationCorrespondenceV1.record(
            source: fixture.source, binding: binding, map: map,
            expectedSourceEvidence: .absent, destinationReceipt: nil
        )
        let sourceCheckpoint = try restoreCheckpoint(
            workspaceID: fixture.source.sourceWorkspaceID, draftID: sourceDraftID,
            mutationID: sourceMutationID, draftRevision: 5, seed: 93_110
        )
        let destinationCheckpoint = try restoreCheckpoint(
            workspaceID: WorkspaceID(rawValue: map.destinationWorkspaceID), draftID: destinationDraftID,
            mutationID: destinationMutationID, draftRevision: 5, seed: 93_120
        )
        let pair = try CheckRunnerChildCheckpointCorrespondenceV1(
            source: sourceCheckpoint, destination: destinationCheckpoint, map: map
        )
        XCTAssertThrowsError(try CheckRunnerParentChildRestoreCorrespondenceV1(
            source: fixture.source, binding: binding, map: map,
            recordBegin: record, timeZoneBegin: nil,
            childCheckpointPairs: [pair, pair], childTargetReceiptPairs: []
        ))

        let cloneIdentity = restoreMutationUncheckedIdentity(
            mode: .clone,
            sourceWorkspaceID: fixture.source.sourceWorkspaceID.rawValue,
            destinationWorkspaceID: restoreBeginID(93_130)
        )
        let sources = try fixture.map(mode: .sameWorkspace).pairs.map {
            try CheckRunnerRestoreIdentitySourceV1(kind: $0.kind, sourceID: $0.sourceID)
        }
        XCTAssertNil(try CheckRunnerParentChildRestoreCorrespondenceV1.make(
            identity: cloneIdentity, source: fixture.source, declaredSources: sources
        ))
    }
}

private func restoreMutationBinding(
    _ fixture: RestoreBindingFixture,
    map: CheckRunnerRestoreIdentityMapV1
) throws -> CheckRunnerDestinationBeginBindingV1 {
    try CheckRunnerDestinationBeginBindingV1(
        source: fixture.source,
        map: map,
        recordMappedDependencyBasis: fixture.recordBasis(targetPresent: false),
        timeZoneMappedDependencyBasis: fixture.source.timeZone == nil ? nil : [fixture.siteDependency()]
    )
}

private func restoreMutationEvidence(
    workspaceID: WorkspaceID,
    mutationID: MutationIDV1,
    command: WorkspaceCommandV1,
    expectedEntities: [WorkspaceEntityRevisionV1],
    committedAt: Date,
    seed: Int,
    sourceKind: MutationSourceKindV1 = .importedHistory,
    correlationID: UUID? = nil
) throws -> CheckRunnerBeginCommittedEvidenceV1 {
    let target: WorkspaceEntityIdentityV1
    let postImage: (UInt64, String) -> MutationPostImageV1
    switch command {
    case let .createCheckDraft(value):
        target = try .init(kind: .workflowRecord, id: value.recordID)
        postImage = { .workflowRecord(id: value.recordID, revision: $0, semanticSHA256: $1) }
    case let .updateSiteTimeZone(value):
        target = try .init(kind: .site, id: value.siteID)
        postImage = { .site(id: value.siteID, revision: $0, semanticSHA256: $1) }
    default:
        throw CheckRunnerRestoreBeginFailureV1.invalidEvidence
    }
    let beforeRevision = try XCTUnwrap(expectedEntities.first { $0.identity == target }?.revision)
    let before = try WorkspaceExpectedRevisionV1(
        workspaceID: workspaceID,
        generationID: restoreBeginID(seed + 1),
        writerInstanceID: restoreBeginID(seed + 2),
        workspaceRevision: 100,
        entityRevisions: expectedEntities
    )
    let envelope = try MutationEnvelopeV1(
        request: .init(mutationID: mutationID, expectedRevision: before, command: command),
        identity: .init(
            workspaceID: workspaceID,
            replicaID: ReplicaID(rawValue: restoreBeginID(seed + 3))
        ),
        sourceKind: sourceKind,
        contentDependencyIDs: ["pack:retained-v1"],
        correlationID: correlationID
    )
    let afterEntities = try expectedEntities.map { entry in
        try WorkspaceEntityRevisionV1(
            identity: entry.identity,
            revision: entry.identity == target ? beforeRevision + 1 : entry.revision
        )
    }
    let after = try MutationPortableExpectedRevisionV1(WorkspaceExpectedRevisionV1(
        workspaceID: workspaceID,
        generationID: before.generationID,
        writerInstanceID: before.writerInstanceID,
        workspaceRevision: before.workspaceRevision + 1,
        entityRevisions: afterEntities
    ))
    let semanticSHA256 = String(repeating: String(format: "%x", seed % 16), count: 64)
    let receipt = try MutationReceiptV1(
        identity: .init(
            workspaceID: workspaceID,
            replicaID: envelope.replicaID,
            localSequence: UInt64(seed + 1)
        ),
        envelope: envelope,
        resultingRevision: after,
        postImages: [postImage(beforeRevision + 1, semanticSHA256)],
        committedAt: committedAt
    )
    return try CheckRunnerBeginCommittedEvidenceV1(envelope: envelope, receipt: receipt)
}

private func restoreMutationMap(
    fixture: RestoreBindingFixture,
    mode: CheckRunnerRestoreModeV1,
    additions: [(CheckRunnerRestoreIdentityKindV1, UUID, UUID)]
) throws -> CheckRunnerRestoreIdentityMapV1 {
    let base = try fixture.map(mode: mode)
    let extras = try additions.map {
        try CheckRunnerRestoreIdentityPairV1(kind: $0.0, sourceID: $0.1, destinationID: $0.2)
    }
    return try CheckRunnerRestoreIdentityMapV1(
        mode: mode,
        sourceWorkspaceID: base.sourceWorkspaceID,
        destinationWorkspaceID: base.destinationWorkspaceID,
        pairs: base.pairs + extras
    )
}

private func restoreCheckpoint(
    workspaceID: WorkspaceID,
    draftID: UUID,
    mutationID: MutationIDV1,
    draftRevision: UInt64,
    seed: Int
) throws -> FieldDraftCheckpointV1 {
    try FieldDraftCheckpointV1(
        draftID: draftID,
        workspaceID: workspaceID,
        scope: .init(scopeKind: "check-runner-child", stableComponentIDs: [String(seed)]),
        purpose: .repetitiveCapture,
        codec: .init(
            codecID: "check-runner-child-v1",
            codecVersion: 1,
            releaseSHA256: String(repeating: "c", count: 64)
        ),
        baseCanonicalRevision: 4,
        draftRevision: draftRevision,
        payloadData: Data("payload-\(seed)".utf8),
        stageIDs: [],
        resumeAnchor: .init(sectionID: "wide"),
        state: .recoveryRequired,
        updatedAt: Date(timeIntervalSince1970: Double(1_789_400_000 + seed)),
        mutationID: mutationID
    )
}

private func restoreCommitReceipt(
    workspaceID: WorkspaceID,
    draftID: UUID,
    receiptID: UUID,
    target: MutationReceiptV1,
    seed: Int
) throws -> DraftCommitReceiptV1 {
    try DraftCommitReceiptV1(
        receiptID: receiptID,
        workspaceID: workspaceID,
        draftID: draftID,
        sagaID: restoreBeginID(seed + 1),
        commitPlanSHA256: String(repeating: "d", count: 64),
        sagaEventSHA256Chain: [String(repeating: "e", count: 64)],
        targetMutationID: target.mutationID,
        targetReceiptSHA256: target.resultSHA256,
        consumedStageToContentID: [:],
        committedAt: target.committedAt,
        mutationID: try MutationIDV1(rawValue: restoreBeginID(seed + 2))
    )
}

private func restoreMutationUncheckedIdentity(
    mode: BackupRestoreMode,
    sourceWorkspaceID: UUID,
    destinationWorkspaceID: UUID
) -> RestoreIdentityV1 {
    let pointer = RestorePointerIdentityV1(
        generationID: restoreBeginID(93_900),
        generationManifestSHA256: String(repeating: "f", count: 64),
        workspaceID: destinationWorkspaceID,
        replicaID: restoreBeginID(93_901)
    )
    return RestoreIdentityV1(
        mode: mode,
        source: .init(workspaceID: sourceWorkspaceID, replicaID: restoreBeginID(93_902)),
        oldPointer: pointer,
        targetPointer: pointer,
        recordIdentityDisposition: .preserve
    )
}
