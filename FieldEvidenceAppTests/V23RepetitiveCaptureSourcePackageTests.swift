import Foundation
import CoreFoundation
import XCTest

@testable import FieldEvidenceApp

final class V23RepetitiveCaptureSourcePackageTests: XCTestCase {
    func testOrdinaryDirectoryPackageIsValidatedAndBoundToExactCanonicalMembers() throws {
        // Exercise both the bulk-copy and scalar-escape paths through the
        // shipping renderer, including normalization before either path.
        let stringCases: [(String, String)] = [
            ("", "\"\""), ("receipt+/=", "\"receipt+/=\""),
            ("e\u{301} / 🧭", "\"é / 🧭\""),
            ("e\u{301}\n\"\\", "\"é\\n\\\"\\\\\""),
            ("\u{7f}\u{2028}\u{2029}", "\"\u{7f}\u{2028}\u{2029}\""),
        ]
        for (raw, expected) in stringCases {
            XCTAssertEqual(try CanonicalJSONV1.encode(.string(raw)), Data(expected.utf8))
        }
        for scalarValue in UInt32(0)..<UInt32(32) {
            let scalar = try XCTUnwrap(UnicodeScalar(scalarValue))
            let shortEscapes: [UInt32: String] = [8: "\\b", 9: "\\t", 10: "\\n", 12: "\\f", 13: "\\r"]
            let escaped = shortEscapes[scalarValue] ?? String(format: "\\u%04x", scalarValue)
            XCTAssertEqual(try CanonicalJSONV1.encode(.string("a" + String(scalar) + "é")),
                           Data(("\"a" + escaped + "é\"").utf8))
        }
        let largePayload = Data(repeating: 0xfb, count: 393_216).base64EncodedString()
        XCTAssertEqual(largePayload.utf8.count, 524_288)
        XCTAssertEqual(try CanonicalJSONV1.encode(.string(largePayload)),
                       Data(("\"" + largePayload + "\"").utf8))
        XCTAssertEqual(try CanonicalJSONV1.encode(.string(largePayload + "\n")),
                       Data(("\"" + largePayload + "\\n\"").utf8))
        let transportValues: [Any] = [true, false, NSNull(), -2, [Any]()]
        let transportObject: [String: Any] = [
            "recordID": 1, "recordedAt": "e\u{301}", "values": transportValues,
        ]
        XCTAssertEqual(try RepetitiveCaptureSourcePackageFixture.canonicalJSONData(transportObject),
                       Data("{\"recordID\":1,\"recordedAt\":\"é\",\"values\":[true,false,null,-2,[]]}".utf8))
        XCTAssertThrowsError(try RepetitiveCaptureSourcePackageFixture.canonicalJSONData(1.5))

        let fixture = try RepetitiveCaptureSourcePackageFixture()
        defer { fixture.removePackages() }

        let package = try fixture.validatedPackage()
        let c05ManifestData = try fixture.memberData("manifest.json")
        let manifest = try BackupCanonicalDecoderV1().decodeManifest(c05ManifestData)
        XCTAssertEqual(manifest.backupSchemaVersion, 4)
        XCTAssertEqual(manifest.source.persistentSchemaVersion,
                       C05RoundSessionBackupEnrollmentV1.persistentSchemaVersion)
        XCTAssertEqual(manifest.source.recordsSchemaVersion,
                       C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion)
        XCTAssertEqual(try BackupCanonicalEncoderV1().encodeManifest(manifest).data, c05ManifestData)
        let c05ManifestObject = try XCTUnwrap(JSONSerialization.jsonObject(with: c05ManifestData) as? [String: Any])
        XCTAssertEqual(try RepetitiveCaptureSourcePackageFixture.canonicalJSONData(c05ManifestObject), c05ManifestData)
        for (persistentVersion, recordsVersion) in [(44, 44), (45, 43), (45, 45), (46, 44)] {
            let changedSource = V4BackupSourceV1(appBuild: manifest.source.appBuild,
                appVersion: manifest.source.appVersion, persistentSchemaVersion: persistentVersion,
                replicaID: manifest.source.replicaID, recordsSchemaVersion: recordsVersion,
                sourceGenerationID: manifest.source.sourceGenerationID, workspaceID: manifest.source.workspaceID)
            let changed = V4BackupManifestV1(backupSchemaVersion: manifest.backupSchemaVersion,
                consumedEvaluationRootIDs: manifest.consumedEvaluationRootIDs,
                declaredPayloadByteCount: manifest.declaredPayloadByteCount, entries: manifest.entries,
                exportedAt: manifest.exportedAt, packs: manifest.packs, source: changedSource)
            XCTAssertThrowsError(try BackupCanonicalEncoderV1().encodeManifest(changed))
            let invalidPackage = try fixture.package(named: "invalid-c05-pair-\(persistentVersion)-\(recordsVersion)")
            var invalidObject = c05ManifestObject
            var invalidSource = try XCTUnwrap(invalidObject["source"] as? [String: Any])
            invalidSource["persistentSchemaVersion"] = persistentVersion
            invalidSource["recordsSchemaVersion"] = recordsVersion
            invalidObject["source"] = invalidSource
            try RepetitiveCaptureSourcePackageFixture.canonicalJSONData(invalidObject).write(
                to: invalidPackage.appendingPathComponent("manifest.json"), options: .atomic)
            XCTAssertThrowsError(try ValidatedRepetitiveCaptureSourcePackageV2.validate(
                stagedPackageURL: invalidPackage, using: BackupPackageValidatorV1()))
            try FileManager.default.removeItem(at: invalidPackage)
        }
        let canonicalRecords = try BackupCanonicalEncoderV1().encodeRecords(package.records).data
        XCTAssertEqual(try fixture.memberData("records.json"), canonicalRecords)
        let canonicalDecoder = BackupCanonicalDecoderV1()
        let decodedWithFacts = try canonicalDecoder.decodeRecordsWithFacts(canonicalRecords)
        XCTAssertEqual(decodedWithFacts.records, package.records)
        XCTAssertEqual(try canonicalDecoder.decodeRecords(canonicalRecords), decodedWithFacts.records)
        XCTAssertEqual(try BackupCanonicalEncoderV1().encodeRecords(decodedWithFacts.records).data,
                       canonicalRecords)
        let canonicalFacts = decodedWithFacts.facts
        let canonicalDescriptor = try XCTUnwrap(canonicalFacts.descriptor(matching: package.records))
        XCTAssertEqual(canonicalDescriptor.sha256, CanonicalJSONV1.sha256(canonicalRecords))
        XCTAssertEqual(canonicalDescriptor.byteCount, canonicalRecords.count)
        XCTAssertEqual(canonicalFacts.records(matching: package.records), package.records)
        XCTAssertEqual(try canonicalDecoder.canonicalRoundTripRecords(package.records,
                       reusing: canonicalFacts), package.records)
        XCTAssertEqual(try canonicalDecoder.canonicalRoundTripRecords(package.records), package.records)

        // A change outside the six reused families cannot borrow their proof.
        // Use ordinary Codable transport only to build a different typed value.
        let factsTransport = try JSONEncoder.canonicalV1.encode(package.records)
        XCTAssertEqual(try JSONDecoder.canonicalV1.decode(V4BackupRecordsV1.self, from: factsTransport),
                       package.records)
        var changedFactsObject = try XCTUnwrap(JSONSerialization.jsonObject(with: factsTransport)
                                              as? [String: Any])
        let unrelatedSite = V4BackupSiteDTO(id: RepetitiveCaptureSourcePackageFixture.id(99_001),
            schemaVersion: 1, label: "Unrelated site", address: nil, timeZoneID: "America/New_York",
            createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 1_000))
        changedFactsObject["sites"] = try JSONSerialization.jsonObject(
            with: JSONEncoder.canonicalV1.encode([unrelatedSite]))
        let changedUnrelatedRecords = try JSONDecoder.canonicalV1.decode(V4BackupRecordsV1.self,
            from: JSONSerialization.data(withJSONObject: changedFactsObject))
        XCTAssertEqual(changedUnrelatedRecords.roundSessions, package.records.roundSessions)
        XCTAssertEqual(changedUnrelatedRecords.mutationHistory, package.records.mutationHistory)
        XCTAssertNil(canonicalFacts.records(matching: changedUnrelatedRecords))
        XCTAssertNil(canonicalFacts.descriptor(matching: changedUnrelatedRecords))
        XCTAssertEqual(try canonicalDecoder.canonicalRoundTripRecords(changedUnrelatedRecords,
                       reusing: canonicalFacts), changedUnrelatedRecords)
        XCTAssertEqual(try canonicalDecoder.canonicalRoundTripRecords(changedUnrelatedRecords),
                       changedUnrelatedRecords)
        changedFactsObject.removeValue(forKey: "mutationHistory")
        let missingHistoryRecords = try JSONDecoder.canonicalV1.decode(V4BackupRecordsV1.self,
            from: JSONSerialization.data(withJSONObject: changedFactsObject))
        XCTAssertNil(canonicalFacts.records(matching: missingHistoryRecords))
        XCTAssertNil(canonicalFacts.descriptor(matching: missingHistoryRecords))
        XCTAssertThrowsError(try canonicalDecoder.canonicalRoundTripRecords(missingHistoryRecords,
                             reusing: canonicalFacts))
        XCTAssertThrowsError(try canonicalDecoder.canonicalRoundTripRecords(missingHistoryRecords))

        let realValidation = try BackupPackageValidatorV1().validateWithCanonicalFacts(
            stagedPackageURL: package.validatedPackage.stagedPackageURL)
        XCTAssertEqual(realValidation.package, package.validatedPackage)
        let validatedDescriptor = try XCTUnwrap(realValidation.recordsFacts.descriptor(
            matching: realValidation.package.records))
        let recordsEntry = try XCTUnwrap(realValidation.package.manifest.entries.first {
            $0.path == "records.json"
        })
        let memberDescriptor = try XCTUnwrap(realValidation.package.members.descriptors["records.json"])
        XCTAssertEqual(validatedDescriptor.sha256, package.recordsJSONSHA256)
        XCTAssertEqual(validatedDescriptor.sha256, recordsEntry.sha256)
        XCTAssertEqual(validatedDescriptor.byteCount, recordsEntry.byteCount)
        XCTAssertEqual(validatedDescriptor.sha256, memberDescriptor.sha256)
        XCTAssertEqual(Int64(validatedDescriptor.byteCount), memberDescriptor.byteCount)
        let unchangedMutation = try fixture.validatedPackage { _ in }
        XCTAssertEqual(unchangedMutation.records, package.records)
        XCTAssertEqual(unchangedMutation.recordsJSONSHA256, package.recordsJSONSHA256)
        XCTAssertEqual(try fixture.memberData("records.json"), canonicalRecords)

        XCTAssertEqual(package.source.workspaceID, fixture.workspaceID.rawValue)
        XCTAssertEqual(package.source.persistentSchemaVersion, 45)
        XCTAssertEqual(package.source.recordsSchemaVersion, 44)
        XCTAssertEqual(package.records.roundSessions, fixture.rounds)
        XCTAssertEqual(package.records.fieldDrafts.count, fixture.checkpoints.count)
        XCTAssertEqual(package.records.mutationHistory, fixture.history)
        XCTAssertTrue(package.records.accessibleDocumentAssessments.isEmpty)
        XCTAssertTrue(package.records.surveyDefinitions.isEmpty && package.records.guidedSurveys.isEmpty)
        XCTAssertTrue(package.records.schedules.isEmpty && package.records.plans.isEmpty
            && package.records.placementPoses.isEmpty)
        let stock = try XCTUnwrap(package.records.partsStockSnapshot)
        try stock.validate()
        XCTAssertEqual(stock.workspaceID, fixture.workspaceID)
        XCTAssertTrue(stock.parts.isEmpty && stock.locations.isEmpty && stock.movements.isEmpty
            && stock.uses.isEmpty && stock.reversals.isEmpty && stock.returns.isEmpty
            && stock.abandonments.isEmpty)
        let receiptKeys = try fixture.history.receipts.map {
            try MutationReceiptV1.decodeCanonical(from: $0.receiptData).identity.stableKey
        }
        XCTAssertEqual(receiptKeys, receiptKeys.sorted())
        let historyFacts = try MutationJournalStoreV1.validatedImportedSnapshotFacts(
            fixture.history
        )
        XCTAssertEqual(historyFacts.receiptStableKeys(matching: fixture.history), receiptKeys)
        let reorderedHistory = MutationHistorySnapshotV1(
            workspaceRevision: fixture.history.workspaceRevision,
            lastLocalSequence: fixture.history.lastLocalSequence,
            receipts: Array(fixture.history.receipts.reversed()),
            quarantines: fixture.history.quarantines,
            entityRevisions: fixture.history.entityRevisions
        )
        XCTAssertNil(historyFacts.receiptStableKeys(matching: reorderedHistory))

        let roundFacts = try C05RoundSessionBackupEnrollmentV1.validatedFacts(package.records)
        XCTAssertEqual(roundFacts.validatedRoundSessions(matching: package.records), fixture.rounds)
        let reorderedRounds = package.records.replacingRoundSessions(
            Array(package.records.roundSessions.reversed())
        )
        XCTAssertNil(roundFacts.validatedRoundSessions(matching: reorderedRounds))
        XCTAssertThrowsError(try BackupCanonicalEncoderV1().encodeRecords(reorderedRounds))
        XCTAssertEqual(package.manifestJSONSHA256,
                       KernelCanonicalHashV1.sha256(try fixture.memberData("manifest.json")))
        XCTAssertEqual(package.recordsJSONSHA256,
                       KernelCanonicalHashV1.sha256(try fixture.memberData("records.json")))

        // The backup embeds the Round codec's numeric dates, including actor
        // and visit snapshots. Its ordinary reader must preserve those instants.
        let recordsData = try fixture.memberData("records.json")
        let recordsObject = try XCTUnwrap(JSONSerialization.jsonObject(with: recordsData) as? [String: Any])
        var futureRecords = recordsObject
        futureRecords["recordsSchemaVersion"] = LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion + 1
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(
            RepetitiveCaptureSourcePackageFixture.canonicalJSONData(futureRecords)))
        let roundObjects = try XCTUnwrap(recordsObject["roundSessions"] as? [[String: Any]])
        XCTAssertEqual(roundObjects.count, fixture.rounds.count)
        let roundMutationBaseline = try RepetitiveCaptureSourcePackageFixture.canonicalJSONData(recordsObject)
        XCTAssertEqual(roundMutationBaseline, recordsData)
        XCTAssertEqual(
            try BackupCanonicalDecoderV1().decodeRecords(roundMutationBaseline).roundSessions,
            fixture.rounds
        )
        var brokenDigestRounds = roundObjects
        brokenDigestRounds[0]["sessionSHA256"] = String(repeating: "f", count: 64)
        var brokenDigestRecords = recordsObject
        brokenDigestRecords["roundSessions"] = brokenDigestRounds
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(
            JSONSerialization.data(withJSONObject: brokenDigestRecords,
                options: [.sortedKeys, .withoutEscapingSlashes])))

        var brokenPredecessorRounds = roundObjects
        var predecessor = try XCTUnwrap(brokenPredecessorRounds[1]["predecessor"] as? [String: Any])
        predecessor["sessionSHA256"] = String(repeating: "e", count: 64)
        brokenPredecessorRounds[1]["predecessor"] = predecessor
        var brokenPredecessorRecords = recordsObject
        brokenPredecessorRecords["roundSessions"] = brokenPredecessorRounds
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(
            JSONSerialization.data(withJSONObject: brokenPredecessorRecords,
                options: [.sortedKeys, .withoutEscapingSlashes])))

        // WorkspaceID's canonical wire shape is {"rawValue": UUID}. Build a
        // fully valid foreign-owned revision (including actor and digest)
        // instead of relying on a scalar decoding failure. Its workspace key
        // sorts before this fixture's key, so C05 reaches the split-history
        // closure and rejects the remaining original history beginning at r2.
        let originalRoot = fixture.rounds[0]
        let foreignWorkspaceID = WorkspaceID(
            rawValue: RepetitiveCaptureSourcePackageFixture.id(0)
        )
        let foreignActorReference = try LocalActorReferenceV1(
            actorReferenceID: originalRoot.recordedBy.actor.actorReferenceID,
            workspaceID: foreignWorkspaceID,
            partyID: originalRoot.recordedBy.actor.partyID,
            displayName: originalRoot.recordedBy.actor.displayName
        )
        let foreignActor = try ActorSnapshotV1(
            snapshotID: originalRoot.recordedBy.snapshotID,
            workspaceID: foreignWorkspaceID,
            actor: foreignActorReference,
            responsibility: originalRoot.recordedBy.responsibility,
            displayNameAtTime: originalRoot.recordedBy.displayNameAtTime,
            capturedAt: originalRoot.recordedBy.capturedAt
        )
        let foreignRoot = try RoundSessionV1(
            workspaceID: foreignWorkspaceID,
            sessionID: originalRoot.sessionID,
            revision: originalRoot.revision,
            mutationID: originalRoot.mutationID,
            state: originalRoot.state,
            transition: originalRoot.transition,
            transitionItemID: originalRoot.transitionItemID,
            items: originalRoot.items,
            recordedBy: foreignActor,
            recordedAt: originalRoot.recordedAt
        )
        XCTAssertNoThrow(try foreignRoot.validateIntrinsic())
        var foreignOwnedRounds = fixture.rounds
        foreignOwnedRounds[0] = foreignRoot
        let foreignOwnedRecords = package.records.replacingRoundSessions(foreignOwnedRounds)
        XCTAssertThrowsError(try BackupCanonicalEncoderV1().encodeRecords(foreignOwnedRecords))
        var visitedDates = 0
        for (index, expected) in fixture.rounds.enumerated() {
            XCTAssertEqual(try XCTUnwrap(roundObjects[index]["recordedAt"] as? NSNumber).doubleValue,
                           expected.recordedAt.timeIntervalSince1970 * 1_000)
            let actual = package.records.roundSessions[index]
            XCTAssertEqual(actual.recordedAt, expected.recordedAt)
            XCTAssertEqual(actual.recordedBy.capturedAt, expected.recordedBy.capturedAt)
            for (actualItem, expectedItem) in zip(actual.items, expected.items) {
                XCTAssertEqual(actualItem.visit?.visitedAt, expectedItem.visit?.visitedAt)
                if expectedItem.visit != nil { visitedDates += 1 }
            }
        }
        XCTAssertGreaterThan(visitedDates, 0)
        XCTAssertEqual(try BackupCanonicalEncoderV1().encodeRecords(
            BackupCanonicalDecoderV1().decodeRecords(recordsData)).data, recordsData)

        // Start from a proven valid serialized baseline at the actual public
        // decoder boundary, then change only the timestamp representation.
        let decoder = BackupCanonicalDecoderV1()
        let serializedRecords = try RepetitiveCaptureSourcePackageFixture.canonicalJSONData(recordsObject)
        XCTAssertEqual(serializedRecords, recordsData)
        XCTAssertEqual(try decoder.decodeRecords(serializedRecords).roundSessions, fixture.rounds)
        let invalidRoundDates: [Any] = ["2026-08-31T00:00:00.000Z", "not-a-date", NSNull(), true]
        for value in invalidRoundDates {
            var changedRounds = roundObjects
            changedRounds[0]["recordedAt"] = value
            var changedRecords = recordsObject
            changedRecords["roundSessions"] = changedRounds
            let bytes = try RepetitiveCaptureSourcePackageFixture.canonicalJSONData(changedRecords)
            XCTAssertThrowsError(try decoder.decodeRecords(bytes))
        }
        let manifestData = try fixture.memberData("manifest.json")
        let manifestObject = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        XCTAssertEqual(manifestObject["exportedAt"] as? String, "2026-08-31T00:00:00.000Z")
        let serializedManifest = try RepetitiveCaptureSourcePackageFixture.canonicalJSONData(manifestObject)
        XCTAssertEqual(serializedManifest, manifestData)
        XCTAssertEqual(try decoder.decodeManifest(serializedManifest).exportedAt,
                       RepetitiveCaptureSourcePackageFixture.date)
        let invalidLegacyDates: [Any] = [1_788_134_400_000, "2026-08-31T00:00:00Z"]
        for value in invalidLegacyDates {
            var changedManifest = manifestObject
            changedManifest["exportedAt"] = value
            let bytes = try RepetitiveCaptureSourcePackageFixture.canonicalJSONData(changedManifest)
            XCTAssertThrowsError(try decoder.decodeManifest(bytes))
        }
    }

    func testPackageCapabilityRejectsTamperedRecordsAndMissingRequiredSourceAuthority() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture()
        defer { fixture.removePackages() }

        let tampered = try fixture.package(named: "tampered")
        var bytes = try Data(contentsOf: tampered.appendingPathComponent("records.json"))
        bytes.append(0x20)
        try bytes.write(to: tampered.appendingPathComponent("records.json"), options: .atomic)
        XCTAssertThrowsError(try ValidatedRepetitiveCaptureSourcePackageV2.validate(
            stagedPackageURL: tampered, using: BackupPackageValidatorV1()))

        let missingWorkspace = try fixture.package(named: "missing-workspace")
        try fixture.mutateManifestJSON(at: missingWorkspace) { object in
            var source = try XCTUnwrap(object["source"] as? [String: Any])
            source["workspaceID"] = NSNull()
            object["source"] = source
        }
        XCTAssertThrowsError(try ValidatedRepetitiveCaptureSourcePackageV2.validate(
            stagedPackageURL: missingWorkspace, using: BackupPackageValidatorV1()))

        let missingHistory = try fixture.package(named: "missing-history")
        try fixture.mutateRecordsTransportJSON(at: missingHistory) { object in
            object["mutationHistory"] = NSNull()
        }
        XCTAssertThrowsError(try ValidatedRepetitiveCaptureSourcePackageV2.validate(
            stagedPackageURL: missingHistory, using: BackupPackageValidatorV1()))

        // The encoder may reuse identities decoded by the complete imported-
        // snapshot validator, but canonical ordering remains mandatory.
        XCTAssertThrowsError(try fixture.package(named: "reordered-history",
                                                  recordsMutation: { object in
            var history = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
            var receipts = try XCTUnwrap(history["receipts"] as? [[String: Any]])
            receipts.reverse()
            history["receipts"] = receipts
            object["mutationHistory"] = history
        }))
        XCTAssertThrowsError(try fixture.package(named: "duplicate-history",
                                                  recordsMutation: { object in
            var history = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
            var receipts = try XCTUnwrap(history["receipts"] as? [[String: Any]])
            receipts.append(try XCTUnwrap(receipts.first))
            history["receipts"] = receipts
            object["mutationHistory"] = history
        }))
        XCTAssertThrowsError(try fixture.package(named: "noncanonical-receipt",
                                                  recordsMutation: { object in
            var history = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
            var receipts = try XCTUnwrap(history["receipts"] as? [[String: Any]])
            var receiptData = try XCTUnwrap(Data(base64Encoded:
                try XCTUnwrap(receipts[0]["receiptData"] as? String)))
            receiptData.append(0x20)
            receipts[0]["receiptData"] = receiptData.base64EncodedString()
            history["receipts"] = receipts
            object["mutationHistory"] = history
        }))
        XCTAssertThrowsError(try fixture.package(named: "mismatched-envelope-receipt",
                                                  recordsMutation: { object in
            var history = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
            var receipts = try XCTUnwrap(history["receipts"] as? [[String: Any]])
            receipts[0]["receiptData"] = receipts[1]["receiptData"]
            history["receipts"] = receipts
            object["mutationHistory"] = history
        }))
    }

    func testActualFactoryRejectsNoncanonicalTruncatedMemberDescriptorAndSchemaDrift() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture()
        defer { fixture.removePackages() }
        let validator = BackupPackageValidatorV1()

        let noncanonical = try fixture.package(named: "noncanonical-manifest")
        var manifestBytes = try Data(contentsOf: noncanonical.appendingPathComponent("manifest.json"))
        manifestBytes.append(0x20)
        try manifestBytes.write(to: noncanonical.appendingPathComponent("manifest.json"),
                                options: .atomic)

        let truncated = try fixture.package(named: "truncated-records")
        var recordsBytes = try Data(contentsOf: truncated.appendingPathComponent("records.json"))
        recordsBytes.removeLast()
        try recordsBytes.write(to: truncated.appendingPathComponent("records.json"), options: .atomic)

        let staleSize = try fixture.package(named: "stale-size")
        try fixture.mutateManifestJSON(at: staleSize) { object in
            var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
            entries[0]["byteCount"] = (try XCTUnwrap(entries[0]["byteCount"] as? NSNumber)).intValue + 1
            object["entries"] = entries
            object["declaredPayloadByteCount"] = entries[0]["byteCount"]
        }

        let staleHash = try fixture.package(named: "stale-hash")
        try fixture.mutateManifestJSON(at: staleHash) { object in
            var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
            entries[0]["sha256"] = String(repeating: "f", count: 64)
            object["entries"] = entries
        }

        let schemaDrift = try fixture.package(named: "schema-drift")
        try fixture.mutateManifestJSON(at: schemaDrift) { object in
            var source = try XCTUnwrap(object["source"] as? [String: Any])
            source["persistentSchemaVersion"] = 44
            object["source"] = source
        }

        let missingMember = try fixture.package(named: "missing-records")
        try FileManager.default.removeItem(at: missingMember.appendingPathComponent("records.json"))
        let extraMember = try fixture.package(named: "extra-member")
        try Data("not declared".utf8).write(
            to: extraMember.appendingPathComponent("extra.bin"), options: .atomic)

        for package in [noncanonical, truncated, staleSize, staleHash, schemaDrift,
                        missingMember, extraMember] {
            XCTAssertThrowsError(try ValidatedRepetitiveCaptureSourcePackageV2.validate(
                stagedPackageURL: package, using: validator), package.lastPathComponent)
        }
    }

    func testActualFactoryPropagatesCancellationWithoutPublishingCapability() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture()
        defer { fixture.removePackages() }
        let package = try fixture.package(named: "cancelled")
        var checkpoints = 0
        let cancellation = StreamingArchiveCancellationV1 {
            checkpoints += 1
            throw StreamingArchiveFailureV1.cancelled
        }

        XCTAssertThrowsError(try ValidatedRepetitiveCaptureSourcePackageV2.validate(
            stagedPackageURL: package, using: BackupPackageValidatorV1(),
            cancellation: cancellation)) {
            XCTAssertEqual($0 as? StreamingArchiveFailureV1, .cancelled)
        }
        XCTAssertEqual(checkpoints, 1)
    }
}

/// Shared by the package and graph tests. It creates an ordinary staged
/// `.fieldrecordbackup` directory and never constructs the private capability.
final class RepetitiveCaptureSourcePackageFixture {
    static let date = Date(timeIntervalSince1970: 1_788_134_400)

    let root: URL
    let workspaceID: WorkspaceID
    let rounds: [RoundSessionV1]
    let checkpoints: [FieldDraftCheckpointV1]
    let history: MutationHistorySnapshotV1

    private let source: V4BackupSourceV1
    private let records: V4BackupRecordsV1
    private let fileManager = FileManager.default
    private let phaseTrace: ((String) -> Void)?

    init(discardSource: Bool = false, includeForeignOriginal: Bool = false,
         laterActiveSource: Bool = false, discardPendingSource: Bool = false,
         laterRoundAfterDisposition: Bool = false,
         secondSameScopeGraph: Bool = false,
         secondGraphIsHistorical: Bool = false,
         addBranch: Bool = false, addOrphan: Bool = false,
         addAfterPending: Bool = false,
         includeUnrelatedHistory: Bool = false,
         semanticRequiredPair: Bool = false,
         extraCurrentV2Row: Bool = false,
         directDiscardedSource: Bool = false,
         staleExtraDiscardReceipt: Bool = false,
         foreignHistoryOnly: Bool = false,
         boundaryItemCount: Int? = nil, sourceOnly: Bool = false,
         extraActiveSourceRevisions: Int = 0,
         phaseTrace: ((String) -> Void)? = nil) throws {
        guard (0...512).contains(extraActiveSourceRevisions),
              extraActiveSourceRevisions == 0 || laterActiveSource,
              !sourceOnly || (!discardSource && !includeForeignOriginal && !laterActiveSource &&
                !discardPendingSource && !laterRoundAfterDisposition && !secondSameScopeGraph &&
                !secondGraphIsHistorical && !addBranch && !addOrphan && !addAfterPending &&
                !includeUnrelatedHistory && !semanticRequiredPair && !extraCurrentV2Row &&
                !directDiscardedSource && !staleExtraDiscardReceipt && !foreignHistoryOnly &&
                boundaryItemCount == nil) else { throw WorkspaceMutationFailureV1.invalidCommand }
        self.phaseTrace = phaseTrace
        phaseTrace?("fixture-start")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("v23-c36-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        workspaceID = WorkspaceID(rawValue: Self.id(1))
        let graph: GraphValues
        if foreignHistoryOnly {
            guard !discardSource, !includeForeignOriginal, !laterActiveSource,
                  !discardPendingSource, !laterRoundAfterDisposition,
                  !secondSameScopeGraph, !secondGraphIsHistorical,
                  !addBranch, !addOrphan, !addAfterPending,
                  !includeUnrelatedHistory, !semanticRequiredPair,
                  !extraCurrentV2Row, !directDiscardedSource,
                  !staleExtraDiscardReceipt, boundaryItemCount == nil else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            let foreign = try Self.makeGraph(
                workspaceID: WorkspaceID(rawValue: Self.id(9_000)), discardSource: false,
                laterActiveSource: false, discardPendingSource: false,
                laterRoundAfterDisposition: false, secondSameScopeGraph: false,
                secondGraphIsHistorical: false, addBranch: false, addOrphan: false,
                addAfterPending: false, includeUnrelatedHistory: false,
                semanticRequiredPair: true, extraCurrentV2Row: false,
                directDiscardedSource: false, staleExtraDiscardReceipt: false)
            graph = .init(rounds: [], checkpoints: [], history: foreign.history,
                          additionalRows: [])
        } else if let boundaryItemCount {
            guard !discardSource, !includeForeignOriginal, !laterActiveSource,
                  !discardPendingSource, !laterRoundAfterDisposition,
                  !secondSameScopeGraph, !secondGraphIsHistorical,
                  !addBranch, !addOrphan, !addAfterPending,
                  !includeUnrelatedHistory, !semanticRequiredPair,
                  !extraCurrentV2Row, !directDiscardedSource,
                  !staleExtraDiscardReceipt else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            graph = try Self.makeBoundaryGraph(
                workspaceID: workspaceID, itemCount: boundaryItemCount, phaseTrace: phaseTrace)
        } else {
            graph = try Self.makeGraph(
                workspaceID: workspaceID, discardSource: discardSource,
                laterActiveSource: laterActiveSource,
                discardPendingSource: discardPendingSource,
                laterRoundAfterDisposition: laterRoundAfterDisposition,
                secondSameScopeGraph: secondSameScopeGraph,
                secondGraphIsHistorical: secondGraphIsHistorical,
                addBranch: addBranch, addOrphan: addOrphan,
                addAfterPending: addAfterPending,
                includeUnrelatedHistory: includeUnrelatedHistory,
                semanticRequiredPair: semanticRequiredPair,
                extraCurrentV2Row: extraCurrentV2Row,
                directDiscardedSource: directDiscardedSource,
                staleExtraDiscardReceipt: staleExtraDiscardReceipt,
                sourceOnly: sourceOnly, extraActiveSourceRevisions: extraActiveSourceRevisions)
        }
        rounds = graph.rounds
        checkpoints = graph.checkpoints
        if includeForeignOriginal {
            let foreign = try Self.makeGraph(
                workspaceID: WorkspaceID(rawValue: Self.id(9_000)), discardSource: false,
                laterActiveSource: false, discardPendingSource: false,
                laterRoundAfterDisposition: false, secondSameScopeGraph: false,
                secondGraphIsHistorical: false, addBranch: false,
                addOrphan: false, addAfterPending: false,
                includeUnrelatedHistory: false, semanticRequiredPair: true,
                extraCurrentV2Row: false, directDiscardedSource: false,
                staleExtraDiscardReceipt: false)
            history = try Self.combining(graph.history, foreign.history)
        } else {
            history = graph.history
        }
        source = V4BackupSourceV1(
            appBuild: "c36-tests", appVersion: "23", persistentSchemaVersion: 45,
            replicaID: Self.id(2), recordsSchemaVersion: 44,
            sourceGenerationID: Self.id(3), workspaceID: workspaceID.rawValue)
        records = V4BackupRecordsV1(
            fieldDrafts: try (checkpoints.map(Self.row) + graph.additionalRows)
                .sorted(by: Self.rowLess),
            assets: [], deletionLedger: .empty, evidenceFiles: [], issues: [],
            mutationHistory: history, packets: [], recordsSchemaVersion: 44,
            reports: [], sites: [], workflowRecords: [],
            partsStockSnapshot: try .init(workspaceID: workspaceID,
                parts: [], locations: [], movements: [], uses: [], reversals: [],
                returns: [], abandonments: []),
            roundSessions: rounds)
        phaseTrace?("fixture-complete")
    }

    func validatedPackage(recordsMutation: ((inout [String: Any]) throws -> Void)? = nil)
        throws -> ValidatedRepetitiveCaptureSourcePackageV2 {
        let value = try writePackage(named: UUID().uuidString,
            recordsMutation: recordsMutation, validateRecordsBeforeWriting: false)
        phaseTrace?("package-validator-start")
        let validated = try ValidatedRepetitiveCaptureSourcePackageV2.validate(
            stagedPackageURL: value, using: BackupPackageValidatorV1())
        phaseTrace?("package-validator-complete")
        return validated
    }

    func package(named name: String,
                 sourceMutation: ((inout [String: Any]) throws -> Void)? = nil,
                 recordsMutation: ((inout [String: Any]) throws -> Void)? = nil) throws -> URL {
        try writePackage(named: name, sourceMutation: sourceMutation,
            recordsMutation: recordsMutation, validateRecordsBeforeWriting: true)
    }

    private func writePackage(named name: String,
                 sourceMutation: ((inout [String: Any]) throws -> Void)? = nil,
                 recordsMutation: ((inout [String: Any]) throws -> Void)? = nil,
                 validateRecordsBeforeWriting: Bool) throws -> URL {
        let directory = root.appendingPathComponent("\(name).fieldrecordbackup", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        phaseTrace?("records-encoder-start")
        let encodedRecords = try BackupCanonicalEncoderV1().encodeRecords(records).data
        phaseTrace?("records-encoder-complete")
        let recordsData: Data
        if let recordsMutation {
            var recordsObject = try XCTUnwrap(JSONSerialization.jsonObject(
                with: encodedRecords) as? [String: Any])
            phaseTrace?("records-json-object-complete")
            try recordsMutation(&recordsObject)
            recordsData = try Self.canonicalJSONData(recordsObject)
        } else {
            recordsData = encodedRecords
        }
        // Public package-only fixtures retain their existing strict validation.
        // validatedPackage performs it through the actual package validator
        // immediately below, on the exact bytes written here.
        if validateRecordsBeforeWriting {
            phaseTrace?("raw-decode-start")
            _ = try BackupCanonicalDecoderV1().decodeRecords(recordsData)
            phaseTrace?("raw-decode-complete")
        }
        try recordsData.write(to: directory.appendingPathComponent("records.json"), options: .atomic)

        var sourceObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try JSONEncoder.canonicalV1.encode(source)) as? [String: Any])
        try sourceMutation?(&sourceObject)
        let sourceData = try JSONSerialization.data(withJSONObject: sourceObject, options: [.sortedKeys])
        let decodedSource = try JSONDecoder.canonicalV1.decode(V4BackupSourceV1.self, from: sourceData)
        let entry = V4BackupEntryV1(byteCount: recordsData.count, mimeType: "application/json",
                                    path: "records.json",
                                    sha256: KernelCanonicalHashV1.sha256(recordsData))
        let manifest = V4BackupManifestV1(
            backupSchemaVersion: 4, consumedEvaluationRootIDs: [],
            declaredPayloadByteCount: recordsData.count, entries: [entry],
            exportedAt: Self.date, packs: [], source: decodedSource)
        try BackupCanonicalEncoderV1().encodeManifest(manifest).data.write(
            to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        return directory
    }

    static func canonicalJSONData(_ object: Any) throws -> Data {
        func value(_ object: Any) throws -> CanonicalJSONValueV1 {
            if object is NSNull { return .null }
            if let object = object as? [String: Any] { return .object(try object.mapValues(value)) }
            if let object = object as? [Any] { return .array(try object.map(value)) }
            if let object = object as? String { return .string(object) }
            if let object = object as? NSNumber {
                if CFGetTypeID(object) == CFBooleanGetTypeID() { return .bool(object.boolValue) }
                guard let integer = Int(object.stringValue) else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
                return .integer(integer)
            }
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        return try CanonicalJSONV1.encode(value(object))
    }

    func package(named name: String,
                 _ sourceMutation: (inout [String: Any]) throws -> Void) throws -> URL {
        try withoutActuallyEscaping(sourceMutation) { mutation in
            try package(named: name, sourceMutation: mutation)
        }
    }

    func memberData(_ name: String) throws -> Data {
        let directories = try fileManager.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil).filter { $0.pathExtension == "fieldrecordbackup" }
        let directory = try XCTUnwrap(directories.last)
        return try Data(contentsOf: directory.appendingPathComponent(name))
    }

    func roundJSONObject(_ round: RoundSessionV1) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder.canonicalV1.encode(round)) as? [String: Any])
    }

    func mutateManifestJSON(at package: URL,
                            _ mutation: (inout [String: Any]) throws -> Void) throws {
        let url = package.appendingPathComponent("manifest.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: url)) as? [String: Any])
        try mutation(&object)
        try Self.canonicalJSONData(object).write(to: url, options: .atomic)
    }

    // Malformed transport fixtures start with an encoder-valid package and keep
    // member descriptors accurate, so the actual validator reaches the mutation.
    func mutateRecordsTransportJSON(at package: URL,
                                    _ mutation: (inout [String: Any]) throws -> Void) throws {
        let url = package.appendingPathComponent("records.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: url)) as? [String: Any])
        try mutation(&object)
        let data = try Self.canonicalJSONData(object)
        try data.write(to: url, options: .atomic)
        try mutateManifestJSON(at: package) { manifest in
            var entries = try XCTUnwrap(manifest["entries"] as? [[String: Any]])
            let index = try XCTUnwrap(entries.firstIndex { $0["path"] as? String == "records.json" })
            let previousByteCount = try XCTUnwrap(entries[index]["byteCount"] as? Int)
            let declaredByteCount = try XCTUnwrap(manifest["declaredPayloadByteCount"] as? Int)
            entries[index]["byteCount"] = data.count
            entries[index]["sha256"] = KernelCanonicalHashV1.sha256(data)
            manifest["entries"] = entries
            manifest["declaredPayloadByteCount"] = declaredByteCount - previousByteCount + data.count
        }
    }

    func removePackages() { try? fileManager.removeItem(at: root) }

    private struct GraphValues {
        let rounds: [RoundSessionV1]
        let checkpoints: [FieldDraftCheckpointV1]
        let history: MutationHistorySnapshotV1
        let additionalRows: [V16BackupFieldDraftRecordV1]
    }

    private struct Event {
        let envelope: MutationEnvelopeV1
        let receipt: MutationReceiptV1
        let reversalBasisData: Data?
        let semanticReversalData: Data?
    }

    private static func makeGraph(
        workspaceID: WorkspaceID,
        discardSource: Bool,
        laterActiveSource: Bool,
        discardPendingSource: Bool,
        laterRoundAfterDisposition: Bool,
        secondSameScopeGraph: Bool,
        secondGraphIsHistorical: Bool,
        addBranch: Bool,
        addOrphan: Bool,
        addAfterPending: Bool,
        includeUnrelatedHistory: Bool,
        semanticRequiredPair: Bool,
        extraCurrentV2Row: Bool,
        directDiscardedSource: Bool,
        staleExtraDiscardReceipt: Bool,
        sourceOnly: Bool = false,
        extraActiveSourceRevisions: Int = 0
    ) throws
        -> GraphValues {
        guard [discardSource, laterActiveSource, discardPendingSource, directDiscardedSource]
            .filter({ $0 }).count <= 1,
              !laterRoundAfterDisposition || discardSource,
              !staleExtraDiscardReceipt || discardSource,
              !secondGraphIsHistorical || secondSameScopeGraph else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let actor = try actor(workspaceID)
        let package = try RoundPackageReleaseReferenceV1(
            packageReleaseID: String(repeating: "a", count: 64), packageID: "c36-source",
            packageContentVersion: 1, packageSHA256: String(repeating: "a", count: 64),
            workflowSHA256: String(repeating: "b", count: 64))
        let items = try (0..<2).map { index in
            try RoundItemV1(itemID: id(20 + index), order: index,
                selection: .init(assetID: id(30 + index), siteID: id(40 + index),
                                 labelAtSelection: "Asset \(index)"),
                requirement: .init(packageRelease: package, requiredContent: []))
        }
        let draft = try RoundSessionV1(workspaceID: workspaceID, sessionID: id(10), revision: 1,
            mutationID: .init(rawValue: id(100)), state: .draft, transition: .create,
            items: items, recordedBy: actor, recordedAt: date)
        let active = try RoundSessionV1(workspaceID: workspaceID, sessionID: draft.sessionID,
            predecessor: draft, revision: 2, mutationID: .init(rawValue: id(101)),
            state: .active, transition: .start, items: items,
            recordedBy: actor, recordedAt: date.addingTimeInterval(1))
        var visitedItems = items
        visitedItems[0] = try RoundItemV1(itemID: items[0].itemID, order: 0,
            selection: items[0].selection, requirement: items[0].requirement,
            disposition: .visited,
            visit: .init(visitedAt: date.addingTimeInterval(2), recordedBy: actor))
        let visited = try RoundSessionV1(workspaceID: workspaceID, sessionID: draft.sessionID,
            predecessor: active, revision: 3, mutationID: .init(rawValue: id(102)),
            state: .active, transition: .visitItem, transitionItemID: items[0].itemID,
            items: visitedItems, recordedBy: actor, recordedAt: date.addingTimeInterval(2))
        let pendingVisit = try RoundSessionV1(workspaceID: workspaceID, sessionID: draft.sessionID,
            predecessor: visited, revision: 4, mutationID: .init(rawValue: id(103)),
            state: .active, transition: .visitItem, transitionItemID: items[1].itemID,
            items: try visiting(items: visitedItems, index: 1, actor: actor),
            recordedBy: actor, recordedAt: date.addingTimeInterval(3))
        let roundMutations = try [draft, active, visited].map {
            try RoundSessionMutationV1(workspaceID: workspaceID,
                expectedRevision: $0.revision - 1, mutationID: $0.mutationID, session: $0)
        }

        let readiness = try readiness(round: active)
        let launch = try RepetitiveCaptureLaunchSourceV2(planID: id(11), round: active,
            readiness: active.items.map { try .init(manifest: readiness, assetID: $0.selection.assetID) })
        let scope = try RepetitiveCaptureDraftCodecV1.scope(planID: id(11), round: active.reference)
        let sourceCheckpoint = try checkpoint(id: 200, workspaceID: workspaceID, scope: scope,
            payload: .source(launch), anchor: .init(sectionID: "facts",
                selectedStableID: items[0].selection.assetID.uuidString.lowercased()))
        let firstMutation = roundMutations[2]
        let firstStep = try RepetitiveCaptureProgressStepV2(
            source: .init(source: sourceCheckpoint), prior: nil, priorRoundReceipt: nil,
            expectedRound: active, itemID: items[0].itemID, action: .enter,
            roundMutation: firstMutation, requirementFocus: .facts,
            resumeAnchor: .init(sectionID: "facts",
                selectedStableID: items[0].selection.assetID.uuidString.lowercased()))
        let first = try checkpoint(id: 201, workspaceID: workspaceID, scope: scope,
            payload: .progress(firstStep), anchor: firstStep.resumeAnchor)
        let secondSource: FieldDraftCheckpointV1?
        let secondFirst: FieldDraftCheckpointV1?
        if secondSameScopeGraph {
            let source = try checkpoint(id: 500, workspaceID: workspaceID, scope: scope,
                payload: .source(launch), anchor: sourceCheckpoint.resumeAnchor)
            let step = try RepetitiveCaptureProgressStepV2(
                source: .init(source: source), prior: nil, priorRoundReceipt: nil,
                expectedRound: active, itemID: items[0].itemID, action: .enter,
                roundMutation: firstMutation, requirementFocus: .facts,
                resumeAnchor: firstStep.resumeAnchor)
            secondSource = source
            secondFirst = try checkpoint(id: 501, workspaceID: workspaceID, scope: scope,
                payload: .progress(step), anchor: step.resumeAnchor)
        } else {
            secondSource = nil
            secondFirst = nil
        }

        var builder = HistoryBuilder(workspaceID: workspaceID)
        _ = try builder.append(.applyRoundSession(roundMutations[0]))
        _ = try builder.append(.applyRoundSession(roundMutations[1]))
        if sourceOnly {
            _ = try builder.append(.applyFieldDraft(fieldMutation(sourceCheckpoint)))
            return .init(rounds: [draft, active], checkpoints: [sourceCheckpoint],
                         history: try builder.snapshot(), additionalRows: [])
        }
        if semanticRequiredPair {
            _ = try builder.appendSemanticReversalPair(
                target: .applyFieldDraft(fieldMutation(sourceCheckpoint)),
                reversal: .applyFieldDraft(fieldMutation(first)))
        } else {
            _ = try builder.append(.applyFieldDraft(fieldMutation(sourceCheckpoint)))
            _ = try builder.append(.applyFieldDraft(fieldMutation(first)))
        }
        if let secondSource, let secondFirst {
            _ = try builder.append(.applyFieldDraft(fieldMutation(secondSource)))
            _ = try builder.append(.applyFieldDraft(fieldMutation(secondFirst)))
        }
        let visitReceipt = try builder.append(.applyRoundSession(roundMutations[2])).receipt
        let typedVisitReceipt = try RoundSessionMutationReceiptV1(
            mutation: firstMutation, mutationReceipt: visitReceipt)
        let keepStep = try RepetitiveCaptureProgressStepV2(
            source: .init(source: sourceCheckpoint), prior: .init(source: first),
            priorRoundReceipt: typedVisitReceipt, expectedRound: visited,
            itemID: items[0].itemID, action: .keepOpenAndNext, roundMutation: nil,
            requirementFocus: .facts, resumeAnchor: .init(sectionID: "facts",
                selectedStableID: items[1].selection.assetID.uuidString.lowercased()))
        let keep = try checkpoint(id: 202, workspaceID: workspaceID, scope: scope,
            payload: .progress(keepStep), anchor: keepStep.resumeAnchor)
        _ = try builder.append(.applyFieldDraft(fieldMutation(keep)))
        let pendingMutation = try RoundSessionMutationV1(workspaceID: workspaceID,
            expectedRevision: 3, mutationID: pendingVisit.mutationID, session: pendingVisit)
        let pendingStep = try RepetitiveCaptureProgressStepV2(
            source: .init(source: sourceCheckpoint), prior: .init(source: keep),
            priorRoundReceipt: nil, expectedRound: visited, itemID: items[1].itemID,
            action: .enter, roundMutation: pendingMutation, requirementFocus: .facts,
            resumeAnchor: .init(sectionID: "facts",
                selectedStableID: items[1].selection.assetID.uuidString.lowercased()))
        let pending = try checkpoint(id: 203, workspaceID: workspaceID, scope: scope,
            payload: .progress(pendingStep), anchor: pendingStep.resumeAnchor)
        _ = try builder.append(.applyFieldDraft(fieldMutation(pending)))
        var currentCheckpoints = [sourceCheckpoint, first, keep, pending]
        if let secondSource, let secondFirst {
            currentCheckpoints += [secondSource, secondFirst]
        }
        if extraCurrentV2Row {
            let extra = try checkpoint(
                id: 590, workspaceID: workspaceID, scope: scope,
                payload: .source(launch), anchor: sourceCheckpoint.resumeAnchor)
            currentCheckpoints.append(extra)
        }
        if addBranch {
            let step = try RepetitiveCaptureProgressStepV2(
                source: .init(source: sourceCheckpoint), prior: .init(source: first),
                priorRoundReceipt: typedVisitReceipt, expectedRound: visited,
                itemID: items[0].itemID, action: .keepOpenAndNext,
                roundMutation: nil, requirementFocus: .facts,
                resumeAnchor: keepStep.resumeAnchor)
            let branch = try checkpoint(id: 600, workspaceID: workspaceID, scope: scope,
                payload: .progress(step), anchor: step.resumeAnchor)
            _ = try builder.append(.applyFieldDraft(fieldMutation(branch)))
            currentCheckpoints.append(branch)
        }
        if addOrphan {
            let absentSource = try checkpoint(id: 610, workspaceID: workspaceID, scope: scope,
                payload: .source(launch), anchor: sourceCheckpoint.resumeAnchor)
            let step = try RepetitiveCaptureProgressStepV2(
                source: .init(source: absentSource), prior: nil, priorRoundReceipt: nil,
                expectedRound: active, itemID: items[0].itemID, action: .enter,
                roundMutation: firstMutation, requirementFocus: .facts,
                resumeAnchor: firstStep.resumeAnchor)
            let orphan = try checkpoint(id: 611, workspaceID: workspaceID, scope: scope,
                payload: .progress(step), anchor: step.resumeAnchor)
            _ = try builder.append(.applyFieldDraft(fieldMutation(orphan)))
            currentCheckpoints.append(orphan)
        }
        if addAfterPending {
            var receiptBuilder = HistoryBuilder(workspaceID: workspaceID)
            let receipt = try receiptBuilder.append(
                .applyRoundSession(pendingMutation)).receipt
            let typed = try RoundSessionMutationReceiptV1(
                mutation: pendingMutation, mutationReceipt: receipt)
            let step = try RepetitiveCaptureProgressStepV2(
                source: .init(source: sourceCheckpoint), prior: .init(source: pending),
                priorRoundReceipt: typed, expectedRound: pendingVisit,
                itemID: items[1].itemID, action: .keepOpenAndNext,
                roundMutation: nil, requirementFocus: .facts,
                resumeAnchor: .init(sectionID: "facts", selectedStableID: nil))
            let after = try checkpoint(id: 620, workspaceID: workspaceID, scope: scope,
                payload: .progress(step), anchor: step.resumeAnchor)
            _ = try builder.append(.applyFieldDraft(fieldMutation(after)))
            currentCheckpoints.append(after)
        }
        var additionalRows: [V16BackupFieldDraftRecordV1] = []
        if includeUnrelatedHistory {
            let fixture = try C36FieldDraftTestSupportV1.makeFixture(seed: 880_000)
            let unrelated = try FieldDraftCheckpointV1(
                draftID: id(880), workspaceID: workspaceID,
                scope: fixture.scope, purpose: .inspectionReview, codec: fixture.codec,
                baseCanonicalRevision: 0, draftRevision: 1,
                payloadData: fixture.payload, stageIDs: [], resumeAnchor: fixture.anchor,
                state: .active, updatedAt: date, mutationID: .init(rawValue: id(881)))
            let compensating = try FieldDraftCheckpointV1(
                draftID: id(882), workspaceID: workspaceID,
                scope: fixture.scope, purpose: .inspectionReview, codec: fixture.codec,
                baseCanonicalRevision: 0, draftRevision: 1,
                payloadData: fixture.payload, stageIDs: [], resumeAnchor: fixture.anchor,
                state: .active, updatedAt: date, mutationID: .init(rawValue: id(883)))
            _ = try builder.appendSemanticReversalPair(
                target: .applyFieldDraft(fieldMutation(unrelated)),
                reversal: .applyFieldDraft(fieldMutation(compensating)))
            additionalRows += [try row(unrelated), try row(compensating)]
        }
        if laterActiveSource {
            var changed = try revisedActiveSource(
                sourceCheckpoint, round: active, revision: 2, mutationSeed: 400)
            let mutation = try FieldDraftMutationV1(
                workspaceID: workspaceID, expectedRevision: 1,
                expectedBaseCanonicalRevision: 0, mutationID: changed.mutationID,
                postImage: .reviseCheckpoint(changed))
            _ = try builder.append(.applyFieldDraft(mutation))
            for offset in 0..<extraActiveSourceRevisions {
                let predecessor = changed
                changed = try revisedCheckpoint(sourceCheckpoint,
                    revision: predecessor.draftRevision + 1, state: .active,
                    mutationID: .init(rawValue: id(20_000 + offset)),
                    payloadData: predecessor.payloadData)
                let successor = try FieldDraftMutationV1(
                    workspaceID: workspaceID, expectedRevision: predecessor.draftRevision,
                    expectedBaseCanonicalRevision: 0, mutationID: changed.mutationID,
                    postImage: .reviseCheckpoint(changed))
                _ = try builder.append(.applyFieldDraft(successor))
            }
            currentCheckpoints[0] = changed
        } else if discardPendingSource {
            let discardPending = try revisedCheckpoint(
                sourceCheckpoint, revision: 2, state: .discardPending,
                mutationID: .init(rawValue: id(400)), payloadData: sourceCheckpoint.payloadData)
            let mutation = try FieldDraftMutationV1(
                workspaceID: workspaceID, expectedRevision: 1,
                expectedBaseCanonicalRevision: 0, mutationID: discardPending.mutationID,
                postImage: .reviseCheckpoint(discardPending))
            _ = try builder.append(.applyFieldDraft(mutation))
            currentCheckpoints[0] = discardPending
        } else if discardSource {
            let discardPending = try FieldDraftCheckpointV1(
                draftID: sourceCheckpoint.draftID, workspaceID: workspaceID,
                scope: sourceCheckpoint.scope, purpose: sourceCheckpoint.purpose,
                codec: sourceCheckpoint.codec, baseCanonicalRevision: 0, draftRevision: 2,
                payloadData: sourceCheckpoint.payloadData, stageIDs: [],
                resumeAnchor: sourceCheckpoint.resumeAnchor, state: .discardPending,
                updatedAt: date.addingTimeInterval(10), mutationID: .init(rawValue: id(400)))
            let pendingDiscardMutation = try FieldDraftMutationV1(
                workspaceID: workspaceID, expectedRevision: 1,
                expectedBaseCanonicalRevision: 0, mutationID: discardPending.mutationID,
                postImage: .reviseCheckpoint(discardPending))
            _ = try builder.append(.applyFieldDraft(pendingDiscardMutation))
            let plan = try DraftDiscardPlanV1(
                planID: id(401), workspaceID: workspaceID,
                draftID: sourceCheckpoint.draftID, expectedDraftRevision: 2,
                nonemptyPayload: true, stageIDs: [], reservationIDs: [],
                estimatedBytes: Int64(sourceCheckpoint.payloadData.count))
            let terminalMutationID = try MutationIDV1(rawValue: id(402))
            let receipt = try DraftDiscardReceiptV1(
                receiptID: id(403), workspaceID: workspaceID,
                draftID: sourceCheckpoint.draftID, planSHA256: plan.planSHA256,
                disposedStageIDs: [], quarantinedReservationIDs: [],
                discardedAt: date.addingTimeInterval(11), mutationID: terminalMutationID)
            let discarded = try FieldDraftCheckpointV1(
                draftID: sourceCheckpoint.draftID, workspaceID: workspaceID,
                scope: sourceCheckpoint.scope, purpose: sourceCheckpoint.purpose,
                codec: sourceCheckpoint.codec, baseCanonicalRevision: 0, draftRevision: 3,
                payloadData: sourceCheckpoint.payloadData, stageIDs: [],
                resumeAnchor: sourceCheckpoint.resumeAnchor, state: .discarded,
                lastDurableMutationID: terminalMutationID,
                lastReceiptSHA256: receipt.receiptSHA256,
                updatedAt: date.addingTimeInterval(11), mutationID: terminalMutationID)
            let bundle = try DraftDiscardTerminalBundleV1(
                discardedCheckpoint: discarded, receipt: receipt)
            let terminal = try FieldDraftMutationV1(
                workspaceID: workspaceID, expectedRevision: 2,
                expectedBaseCanonicalRevision: 0, mutationID: terminalMutationID,
                postImage: .applyDiscardTerminal(bundle))
            _ = try builder.append(.applyFieldDraft(terminal))
            currentCheckpoints[0] = discarded
            additionalRows = [.init(kind: .discardReceipt, id: receipt.receiptID,
                workspaceID: workspaceID.rawValue, revision: receipt.revision,
                canonicalData: try FieldDraftCanonicalCodecV1.encode(receipt))]
            if staleExtraDiscardReceipt {
                let stale = try DraftDiscardReceiptV1(
                    receiptID: id(404), workspaceID: workspaceID,
                    draftID: sourceCheckpoint.draftID,
                    planSHA256: String(repeating: "e", count: 64),
                    disposedStageIDs: [], quarantinedReservationIDs: [],
                    discardedAt: date.addingTimeInterval(9),
                    mutationID: .init(rawValue: id(405)))
                additionalRows.append(.init(
                    kind: .discardReceipt, id: stale.receiptID,
                    workspaceID: workspaceID.rawValue, revision: stale.revision,
                    canonicalData: try FieldDraftCanonicalCodecV1.encode(stale)))
            }
        } else if directDiscardedSource {
            let mutationID = try MutationIDV1(rawValue: id(410))
            let direct = try FieldDraftCheckpointV1(
                draftID: sourceCheckpoint.draftID, workspaceID: workspaceID,
                scope: sourceCheckpoint.scope, purpose: sourceCheckpoint.purpose,
                codec: sourceCheckpoint.codec, baseCanonicalRevision: 0,
                draftRevision: 2, payloadData: sourceCheckpoint.payloadData,
                stageIDs: [], resumeAnchor: sourceCheckpoint.resumeAnchor,
                state: .discarded, lastDurableMutationID: mutationID,
                lastReceiptSHA256: String(repeating: "d", count: 64),
                updatedAt: date.addingTimeInterval(10), mutationID: mutationID)
            let mutation = try FieldDraftMutationV1(
                workspaceID: workspaceID, expectedRevision: 1,
                expectedBaseCanonicalRevision: 0, mutationID: mutationID,
                postImage: .reviseCheckpoint(direct))
            _ = try builder.append(.applyFieldDraft(mutation))
            currentCheckpoints[0] = direct
        }
        if secondGraphIsHistorical, let original = secondSource {
            let index = try XCTUnwrap(currentCheckpoints.firstIndex {
                $0.draftID == original.draftID
            })
            let changed = try revisedActiveSource(
                original, round: active, revision: 2, mutationSeed: 700)
            let mutation = try FieldDraftMutationV1(
                workspaceID: workspaceID, expectedRevision: 1,
                expectedBaseCanonicalRevision: 0, mutationID: changed.mutationID,
                postImage: .reviseCheckpoint(changed))
            _ = try builder.append(.applyFieldDraft(mutation))
            currentCheckpoints[index] = changed
        }
        var packageRounds = [draft, active, visited]
        if laterRoundAfterDisposition {
            let laterItems = try deferring(items: visited.items, index: 1)
            let later = try RoundSessionV1(
                workspaceID: workspaceID, sessionID: visited.sessionID,
                predecessor: visited, revision: 4, mutationID: .init(rawValue: id(104)),
                state: .active, transition: .deferItem,
                transitionItemID: visited.items[1].itemID, items: laterItems,
                recordedBy: actor, recordedAt: date.addingTimeInterval(20))
            let mutation = try RoundSessionMutationV1(
                workspaceID: workspaceID, expectedRevision: 3,
                mutationID: later.mutationID, session: later)
            _ = try builder.append(.applyRoundSession(mutation))
            packageRounds.append(later)
        }
        return .init(rounds: packageRounds,
                     checkpoints: currentCheckpoints, history: try builder.snapshot(),
                     additionalRows: additionalRows)
    }

    private static func makeBoundaryGraph(workspaceID: WorkspaceID, itemCount: Int,
                                          phaseTrace: ((String) -> Void)?) throws
        -> GraphValues {
        guard itemCount == ScanToWorkLimitsV1.maximumSelection else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let actor = try actor(workspaceID)
        let package = try RoundPackageReleaseReferenceV1(
            packageReleaseID: String(repeating: "a", count: 64),
            packageID: "c36-boundary", packageContentVersion: 1,
            packageSHA256: String(repeating: "a", count: 64),
            workflowSHA256: String(repeating: "b", count: 64))
        let items = try (0..<itemCount).map { index in
            try RoundItemV1(
                itemID: id(11_000 + index), order: index,
                selection: .init(assetID: id(12_000 + index),
                                 siteID: id(13_000 + index),
                                 labelAtSelection: "Boundary asset \(index)"),
                requirement: .init(packageRelease: package, requiredContent: []))
        }
        let draft = try RoundSessionV1(
            workspaceID: workspaceID, sessionID: id(10_000), revision: 1,
            mutationID: .init(rawValue: id(14_001)), state: .draft,
            transition: .create, items: items, recordedBy: actor, recordedAt: date)
        let active = try RoundSessionV1(
            workspaceID: workspaceID, sessionID: draft.sessionID, predecessor: draft,
            revision: 2, mutationID: .init(rawValue: id(14_002)), state: .active,
            transition: .start, items: items, recordedBy: actor,
            recordedAt: date.addingTimeInterval(1))
        phaseTrace?("readiness-manifest-start")
        let ready = try readiness(round: active)
        phaseTrace?("readiness-manifest-complete")
        let readyProofs: [ScanToWorkOfflineReadinessProofV1] = try active.items.map {
            try .init(manifest: ready, assetID: $0.selection.assetID)
        }
        phaseTrace?("readiness-proofs-complete")
        let planID = id(10_001)
        let launch = try RepetitiveCaptureLaunchSourceV2(
            planID: planID, round: active, readiness: readyProofs)
        let scope = try RepetitiveCaptureDraftCodecV1.scope(
            planID: planID, round: active.reference)
        let source = try checkpoint(
            id: 15_000, workspaceID: workspaceID, scope: scope,
            payload: .source(launch), anchor: .init(
                sectionID: "facts",
                selectedStableID: active.items[0].selection.assetID.uuidString.lowercased()))
        var builder = HistoryBuilder(workspaceID: workspaceID)
        var rounds = [draft, active]
        _ = try builder.append(.applyRoundSession(.init(
            workspaceID: workspaceID, expectedRevision: 0,
            mutationID: draft.mutationID, session: draft)))
        _ = try builder.append(.applyRoundSession(.init(
            workspaceID: workspaceID, expectedRevision: 1,
            mutationID: active.mutationID, session: active)))
        _ = try builder.append(.applyFieldDraft(fieldMutation(source)))

        var checkpoints = [source]
        var current = active
        var prior: FieldDraftCheckpointV1?
        phaseTrace?("progress-construction-start")
        for index in 0..<itemCount {
            let visited = try visitingRound(
                current, itemIndex: index, actor: actor,
                mutationID: .init(rawValue: id(14_100 + index)))
            let mutation = try RoundSessionMutationV1(
                workspaceID: workspaceID, expectedRevision: current.revision,
                mutationID: visited.mutationID, session: visited)
            let entryStep = try RepetitiveCaptureProgressStepV2(
                source: .init(source: source),
                prior: try prior.map { try .init(source: $0) },
                priorRoundReceipt: nil, expectedRound: current,
                itemID: current.items[index].itemID, action: .enter,
                roundMutation: mutation, requirementFocus: .facts,
                resumeAnchor: .init(sectionID: "facts", selectedStableID:
                    current.items[index].selection.assetID.uuidString.lowercased()))
            let entry = try checkpoint(
                id: 16_000 + index * 2, workspaceID: workspaceID, scope: scope,
                payload: .progress(entryStep), anchor: entryStep.resumeAnchor)
            _ = try builder.append(.applyFieldDraft(fieldMutation(entry)))
            let receipt = try builder.append(.applyRoundSession(mutation)).receipt
            let typed = try RoundSessionMutationReceiptV1(
                mutation: mutation, mutationReceipt: receipt)
            rounds.append(visited)

            let nextAssetID = index + 1 < itemCount
                ? visited.items[index + 1].selection.assetID.uuidString.lowercased() : nil
            let keepStep = try RepetitiveCaptureProgressStepV2(
                source: .init(source: source), prior: .init(source: entry),
                priorRoundReceipt: typed, expectedRound: visited,
                itemID: visited.items[index].itemID, action: .keepOpenAndNext,
                roundMutation: nil, requirementFocus: .facts,
                resumeAnchor: .init(sectionID: "facts", selectedStableID: nextAssetID))
            let keep = try checkpoint(
                id: 16_001 + index * 2, workspaceID: workspaceID, scope: scope,
                payload: .progress(keepStep), anchor: keepStep.resumeAnchor)
            _ = try builder.append(.applyFieldDraft(fieldMutation(keep)))
            checkpoints += [entry, keep]
            current = visited
            prior = keep
            if (index + 1).isMultiple(of: 50) {
                phaseTrace?("progress-construction-\(index + 1)-items")
            }
        }
        phaseTrace?("progress-construction-complete")
        return .init(rounds: rounds, checkpoints: checkpoints,
                     history: try builder.snapshot(phaseTrace: phaseTrace), additionalRows: [])
    }

    private static func visitingRound(
        _ prior: RoundSessionV1,
        itemIndex: Int,
        actor: ActorSnapshotV1,
        mutationID: MutationIDV1
    ) throws -> RoundSessionV1 {
        let items = try visiting(items: prior.items, index: itemIndex, actor: actor)
        return try RoundSessionV1(
            workspaceID: prior.workspaceID, sessionID: prior.sessionID,
            predecessor: prior, revision: prior.revision + 1,
            mutationID: mutationID, state: .active, transition: .visitItem,
            transitionItemID: prior.items[itemIndex].itemID, items: items,
            recordedBy: actor,
            recordedAt: date.addingTimeInterval(Double(prior.revision)))
    }

    private static func canonicalReceipts(_ records: [MutationHistoryReceiptRecordV1]) throws
        -> [MutationHistoryReceiptRecordV1] {
        let keyed: [(String, MutationHistoryReceiptRecordV1)] = try records.map { record in
            (try MutationReceiptV1.decodeCanonical(from: record.receiptData).identity.stableKey, record)
        }
        return keyed.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    private static func combining(_ primary: MutationHistorySnapshotV1,
                                  _ foreign: MutationHistorySnapshotV1) throws
        -> MutationHistorySnapshotV1 {
        var projections: [WorkspaceEntityIdentityV1: MutationHistoryEntityRevisionV1] = [:]
        for projection in primary.entityRevisions + foreign.entityRevisions {
            if let existing = projections[projection.identity] {
                guard existing == projection else {
                    throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                }
            } else {
                projections[projection.identity] = projection
            }
        }
        let value = MutationHistorySnapshotV1(
            workspaceRevision: primary.workspaceRevision,
            lastLocalSequence: primary.lastLocalSequence,
            receipts: try canonicalReceipts(primary.receipts + foreign.receipts),
            quarantines: primary.quarantines + foreign.quarantines,
            entityRevisions: projections.values.sorted {
                $0.identity.stableKey < $1.identity.stableKey
            })
        try MutationJournalStoreV1.validateImportedSnapshot(
            value, sourcePersistentSchemaVersion: 45)
        return value
    }

    private struct HistoryBuilder {
        let workspaceID: WorkspaceID
        let replicaID = ReplicaID(rawValue: RepetitiveCaptureSourcePackageFixture.id(2))
        let generationID = RepetitiveCaptureSourcePackageFixture.id(3)
        let writerID = RepetitiveCaptureSourcePackageFixture.id(4)
        var events: [Event] = []
        var revisions: [WorkspaceEntityIdentityV1: UInt64] = [:]

        mutating func append(_ command: WorkspaceCommandV1) throws -> Event {
            let binding = try Self.binding(command)
            let expected = try WorkspaceExpectedRevisionV1(
                workspaceID: workspaceID, generationID: generationID, writerInstanceID: writerID,
                workspaceRevision: UInt64(events.count),
                entityRevisions: binding.expected.sorted { $0.identity.stableKey < $1.identity.stableKey })
            let envelope = try MutationEnvelopeV1(request: .init(
                mutationID: binding.mutationID, expectedRevision: expected, command: command),
                identity: .init(workspaceID: workspaceID, replicaID: replicaID))
            for image in binding.images { revisions[try image.identity] = image.revision }
            let resulting = try result(
                workspaceRevision: UInt64(events.count + 1), images: binding.images)
            let receipt = try MutationReceiptV1(identity: .init(
                workspaceID: workspaceID, replicaID: replicaID,
                localSequence: UInt64(events.count + 1)), envelope: envelope,
                resultingRevision: .init(resulting), postImages: binding.images,
                committedAt: RepetitiveCaptureSourcePackageFixture.date
                    .addingTimeInterval(Double(100 + events.count)))
            let event = Event(envelope: envelope, receipt: receipt,
                              reversalBasisData: nil, semanticReversalData: nil)
            events.append(event)
            return event
        }

        mutating func appendSemanticReversalPair(
            target targetCommand: WorkspaceCommandV1,
            reversal reversalCommand: WorkspaceCommandV1
        ) throws -> (target: Event, reversal: Event) {
            let targetBinding = try Self.binding(targetCommand)
            let targetExpected = try WorkspaceExpectedRevisionV1(
                workspaceID: workspaceID, generationID: generationID,
                writerInstanceID: writerID, workspaceRevision: UInt64(events.count),
                entityRevisions: targetBinding.expected.sorted {
                    $0.identity.stableKey < $1.identity.stableKey
                })
            let targetIdentity = MutationReceiptIdentityV1(
                workspaceID: workspaceID, replicaID: replicaID,
                localSequence: UInt64(events.count + 1))
            let plan = try SemanticReversalPlanV1(
                mutationID: targetBinding.mutationID, commandKind: targetCommand.kind,
                expectedRevision: targetExpected,
                prospectiveTargets: try targetBinding.images.map { try $0.identity },
                requiredSemanticValues: [.init(key: "c36-source", value: "original")],
                contentReferences: [], dependencyGraph: [], conflicts: [],
                compensatingCommands: [reversalCommand])
            let basis = try ReversalBasisV1(
                targetMutationID: targetBinding.mutationID,
                targetReceiptIdentity: targetIdentity, plan: plan)
            let replica = try WorkspaceReplicaIdentityV1(
                workspaceID: workspaceID, replicaID: replicaID)
            let targetEnvelope = try MutationEnvelopeV1(
                request: .init(mutationID: targetBinding.mutationID,
                    expectedRevision: targetExpected, command: targetCommand),
                identity: replica, reversalPlanDigest: basis.planDigest)
            for image in targetBinding.images { revisions[try image.identity] = image.revision }
            let targetResult = try result(
                workspaceRevision: UInt64(events.count + 1), images: targetBinding.images)
            let targetReceipt = try MutationReceiptV1(
                identity: targetIdentity, envelope: targetEnvelope,
                resultingRevision: .init(targetResult), postImages: targetBinding.images,
                committedAt: RepetitiveCaptureSourcePackageFixture.date
                    .addingTimeInterval(Double(100 + events.count)))
            let targetEvent = Event(
                envelope: targetEnvelope, receipt: targetReceipt,
                reversalBasisData: try basis.canonicalData(), semanticReversalData: nil)
            events.append(targetEvent)

            let reversalBinding = try Self.binding(reversalCommand)
            let reversalExpected = try WorkspaceExpectedRevisionV1(
                workspaceID: workspaceID, generationID: generationID,
                writerInstanceID: writerID, workspaceRevision: UInt64(events.count),
                entityRevisions: reversalBinding.expected.sorted {
                    $0.identity.stableKey < $1.identity.stableKey
                })
            let request = WorkspaceMutationRequestV1(
                mutationID: reversalBinding.mutationID,
                expectedRevision: reversalExpected, command: reversalCommand)
            let execution = try SemanticReversalExecutionV1(
                targetMutationID: targetBinding.mutationID,
                targetReceiptIdentity: targetIdentity,
                reversalBasisSHA256: basis.canonicalSHA256(),
                planDigest: basis.planDigest,
                compensatingMutationIDs: [reversalBinding.mutationID])
            let replay = try SemanticReversalReplayIdentityV1(
                request: request, identity: replica,
                targetMutationID: targetBinding.mutationID,
                planDigest: basis.planDigest,
                compensatingMutationIDs: [reversalBinding.mutationID]).canonicalSHA256()
            let reversalEnvelope = try MutationEnvelopeV1(
                request: request, identity: replica, sourceKind: .semanticReversal,
                causationMutationID: targetBinding.mutationID,
                semanticReversalReplayIdentitySHA256: replay,
                semanticReversalExecution: execution)
            for image in reversalBinding.images { revisions[try image.identity] = image.revision }
            let reversalResult = try result(
                workspaceRevision: UInt64(events.count + 1), images: reversalBinding.images)
            let reversalIdentity = MutationReceiptIdentityV1(
                workspaceID: workspaceID, replicaID: replicaID,
                localSequence: UInt64(events.count + 1))
            let reversalReceipt = try MutationReceiptV1(
                identity: reversalIdentity, envelope: reversalEnvelope,
                resultingRevision: .init(reversalResult), postImages: reversalBinding.images,
                reversesMutationID: targetBinding.mutationID,
                committedAt: RepetitiveCaptureSourcePackageFixture.date
                    .addingTimeInterval(Double(100 + events.count)))
            let semantic = try SemanticReversalReceiptV1(
                reversalReceiptIdentity: reversalIdentity,
                reversesMutationID: targetBinding.mutationID,
                targetReceiptIdentity: targetIdentity,
                reversalBasisSHA256: basis.canonicalSHA256(),
                planDigest: basis.planDigest,
                compensatingMutationIDs: [reversalBinding.mutationID],
                resultingRevision: reversalReceipt.resultingRevision)
            let reversalEvent = Event(
                envelope: reversalEnvelope, receipt: reversalReceipt,
                reversalBasisData: nil, semanticReversalData: try semantic.canonicalData())
            events.append(reversalEvent)
            return (targetEvent, reversalEvent)
        }

        private func result(workspaceRevision: UInt64, images: [MutationPostImageV1]) throws
            -> WorkspaceExpectedRevisionV1 {
            try WorkspaceExpectedRevisionV1(
                workspaceID: workspaceID, generationID: generationID,
                writerInstanceID: writerID, workspaceRevision: workspaceRevision,
                entityRevisions: try images.map {
                    .init(identity: try $0.identity, revision: $0.revision)
                }.sorted { $0.identity.stableKey < $1.identity.stableKey })
        }

        func snapshot(phaseTrace: ((String) -> Void)? = nil) throws -> MutationHistorySnapshotV1 {
            phaseTrace?("history-envelope-encoding-start")
            let receipts: [MutationHistoryReceiptRecordV1] = try events.map { event in
                .init(envelopeData: try event.envelope.canonicalData(),
                    receiptData: try event.receipt.canonicalData(),
                    reversalBasisData: event.reversalBasisData,
                    semanticReversalData: event.semanticReversalData)
            }
            phaseTrace?("history-envelope-encoding-complete")
            let value = MutationHistorySnapshotV1(
                workspaceRevision: UInt64(events.count), lastLocalSequence: UInt64(events.count),
                receipts: try RepetitiveCaptureSourcePackageFixture.canonicalReceipts(receipts),
                quarantines: [],
                entityRevisions: revisions.map { .init(identity: $0.key, revision: $0.value) }
                    .sorted { $0.identity.stableKey < $1.identity.stableKey })
            phaseTrace?("history-canonical-receipts-complete")
            try MutationJournalStoreV1.validateImportedSnapshot(value,
                                                                 sourcePersistentSchemaVersion: 45)
            phaseTrace?("history-snapshot-validation-complete")
            return value
        }

        private static func binding(_ command: WorkspaceCommandV1) throws
            -> (mutationID: MutationIDV1, expected: [WorkspaceEntityRevisionV1],
                images: [MutationPostImageV1]) {
            switch command {
            case let .applyRoundSession(value):
                return (value.mutationID,
                        [.init(identity: try value.concurrencyIdentity,
                               revision: value.expectedRevision)],
                        [try value.mutationPostImage])
            case let .applyFieldDraft(value):
                return (value.mutationID, try value.concurrencyIdentities.map {
                    .init(identity: $0, revision: try value.expectedRevision(for: $0))
                }, try value.postImage.mutationPostImages)
            default: throw WorkspaceMutationFailureV1.invalidCommand
            }
        }
    }

    private static func fieldMutation(_ checkpoint: FieldDraftCheckpointV1) throws
        -> FieldDraftMutationV1 {
        try .init(workspaceID: checkpoint.workspaceID, expectedRevision: 0,
                  expectedBaseCanonicalRevision: checkpoint.baseCanonicalRevision,
                  mutationID: checkpoint.mutationID, postImage: .createCheckpoint(checkpoint))
    }

    private static func checkpoint(id seed: Int, workspaceID: WorkspaceID,
                                   scope: DraftScopeKeyV1,
                                   payload: RepetitiveCaptureProgressDraftPayloadV2,
                                   anchor: DraftResumeAnchorV1) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: id(seed), workspaceID: workspaceID, scope: scope,
                  purpose: .repetitiveCapture, codec: RepetitiveCaptureProgressDraftCodecV2.release(),
                  baseCanonicalRevision: 0, draftRevision: 1,
                  payloadData: RepetitiveCaptureProgressDraftCodecV2.encode(payload), stageIDs: [],
                  resumeAnchor: anchor, state: .active, updatedAt: date,
                  mutationID: .init(rawValue: id(seed + 100)))
    }

    private static func revisedActiveSource(
        _ original: FieldDraftCheckpointV1,
        round: RoundSessionV1,
        revision: UInt64,
        mutationSeed: Int
    ) throws -> FieldDraftCheckpointV1 {
        let old = try RepetitiveCaptureProgressDraftCodecV2.source(original)
        let changedReadiness = try readiness(
            round: round, checkedAt: date.addingTimeInterval(Double(mutationSeed)))
        let changedLaunch = try RepetitiveCaptureLaunchSourceV2(
            planID: old.planID, round: round,
            readiness: round.items.map {
                try .init(manifest: changedReadiness, assetID: $0.selection.assetID)
            })
        return try revisedCheckpoint(
            original, revision: revision, state: .active,
            mutationID: .init(rawValue: id(mutationSeed)),
            payloadData: RepetitiveCaptureProgressDraftCodecV2.encode(.source(changedLaunch)))
    }

    private static func revisedCheckpoint(
        _ original: FieldDraftCheckpointV1,
        revision: UInt64,
        state: FieldDraftStateV1,
        mutationID: MutationIDV1,
        payloadData: Data
    ) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: original.draftID, workspaceID: original.workspaceID,
                  scope: original.scope, purpose: original.purpose, codec: original.codec,
                  baseCanonicalRevision: original.baseCanonicalRevision,
                  draftRevision: revision, payloadData: payloadData,
                  stageIDs: original.stageIDs, resumeAnchor: original.resumeAnchor,
                  state: state, updatedAt: date.addingTimeInterval(Double(revision + 5)),
                  mutationID: mutationID)
    }

    private static func row(_ checkpoint: FieldDraftCheckpointV1) throws
        -> V16BackupFieldDraftRecordV1 {
        .init(kind: .checkpoint, id: checkpoint.draftID,
              workspaceID: checkpoint.workspaceID.rawValue, revision: checkpoint.draftRevision,
              canonicalData: try FieldDraftCanonicalCodecV1.encode(checkpoint))
    }

    private static func rowLess(_ lhs: V16BackupFieldDraftRecordV1,
                                _ rhs: V16BackupFieldDraftRecordV1) -> Bool {
        let left = "\(lhs.kind.rawValue)\u{0}\(lhs.id.uuidString.lowercased())"
        let right = "\(rhs.kind.rawValue)\u{0}\(rhs.id.uuidString.lowercased())"
        return left < right
    }

    private static func visiting(items: [RoundItemV1], index: Int, actor: ActorSnapshotV1) throws
        -> [RoundItemV1] {
        var result = items
        let old = result[index]
        result[index] = try .init(itemID: old.itemID, order: old.order,
            selection: old.selection, requirement: old.requirement, disposition: .visited,
            visit: .init(visitedAt: date.addingTimeInterval(3), recordedBy: actor))
        return result
    }

    private static func deferring(items: [RoundItemV1], index: Int) throws -> [RoundItemV1] {
        var result = items
        let old = result[index]
        result[index] = try .init(itemID: old.itemID, order: old.order,
            selection: old.selection, requirement: old.requirement, disposition: .deferred,
            visit: old.visit, reason: .userDeferred)
        return result
    }

    private static func readiness(round: RoundSessionV1,
                                  checkedAt: Date = date) throws -> OfflineReadinessManifestV1 {
        let package = try RoundPackageReleaseReferenceV1(
            packageReleaseID: String(repeating: "a", count: 64), packageID: "c36-source",
            packageContentVersion: 1, packageSHA256: String(repeating: "a", count: 64),
            workflowSHA256: String(repeating: "b", count: 64))
        return try OfflineReadinessManifestBuilderV1.build(snapshot: .init(
            session: round.reference, expectedPackage: package, observedPackage: package,
            selectedAssets: round.items.map(\.selection).sorted {
                $0.assetID.uuidString < $1.assetID.uuidString
            }, observedAssetIDs: Set(round.items.map { $0.selection.assetID }),
            guidanceReferenceIDs: [], availableGuidanceReferenceIDs: [],
            contentRequirements: [], contentObservations: [], expectedFieldReferences: [],
            fieldReferenceReadiness: [], storage: .init(capacityState: .checked,
                                                        availableBytes: 100_000),
            access: .init(protectedDataAvailable: true), checkedAt: checkedAt,
            timeZoneIdentifier: "America/New_York", clockState: .checked))
    }

    private static func actor(_ workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        let value = try LocalActorReferenceV1(actorReferenceID: id(5), workspaceID: workspaceID,
                                               displayName: "C36 source")
        return try .init(snapshotID: id(6), workspaceID: workspaceID, actor: value,
                         responsibility: .recordedBy, displayNameAtTime: "C36 source",
                         capturedAt: date)
    }

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", value))!
    }
}

private extension JSONEncoder {
    static var canonicalV1: JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        value.dateEncodingStrategy = .millisecondsSince1970
        return value
    }
}

private extension JSONDecoder {
    static var canonicalV1: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .millisecondsSince1970
        return value
    }
}
