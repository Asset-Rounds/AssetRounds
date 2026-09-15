import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V23CheckRunnerBeginReceiptReferenceTests: XCTestCase {
    func testBothBeginRolesDeriveEveryReferenceFieldFromOriginalReceipt() throws {
        for record in [false, true] {
            let evidence = try receiptReferenceEvidence(record: record)
            let originalEnvelope = try evidence.envelope.canonicalData()
            let originalReceipt = try evidence.receipt.canonicalData()
            let reference = try CheckRunnerBeginReceiptReferenceV1(evidence: evidence)
            let image = try XCTUnwrap(evidence.receipt.postImages.first)
            XCTAssertEqual(reference.workspaceID, evidence.envelope.workspaceID)
            XCTAssertEqual(reference.mutationID, evidence.envelope.mutationID)
            XCTAssertEqual(reference.receiptIdentity, evidence.receipt.identity)
            XCTAssertEqual(reference.envelopeSHA256, try evidence.envelope.canonicalSHA256())
            XCTAssertEqual(reference.commandBodySHA256, evidence.envelope.commandBodySHA256)
            XCTAssertEqual(reference.resultSHA256, evidence.receipt.resultSHA256)
            XCTAssertEqual(reference.expectedWorkspaceRevision, 40)
            XCTAssertEqual(reference.resultingWorkspaceRevision, 41)
            XCTAssertEqual(reference.beginPostimageIdentity, try image.identity)
            XCTAssertEqual(reference.beginPostimageRevision, record ? 1 : 9)
            XCTAssertEqual(reference.beginPostimageSemanticSHA256, String(repeating: "f", count: 64))
            XCTAssertEqual(reference.committedAt, Date(timeIntervalSince1970: 1_725_555_120))
            XCTAssertEqual(reference.sourceKind, .importedHistory)
            let data = try FieldDraftCanonicalCodecV1.encode(reference)
            let decoded = try FieldDraftCanonicalCodecV1.decode(CheckRunnerBeginReceiptReferenceV1.self, from: data)
            XCTAssertEqual(decoded, reference)
            try decoded.validate(evidence: evidence)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), data)
            XCTAssertEqual(try receiptReferenceJSON(receiptReferenceObject(reference)), data)
            XCTAssertEqual(try receiptReferenceObject(reference).keys.sorted(), [
                "beginPostimageIdentity", "beginPostimageRevision", "beginPostimageSemanticSHA256",
                "commandBodySHA256", "committedAt", "envelopeSHA256", "expectedWorkspaceRevision",
                "mutationID", "receiptIdentity", "resultSHA256", "resultingWorkspaceRevision", "sourceKind", "workspaceID"
            ])
            XCTAssertEqual(try evidence.envelope.canonicalData(), originalEnvelope)
            XCTAssertEqual(try evidence.receipt.canonicalData(), originalReceipt)
        }
    }

    func testShapeValidSubstitutionsCannotReplaceExactBeginProvenance() throws {
        let evidence = try receiptReferenceEvidence(record: true)
        let reference = try CheckRunnerBeginReceiptReferenceV1(evidence: evidence)
        let original = try FieldDraftCanonicalCodecV1.encode(reference)
        let base = try receiptReferenceObject(reference)
        var variants: [[String: Any]] = []
        for key in ["envelopeSHA256", "commandBodySHA256", "resultSHA256", "beginPostimageSemanticSHA256"] {
            var changed = base
            changed[key] = String(repeating: "a", count: 64)
            variants.append(changed)
        }
        var nextWorkspace = base
        nextWorkspace["expectedWorkspaceRevision"] = 41
        nextWorkspace["resultingWorkspaceRevision"] = 42
        variants.append(nextWorkspace)
        var nextTarget = base
        nextTarget["beginPostimageRevision"] = 2
        nextTarget["beginPostimageSemanticSHA256"] = String(repeating: "b", count: 64)
        variants.append(nextTarget)
        var nextTime = base
        nextTime["committedAt"] = 1_725_555_121_000 as Int64
        variants.append(nextTime)
        var nextKind = base
        nextKind["sourceKind"] = MutationSourceKindV1.localRecovery.rawValue
        variants.append(nextKind)
        var nextMutation = base
        nextMutation["mutationID"] = receiptReferenceID(90).uuidString
        variants.append(nextMutation)
        var nextReceipt = base
        var identity = try XCTUnwrap(base["receiptIdentity"] as? [String: Any])
        identity["localSequence"] = 78
        nextReceipt["receiptIdentity"] = identity
        variants.append(nextReceipt)
        var nextReplica = base
        identity = try XCTUnwrap(base["receiptIdentity"] as? [String: Any])
        identity["replicaID"] = ["rawValue": receiptReferenceID(91).uuidString]
        nextReplica["receiptIdentity"] = identity
        variants.append(nextReplica)
        var nextID = base
        var target = try XCTUnwrap(base["beginPostimageIdentity"] as? [String: Any])
        target["id"] = receiptReferenceID(92).uuidString
        nextID["beginPostimageIdentity"] = target
        variants.append(nextID)
        var nextRole = base
        target = try XCTUnwrap(base["beginPostimageIdentity"] as? [String: Any])
        target["kind"] = WorkspaceEntityKindV1.site.rawValue
        nextRole["beginPostimageIdentity"] = target
        variants.append(nextRole)
        var nextNamespace = base
        identity = try XCTUnwrap(base["receiptIdentity"] as? [String: Any])
        let workspace: [String: Any] = ["rawValue": receiptReferenceID(93).uuidString]
        identity["workspaceID"] = workspace
        nextNamespace["workspaceID"] = workspace
        nextNamespace["receiptIdentity"] = identity
        variants.append(nextNamespace)

        for changed in variants {
            let decoded = try receiptReferenceDecode(changed)
            try decoded.validate()
            XCTAssertThrowsError(try decoded.validate(evidence: evidence)) { error in
                XCTAssertEqual(error as? CheckRunnerRestoreBeginFailureV1, .invalidEvidence)
            }
        }
        XCTAssertThrowsError(try reference.validate(evidence: receiptReferenceEvidence(record: false)))
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(reference), original)
        // The next-target variant above is only a candidate current observation.
        // This pure reference test does not authenticate any successor lineage.
        XCTAssertEqual(reference.beginPostimageRevision, 1)
    }

    func testClosedReferenceRejectsMalformedShapeAndNestedIdentityKeys() throws {
        let reference = try CheckRunnerBeginReceiptReferenceV1(evidence: receiptReferenceEvidence(record: false))
        let base = try receiptReferenceObject(reference)
        XCTAssertEqual(try receiptReferenceJSON(base), try FieldDraftCanonicalCodecV1.encode(reference))
        var variants: [[String: Any]] = []
        var unknown = base
        unknown["future"] = true
        variants.append(unknown)
        for key in base.keys {
            var missing = base
            missing.removeValue(forKey: key)
            variants.append(missing)
        }
        for (key, value) in [
            ("beginPostimageRevision", 0 as Any),
            ("resultingWorkspaceRevision", 40 as Any),
            ("expectedWorkspaceRevision", NSNumber(value: UInt64.max) as Any),
            ("sourceKind", "FUTURE" as Any),
            ("resultSHA256", String(repeating: "A", count: 64) as Any),
        ] {
            var changed = base
            changed[key] = value
            variants.append(changed)
        }
        for key in ["workspaceID", "receiptIdentity", "beginPostimageIdentity"] {
            var changed = base
            var nested = try XCTUnwrap(base[key] as? [String: Any])
            nested["future"] = true
            changed[key] = nested
            variants.append(changed)
        }
        for key in ["workspaceID", "replicaID"] {
            var changed = base
            var receipt = try XCTUnwrap(base["receiptIdentity"] as? [String: Any])
            var nested = try XCTUnwrap(receipt[key] as? [String: Any])
            nested["future"] = true
            receipt[key] = nested
            changed["receiptIdentity"] = receipt
            variants.append(changed)
        }
        var wrongRole = base
        var target = try XCTUnwrap(base["beginPostimageIdentity"] as? [String: Any])
        target["kind"] = WorkspaceEntityKindV1.asset.rawValue
        wrongRole["beginPostimageIdentity"] = target
        variants.append(wrongRole)
        var wrongWorkspace = base
        wrongWorkspace["workspaceID"] = ["rawValue": receiptReferenceID(94).uuidString]
        variants.append(wrongWorkspace)
        var zeroSequence = base
        var receipt = try XCTUnwrap(base["receiptIdentity"] as? [String: Any])
        receipt["localSequence"] = 0
        zeroSequence["receiptIdentity"] = receipt
        variants.append(zeroSequence)
        for changed in variants {
            // Direct decoding proves semantic closure independently of the
            // outer canonical-byte equality check.
            XCTAssertThrowsError(try receiptReferenceDecode(changed))
        }
    }
}

private func receiptReferenceEvidence(record: Bool) throws -> CheckRunnerBeginCommittedEvidenceV1 {
    let workspace = WorkspaceID(rawValue: receiptReferenceID(1))
    let replica = ReplicaID(rawValue: receiptReferenceID(2))
    let generation = receiptReferenceID(3)
    let writer = receiptReferenceID(4)
    let targetID = receiptReferenceID(record ? 5 : 6)
    let target = try WorkspaceEntityIdentityV1(kind: record ? .workflowRecord : .site, id: targetID)
    let asset = try WorkspaceEntityIdentityV1(kind: .asset, id: receiptReferenceID(7))
    let before = try WorkspaceExpectedRevisionV1(workspaceID: workspace, generationID: generation,
        writerInstanceID: writer, workspaceRevision: 40,
        entityRevisions: [.init(identity: target, revision: record ? 0 : 8), .init(identity: asset, revision: 19)])
    let observedAt = Date(timeIntervalSince1970: 1_725_555_000)
    let command: WorkspaceCommandV1
    if record {
        command = .createCheckDraft(CheckDraftMutationV1(recordID: targetID, assetID: asset.id,
            issueID: nil, parentRecordID: nil, stage: WorkflowStage.check.rawValue,
            draftStepKey: WorkflowDraftStep.wide.rawValue, startedAt: observedAt,
            observedAtUTC: observedAt, timeZoneID: "America/New_York", utcOffsetMinutes: -240,
            localDate: "2024-09-05", localTime: "12:50", afterDarkAcknowledgementKey: "after-dark",
            afterDarkAcknowledgementCopy: "After dark", afterDarkAcknowledgementVersion: "1",
            afterDarkAcknowledgementAccepted: true, safePositionAcknowledgementKey: "safe-position",
            safePositionAcknowledgementCopy: "Safe position", safePositionAcknowledgementVersion: "1",
            safePositionAcknowledgementAccepted: true, packID: "fixture.pack", packSchemaVersion: 1,
            packContentVersion: 1, pdfTemplateID: "fixture.template", pdfTemplateVersion: 1))
    } else {
        command = .updateSiteTimeZone(SiteTimeZoneMutationV1(siteID: targetID,
            timeZoneID: "America/New_York", confirmedAt: observedAt))
    }
    let envelope = try MutationEnvelopeV1(request: WorkspaceMutationRequestV1(
        mutationID: MutationIDV1(rawValue: targetID), expectedRevision: before, command: command),
        identity: WorkspaceReplicaIdentityV1(workspaceID: workspace, replicaID: replica),
        sourceKind: .importedHistory, contentDependencyIDs: [])
    let after = try MutationPortableExpectedRevisionV1(WorkspaceExpectedRevisionV1(
        workspaceID: workspace, generationID: generation, writerInstanceID: writer, workspaceRevision: 41,
        entityRevisions: [.init(identity: target, revision: record ? 1 : 9), .init(identity: asset, revision: 19)]))
    let image: MutationPostImageV1 = record
        ? .workflowRecord(id: targetID, revision: 1, semanticSHA256: String(repeating: "f", count: 64))
        : .site(id: targetID, revision: 9, semanticSHA256: String(repeating: "f", count: 64))
    let receipt = try MutationReceiptV1(identity: MutationReceiptIdentityV1(
        workspaceID: workspace, replicaID: replica, localSequence: 77), envelope: envelope,
        resultingRevision: after, postImages: [image], committedAt: Date(timeIntervalSince1970: 1_725_555_120))
    // Valid typed fixture bytes only; no persistent journal is claimed here.
    return try CheckRunnerBeginCommittedEvidenceV1(envelope: envelope, receipt: receipt)
}

private func receiptReferenceObject(_ reference: CheckRunnerBeginReceiptReferenceV1) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: FieldDraftCanonicalCodecV1.encode(reference)) as? [String: Any])
}

private func receiptReferenceJSON(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}

private func receiptReferenceDecode(_ object: [String: Any]) throws -> CheckRunnerBeginReceiptReferenceV1 {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return try decoder.decode(CheckRunnerBeginReceiptReferenceV1.self, from: receiptReferenceJSON(object))
}

private func receiptReferenceID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", value))!
}
