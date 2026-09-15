import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V23CheckRunnerItemFieldContractsTests: XCTestCase {
    private let pack = SignPack.illuminatedSignV1
    private var profile: WorkspacePackageLifecycleProfileV1 {
        get throws { try WorkspacePackageLifecycleCompatibilityV1.shippingProfile() }
    }
    private var legacyProfile: WorkspacePackageLifecycleProfileV1 {
        get throws { try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: pack) }
    }

    func testAllSixSnapshotsUseShippingResolverAndCheckRecheckMatrix() throws {
        let label = try XCTUnwrap(pack.issueLabels.first)
        let reason = try XCTUnwrap(pack.couldNotVerifyReasons.entries.first)
        let cases: [(CheckOutcomeSelection, WorkflowStage)] = [
            (.noVisibleIssue, .check), (.visibleIssue(labelKey: label.key), .check),
            (.couldNotVerify(reasonKey: reason.key, note: "note"), .check),
            (.couldNotVerify(reasonKey: reason.key, note: "note"), .recheck),
            (.resolved(note: "note"), .recheck), (.issueStillVisible(note: "note"), .recheck),
            (.originalResolvedDifferentIssue(labelKey: label.key, note: "note"), .recheck),
        ]
        for (selection, stage) in cases {
            let snapshot = try CheckRunnerOutcomeSnapshotV1(selection: selection, stage: stage,
                signPack: pack, activeLifecycleProfile: { try self.profile })
            let resolved = try snapshot.resolve(stage: stage, signPack: pack,
                activeLifecycleProfile: { try self.profile })
            XCTAssertEqual(snapshot.selection, resolved.selection)
            XCTAssertThrowsError(try snapshot.resolve(stage: .work, signPack: pack,
                activeLifecycleProfile: { try self.profile }))
        }
        XCTAssertThrowsError(try CheckRunnerOutcomeSnapshotV1(selection: .resolved(note: nil),
            stage: .check, signPack: pack, activeLifecycleProfile: { try self.profile }))
        XCTAssertThrowsError(try CheckRunnerOutcomeSnapshotV1(selection: .noVisibleIssue,
            stage: .recheck, signPack: pack, activeLifecycleProfile: { try self.profile }))
        XCTAssertThrowsError(try CheckRunnerOutcomeSnapshotV1(
            selection: .visibleIssue(labelKey: label.key), stage: .recheck,
            signPack: pack, activeLifecycleProfile: { try self.profile }))
        for selection in [CheckOutcomeSelection.resolved(note: nil), .issueStillVisible(note: nil),
                          .originalResolvedDifferentIssue(labelKey: label.key, note: nil)] {
            XCTAssertThrowsError(try CheckRunnerOutcomeSnapshotV1(selection: selection,
                stage: .check, signPack: pack, activeLifecycleProfile: { try self.profile }))
        }
    }

    func testSnapshotsHaveExactCanonicalRoundTripAndResolverInverse() throws {
        let label = try XCTUnwrap(pack.issueLabels.first)
        let reason = try XCTUnwrap(pack.couldNotVerifyReasons.entries.first)
        let cases: [(CheckOutcomeSelection, WorkflowStage)] = [
            (.noVisibleIssue, .check), (.visibleIssue(labelKey: label.key), .check),
            (.couldNotVerify(reasonKey: reason.key, note: "field note"), .check),
            (.resolved(note: "field note"), .recheck),
            (.issueStillVisible(note: "field note"), .recheck),
            (.originalResolvedDifferentIssue(labelKey: label.key, note: "field note"), .recheck),
        ]
        for (selection, stage) in cases {
            let expected = try CheckRunnerOutcomeResolverV1.resolve(selection, signPack: pack,
                activeLifecycleProfile: { try self.legacyProfile })
            let value = try CheckRunnerOutcomeSnapshotV1(selection: selection, stage: stage,
                signPack: pack, activeLifecycleProfile: { try self.legacyProfile })
            let bytes = try FieldDraftCanonicalCodecV1.encode(value)
            let decoded = try FieldDraftCanonicalCodecV1.decode(CheckRunnerOutcomeSnapshotV1.self, from: bytes)
            XCTAssertEqual(decoded, value)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), bytes)
            XCTAssertEqual(try decoded.resolve(stage: stage, signPack: pack,
                activeLifecycleProfile: { try self.legacyProfile }), expected)
        }
    }

    func testInverseRejectsEveryStaleDisplayKeyVersionAndNoncanonicalNoteClaim() throws {
        let label = try XCTUnwrap(pack.issueLabels.first)
        let reason = try XCTUnwrap(pack.couldNotVerifyReasons.entries.first)
        let bases: [(CheckOutcomeSelection, WorkflowStage, [(String, Any)])] = [
            (.noVisibleIssue, .check, [("outcomeKey", "wrong"), ("outcomeDisplay", "wrong")]),
            (.visibleIssue(labelKey: label.key), .check,
             [("issueLabelKey", "wrong"), ("issueLabelDisplay", "wrong")]),
            (.couldNotVerify(reasonKey: reason.key, note: nil), .check,
             [("reasonKey", "wrong"), ("reasonDisplay", "wrong"),
              ("reasonRegistryVersion", "stale")]),
            (.resolved(note: "field note"), .recheck, [("note", " padded ")]),
        ]
        for (selection, stage, mutations) in bases {
            let valid = try CheckRunnerOutcomeSnapshotV1(selection: selection, stage: stage,
                signPack: pack, activeLifecycleProfile: { try self.profile })
            let original = try XCTUnwrap(JSONSerialization.jsonObject(
                with: FieldDraftCanonicalCodecV1.encode(valid)) as? [String: Any])
            for (key, replacement) in mutations {
                var object = original
                object[key] = replacement
                let bytes = try canonical(object)
                let hostile = try FieldDraftCanonicalCodecV1.decode(
                    CheckRunnerOutcomeSnapshotV1.self, from: bytes)
                XCTAssertThrowsError(try hostile.resolve(stage: stage, signPack: pack,
                    activeLifecycleProfile: { try self.profile }))
            }
        }
    }

    func testPrepareProjectsRawNotesWithoutMutatingEditorOrIrrelevantFields() throws {
        let reason = try XCTUnwrap(pack.couldNotVerifyReasons.entries.first)
        let thousand = String(repeating: "e\u{301}", count: 1000)
        let label = try XCTUnwrap(pack.issueLabels.first)
        let noteCases: [(CheckRunnerEditableSelectionV1, WorkflowStage, Bool)] = [
            (.couldNotVerify(reasonKey: reason.key, note: nil), .check, true),
            (.resolved(note: nil), .recheck, false), (.issueStillVisible(note: nil), .recheck, false),
            (.originalResolvedDifferentIssue(labelKey: label.key, note: nil), .recheck, false),
        ]
        for (selection, stage, usesCNV) in noteCases {
            let validNotes: [(String, String?)] = [
                (" \nfield\t ", "field"), (" \n\t ", nil), (thousand, thousand),
            ]
            for (raw, expected) in validNotes {
                let editor = CheckRunnerEditableOutcomeV1(selection: selection, choice: .visibleIssue,
                    selectedCouldNotVerifyReasonKey: "irrelevant",
                    couldNotVerifyNote: usesCNV ? raw : "irrelevant bytes",
                    recheckNote: usesCNV ? "irrelevant bytes" : raw, startsWithCouldNotVerify: true)
                let before = editor
                let prepared = try CheckRunnerOutcomeSnapshotV1.prepare(editor: editor, stage: stage,
                    signPack: pack, activeLifecycleProfile: { try self.profile })
                XCTAssertEqual(prepared.selection.note, expected)
                XCTAssertEqual(prepared.selection.note.map { Data($0.utf8) },
                    expected.map { Data($0.utf8) })
                XCTAssertEqual(editor, before)
                XCTAssertEqual(Data(editor.couldNotVerifyNote.utf8), Data(before.couldNotVerifyNote.utf8))
                XCTAssertEqual(Data(editor.recheckNote.utf8), Data(before.recheckNote.utf8))
            }
            let overflow = thousand + "e\u{301}"
            let editor = CheckRunnerEditableOutcomeV1(selection: selection,
                couldNotVerifyNote: usesCNV ? overflow : "irrelevant",
                recheckNote: usesCNV ? "irrelevant" : overflow)
            XCTAssertThrowsError(try CheckRunnerOutcomeSnapshotV1.prepare(editor: editor, stage: stage,
                signPack: pack, activeLifecycleProfile: { try self.profile }))
            XCTAssertEqual(usesCNV ? editor.couldNotVerifyNote : editor.recheckNote, overflow)
        }
        let none = CheckRunnerEditableOutcomeV1(selection: nil, couldNotVerifyNote: "keep", recheckNote: "keep too")
        XCTAssertThrowsError(try CheckRunnerOutcomeSnapshotV1.prepare(editor: none, stage: .check,
            signPack: pack, activeLifecycleProfile: { try self.profile }))
        for selection in [CheckRunnerEditableSelectionV1.noVisibleIssue,
                          .visibleIssue(labelKey: label.key)] {
            let irrelevant = CheckRunnerEditableOutcomeV1(selection: selection,
                couldNotVerifyNote: thousand + "x", recheckNote: thousand + "x")
            XCTAssertNoThrow(try CheckRunnerOutcomeSnapshotV1.prepare(editor: irrelevant, stage: .check,
                signPack: pack, activeLifecycleProfile: { try self.profile }))
            XCTAssertEqual(irrelevant.couldNotVerifyNote.count, 1001)
        }
    }

    func testPendingAndCommittedSlotsValidateExactPurposeAndSameChildReplacement() throws {
        let pending = pendingSlot(id: id(1), step: .wide)
        try pending.validate()
        XCTAssertNil(pending.evidenceID)
        let committed = try committedSlot(child: id(1), evidence: id(2), step: .wide)
        try committed.validate()
        try committed.validateReplacement(of: pending)
        for slot in [pending, committed] {
            let bytes = try FieldDraftCanonicalCodecV1.encode(slot)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.decode(CheckRunnerPhotoSlotV1.self,
                from: bytes), slot)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(slot), bytes)
        }
        XCTAssertThrowsError(try committed.validateReplacement(of: pendingSlot(id: id(3), step: .wide)))
        XCTAssertThrowsError(try pending.validateReplacement(of: pending))
        XCTAssertThrowsError(try pending.validateReplacement(of: committed))
        XCTAssertThrowsError(try pendingSlot(id: id(1), step: .wide, purpose: "close_detail").validate())
        XCTAssertThrowsError(try pendingSlot(id: id(1), step: .outcome, purpose: "wide_context").validate())
    }

    func testTwoSlotsRequireDistinctChildAndEvidenceIdentitiesAndValidLinkage() throws {
        let wide = try committedSlot(child: id(1), evidence: id(2), step: .wide)
        let close = try committedSlot(child: id(3), evidence: id(4), step: .close)
        XCTAssertNoThrow(try CheckRunnerPhotoSlotV1.validateSlots(wideContext: nil, closeDetail: nil))
        XCTAssertNoThrow(try CheckRunnerPhotoSlotV1.validateSlots(wideContext: wide, closeDetail: nil))
        try CheckRunnerPhotoSlotV1.validateSlots(wideContext: wide, closeDetail: close)
        XCTAssertThrowsError(try CheckRunnerPhotoSlotV1.validateSlots(
            wideContext: pendingSlot(id: id(1), step: .wide),
            closeDetail: pendingSlot(id: id(1), step: .close)))
        XCTAssertThrowsError(try CheckRunnerPhotoSlotV1.validateSlots(wideContext: wide,
            closeDetail: try committedSlot(child: id(3), evidence: id(2), step: .close)))
        XCTAssertThrowsError(try CheckRunnerPhotoSlotV1.validateSlots(wideContext: wide,
            closeDetail: pendingSlot(id: id(2), step: .close)))
        XCTAssertThrowsError(try CheckRunnerPhotoSlotV1.validateSlots(wideContext: close, closeDetail: wide))
        XCTAssertThrowsError(try committedSlot(child: id(1), evidence: id(1), step: .wide).validate())
        XCTAssertThrowsError(try committedSlot(child: id(1), evidence: id(2), step: .wide,
            revision: 0).validate())
        XCTAssertThrowsError(try committedSlot(child: id(1), evidence: id(2), step: .wide,
            digest: "bad").validate())
        XCTAssertThrowsError(try committedSlot(child: id(1), evidence: id(2), step: .wide,
            target: id(9)).validate())
        XCTAssertThrowsError(try pendingSlot(id: id(0), step: .wide).validate())
    }

    func testClosedSnapshotDecoderRejectsUnknownTagKeyAssociatedMissingAndType() throws {
        let valid = try canonical(["tag": "NO_VISIBLE_ISSUE", "outcomeKey": "x", "outcomeDisplay": "y"])
        let objects: [[String: Any]] = [
            ["tag": "FUTURE", "outcomeKey": "x", "outcomeDisplay": "y"],
            ["tag": "NO_VISIBLE_ISSUE", "outcomeKey": "x", "outcomeDisplay": "y", "future": true],
            ["tag": "NO_VISIBLE_ISSUE", "outcomeKey": "x", "outcomeDisplay": "y", "note": "x"],
            ["tag": "VISIBLE_ISSUE", "outcomeKey": "x", "outcomeDisplay": "y", "issueLabelKey": "x"],
            ["tag": "NO_VISIBLE_ISSUE", "outcomeKey": 7, "outcomeDisplay": "y"],
        ]
        XCTAssertNoThrow(try JSONDecoder().decode(CheckRunnerOutcomeSnapshotV1.self, from: valid))
        for object in objects {
            let bytes = try canonical(object)
            XCTAssertThrowsError(try JSONDecoder().decode(CheckRunnerOutcomeSnapshotV1.self, from: bytes))
            XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(CheckRunnerOutcomeSnapshotV1.self, from: bytes))
        }
    }

    func testClosedPhotoSlotDecoderRejectsUnknownTagKeyAssociatedMissingAndType() throws {
        let base: [String: Any] = ["tag": "PENDING", "childDraftID": id(1).uuidString.lowercased(),
            "captureStep": "wide", "purposeKey": "wide_context"]
        var objects: [[String: Any]] = []
        objects.append(base.merging(["tag": "FUTURE"]) { _, new in new })
        objects.append(base.merging(["future": true]) { _, new in new })
        objects.append(base.merging(["evidenceID": id(2).uuidString.lowercased()]) { _, new in new })
        objects.append(base.filter { $0.key != "purposeKey" })
        objects.append(base.merging(["captureStep": 7]) { _, new in new })
        for object in objects {
            let bytes = try canonical(object)
            XCTAssertThrowsError(try JSONDecoder().decode(CheckRunnerPhotoSlotV1.self, from: bytes))
            XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(CheckRunnerPhotoSlotV1.self, from: bytes))
        }
    }

    func testAllSemanticAnchorsProduceExactResumeAnchorStrings() throws {
        let assetID = id(42)
        let expected = ["preflight", "wide_context", "close_detail", "outcome", "review"]
        XCTAssertEqual(CheckRunnerItemSemanticAnchorV1.allCases.count, expected.count)
        for (anchor, section) in zip(CheckRunnerItemSemanticAnchorV1.allCases, expected) {
            let resume = try anchor.resumeAnchor(assetID: assetID)
            XCTAssertEqual(resume.sectionID, section)
            XCTAssertEqual(resume.selectedStableID, assetID.uuidString.lowercased())
        }
        XCTAssertThrowsError(try JSONDecoder().decode(CheckRunnerItemSemanticAnchorV1.self,
            from: Data("\"FUTURE\"".utf8)))
        XCTAssertThrowsError(try CheckRunnerItemSemanticAnchorV1.preflight.resumeAnchor(assetID: id(0)))
    }

    func testParentPayloadBeginStatesRoundTripAndBindAllReceiptFields() throws {
        for includesTimeZone in [false, true] {
            let fixture = try parentFixture(recheck: false, includesTimeZone: includesTimeZone)
            let states: [CheckRunnerBeginStateV1] = [
                .notBegun,
                .prepared(attempt: fixture.attempt),
                .bound(attempt: fixture.attempt, workflowReceiptReference: fixture.workflowReference,
                    timeZoneReceiptReference: fixture.timeZoneReference),
            ]
            for state in states {
                let field = try parentField(begin: state)
                let payload = try CheckRunnerItemDraftPayloadV1(editing: fixture.source, field: field)
                let bytes = try CheckRunnerItemDraftPayloadV1.encode(payload)
                let decoded = try CheckRunnerItemDraftPayloadV1.decode(bytes)
                XCTAssertEqual(decoded, payload)
                XCTAssertEqual(try CheckRunnerItemDraftPayloadV1.encode(decoded), bytes)
            }
            let object = try jsonObject(fixture.workflowReference)
            XCTAssertEqual(Set(object.keys), Set([
                "workspaceID", "mutationID", "receiptIdentity", "envelopeSHA256",
                "commandBodySHA256", "resultSHA256", "expectedWorkspaceRevision",
                "resultingWorkspaceRevision", "beginPostimageIdentity", "beginPostimageRevision",
                "beginPostimageSemanticSHA256", "committedAt", "sourceKind",
            ]))
            XCTAssertEqual(fixture.workflowReference.commandBodySHA256,
                try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.createCheckDraft(fixture.attempt.recordCommand)))
            XCTAssertEqual(fixture.workflowReference.beginPostimageRevision, 1)
            XCTAssertEqual(fixture.workflowEvidence.receipt.expectedRevision.entityRevisions.map(\.identity.stableKey),
                fixture.workflowEvidence.receipt.expectedRevision.entityRevisions.map(\.identity.stableKey).sorted())
            XCTAssertEqual(fixture.workflowEvidence.receipt.resultingRevision.entityRevisions.map(\.identity.stableKey),
                fixture.workflowEvidence.receipt.resultingRevision.entityRevisions.map(\.identity.stableKey).sorted())
            if let frozen = fixture.attempt.timeZone, let reference = fixture.timeZoneReference {
                XCTAssertEqual(reference.commandBodySHA256,
                    try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.updateSiteTimeZone(frozen.command)))
                XCTAssertEqual(reference.beginPostimageRevision, frozen.expectedSiteRevision + 1)
            } else {
                XCTAssertNil(fixture.timeZoneReference)
            }
        }
    }

    func testParentPayloadRejectsSingleFieldBeginReferenceAndSourceForgeries() throws {
        let fixture = try parentFixture(recheck: false, includesTimeZone: true)
        let field = try parentField(begin: .bound(attempt: fixture.attempt,
            workflowReceiptReference: fixture.workflowReference,
            timeZoneReceiptReference: fixture.timeZoneReference))
        let payload = try CheckRunnerItemDraftPayloadV1(editing: fixture.source, field: field)
        let valid = try jsonObject(payload)
        let paths: [([String], Any)] = [
            (["field", "begin", "workflowReceiptReference", "workspaceID", "rawValue"], largeID(900).uuidString),
            (["field", "begin", "workflowReceiptReference", "mutationID"], largeID(901).uuidString),
            (["field", "begin", "workflowReceiptReference", "receiptIdentity", "workspaceID", "rawValue"],
                largeID(903).uuidString),
            (["field", "begin", "workflowReceiptReference", "envelopeSHA256"], "bad"),
            (["field", "begin", "workflowReceiptReference", "commandBodySHA256"], String(repeating: "0", count: 64)),
            (["field", "begin", "workflowReceiptReference", "resultSHA256"], "bad"),
            (["field", "begin", "workflowReceiptReference", "beginPostimageIdentity", "kind"], "SITE"),
            (["field", "begin", "workflowReceiptReference", "beginPostimageRevision"], 2),
            (["field", "begin", "workflowReceiptReference", "beginPostimageSemanticSHA256"], "bad"),
            (["field", "begin", "workflowReceiptReference", "committedAt"], 1),
            (["field", "begin", "timeZoneReceiptReference", "resultingWorkspaceRevision"], 99),
            (["field", "begin", "timeZoneReceiptReference", "beginPostimageRevision"], 8),
            (["source", "assetID"], largeID(902).uuidString),
        ]
        for (path, replacement) in paths {
            var hostile = valid
            try setJSON(&hostile, path: path, value: replacement)
            XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile)), "\(path)")
        }
        for path in [
            ["field", "begin", "workflowReceiptReference", "commandBodySHA256"],
            ["field", "begin", "workflowReceiptReference"],
            ["field", "begin", "attempt"],
        ] {
            var hostile = valid
            try removeJSON(&hostile, path: path)
            XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile)), "\(path)")
        }
        var unknown = valid
        try setJSON(&unknown, path: ["field", "begin", "workflowReceiptReference", "future"], value: true)
        XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(unknown)))
    }

    func testParentPayloadPreservesRawEditableBytesAnchorsAndSlots() throws {
        let fixture = try parentFixture(recheck: false, includesTimeZone: false)
        let bound = CheckRunnerBeginStateV1.bound(attempt: fixture.attempt,
            workflowReceiptReference: fixture.workflowReference, timeZoneReceiptReference: nil)
        let rawCases: [(String, String, String, String?)] = [
            ("", "", "", nil),
            (" America/New_York ", "  padded\n", "\tother ", " America/New_York "),
            ("e\u{301}", "e\u{301}", String(repeating: "n", count: 2_001), "e\u{301}"),
            ("bad\u{0001}zone", "control\u{0000}note", "overflow\u{0007}", "bad\u{0001}zone"),
        ]
        for anchor in CheckRunnerItemSemanticAnchorV1.allCases {
            for (zone, cnv, recheck, confirmed) in rawCases {
                let preflight = CheckRunnerEditablePreflightV1(timeZoneID: zone,
                    isTimeZoneConfirmed: confirmed != nil, confirmedTimeZoneID: confirmed,
                    afterDarkAccepted: false, safePositionAccepted: true)
                let outcome = CheckRunnerEditableOutcomeV1(selection: nil, choice: .differentIssue,
                    selectedCouldNotVerifyReasonKey: " raw-key ", couldNotVerifyNote: cnv,
                    recheckNote: recheck, startsWithCouldNotVerify: true)
                let field = try CheckRunnerItemFieldStateV1(preflight: preflight, begin: bound,
                    outcome: outcome, wideContext: pendingSlot(id: largeID(700), step: .wide),
                    closeDetail: pendingSlot(id: largeID(701), step: .close), semanticAnchor: anchor)
                let decoded = try CheckRunnerItemDraftPayloadV1.decode(
                    CheckRunnerItemDraftPayloadV1.encode(.init(editing: fixture.source, field: field)))
                XCTAssertEqual(Data(decoded.field.preflight.timeZoneID.utf8), Data(zone.utf8))
                XCTAssertEqual(decoded.field.preflight.confirmedTimeZoneID.map { Data($0.utf8) },
                    confirmed.map { Data($0.utf8) })
                XCTAssertEqual(Data(decoded.field.outcome.couldNotVerifyNote.utf8), Data(cnv.utf8))
                XCTAssertEqual(Data(decoded.field.outcome.recheckNote.utf8), Data(recheck.utf8))
                XCTAssertEqual(decoded.field.semanticAnchor, anchor)
                XCTAssertEqual(decoded.field.wideContext, field.wideContext)
                XCTAssertEqual(decoded.field.closeDetail, field.closeDetail)
            }
        }
    }

    func testEditingParentPayloadUsesClosedCanonicalPhaseShape() throws {
        let fixture = try parentFixture(recheck: false, includesTimeZone: false)
        let payload = try CheckRunnerItemDraftPayloadV1(editing: fixture.source,
            field: parentField(begin: .notBegun))
        let bytes = try CheckRunnerItemDraftPayloadV1.encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "phase", "source", "field"])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["phase"] as? String, "EDITING")
        let mutations: [([String], Any)] = [
            (["future"], true), (["schemaVersion"], 2), (["phase"], "FUTURE"),
            (["finalizationAttempt"], [:]), (["field", "future"], true),
            (["field", "preflight", "future"], true), (["field", "semanticAnchor"], 7),
            (["source", "requestedEntry", "future"], true),
            (["field", "outcome", "choice"], 7),
        ]
        for (path, value) in mutations {
            var hostile = object; try setJSON(&hostile, path: path, value: value)
            XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile)))
        }
        var missing = object; missing.removeValue(forKey: "field")
        XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(missing)))
        var nestedMissing = object
        try removeJSON(&nestedMissing, path: ["field", "preflight", "timeZoneID"])
        XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(nestedMissing)))
        XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(bytes + Data(" ".utf8)))
    }

    func testParentPayloadEnforcesActualTwoMiBBoundaryByEncodedUTF8Bytes() throws {
        let fixture = try parentFixture(recheck: false, includesTimeZone: false)
        func payload(_ note: String) throws -> CheckRunnerItemDraftPayloadV1 {
            let field = try parentField(begin: .notBegun,
                outcome: .init(selection: nil, couldNotVerifyNote: note, recheckNote: ""))
            return try .init(editing: fixture.source, field: field)
        }
        let baseline = try CheckRunnerItemDraftPayloadV1.encode(payload("")).count
        let exactNote = String(repeating: "a", count: CheckRunnerItemDraftPayloadV1.maximumPayloadBytes - baseline)
        let exact = try CheckRunnerItemDraftPayloadV1.encode(payload(exactNote))
        XCTAssertEqual(exact.count, CheckRunnerItemDraftPayloadV1.maximumPayloadBytes)
        XCTAssertEqual(try CheckRunnerItemDraftPayloadV1.encode(
            CheckRunnerItemDraftPayloadV1.decode(exact)), exact)
        XCTAssertThrowsError(try payload(exactNote + "a"))
        let unicodeBaseline = try CheckRunnerItemDraftPayloadV1.encode(payload("é")).count
        XCTAssertEqual(unicodeBaseline - baseline, Data("é".utf8).count)
        XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(
            Data(repeating: 0x20, count: CheckRunnerItemDraftPayloadV1.maximumPayloadBytes + 1)))
    }

    func testPreparedParentPayloadValidatesAllSevenOutcomeMediaRowsAgainstShippingRelease() throws {
        let label = try XCTUnwrap(pack.issueLabels.first)
        let reason = try XCTUnwrap(pack.couldNotVerifyReasons.entries.first)
        let rows: [(Bool, CheckOutcomeSelection, Bool)] = [
            (false, .noVisibleIssue, true),
            (false, .visibleIssue(labelKey: label.key), true),
            (false, .couldNotVerify(reasonKey: reason.key, note: "raw cnv"), false),
            (true, .resolved(note: "raw recheck"), true),
            (true, .issueStillVisible(note: "raw recheck"), true),
            (true, .originalResolvedDifferentIssue(labelKey: label.key, note: "raw recheck"), true),
            (true, .couldNotVerify(reasonKey: reason.key, note: "raw cnv"), false),
        ]
        for (index, row) in rows.enumerated() {
            let fixture = try parentFixture(recheck: row.0, includesTimeZone: index.isMultiple(of: 2))
            let editor = editableOutcome(row.1)
            let field = try preparedField(fixture: fixture, outcome: editor, mediaCount: row.2 ? 2 : index == 6 ? 1 : 0,
                seed: 1_000 + index * 100)
            let attempt = try finalizationAttempt(fixture: fixture, field: field,
                selection: row.1, seed: 2_000 + index * 100)
            let payload = try CheckRunnerItemDraftPayloadV1(prepared: fixture.source,
                field: field, attempt: attempt)
            try payload.validatePreparedOutcome(signPack: pack, activeLifecycleProfile: { try self.profile })
            let bytes = try CheckRunnerItemDraftPayloadV1.encode(payload)
            XCTAssertEqual(try CheckRunnerItemDraftPayloadV1.encode(
                CheckRunnerItemDraftPayloadV1.decode(bytes)), bytes)
            if row.2 {
                XCTAssertNotNil(field.wideContext); XCTAssertNotNil(field.closeDetail)
            }
        }
    }

    func testPreparedParentPayloadRoundTripsAllFrozenValuesWithoutSelfDigests() throws {
        let fixture = try parentFixture(recheck: true, includesTimeZone: true)
        let selection = CheckOutcomeSelection.resolved(note: "e\u{301} long " + String(repeating: "x", count: 800))
        let field = try preparedField(fixture: fixture, outcome: editableOutcome(selection),
            mediaCount: 2, seed: 3_000)
        let apps = [SourceAppSnapshotV1(build: "", version: "e\u{301}"),
            SourceAppSnapshotV1(build: String(repeating: "build-", count: 400), version: "")]
        for app in apps {
            let attempt = try finalizationAttempt(fixture: fixture, field: field, selection: selection,
                seed: 4_000, sourceApp: app)
            let payload = try CheckRunnerItemDraftPayloadV1(prepared: fixture.source, field: field, attempt: attempt)
            let bytes = try CheckRunnerItemDraftPayloadV1.encode(payload)
            let decoded = try CheckRunnerItemDraftPayloadV1.decode(bytes)
            XCTAssertEqual(decoded, payload)
            XCTAssertEqual(decoded.finalizationAttempt, attempt)
            XCTAssertEqual(decoded.finalizationAttempt?.sourceApp, app)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            let text = String(decoding: bytes, as: UTF8.self)
            for forbidden in ["planSHA256", "payloadSHA256", "sagaSHA256", "stageDigests", "outputKeys"] {
                XCTAssertFalse(text.contains("\"\(forbidden)\""))
            }
            XCTAssertEqual(Set(object.keys), ["schemaVersion", "phase", "source", "field", "finalizationAttempt"])
            XCTAssertEqual(decoded.finalizationAttempt?.expectedWorkflowRecordRevision, 7)
            XCTAssertEqual(decoded.finalizationAttempt?.preparedSagaUpdatedAt, Date(timeIntervalSince1970: 1_800_004_010))
            XCTAssertEqual(decoded.finalizationAttempt?.terminalCheckpointUpdatedAt, Date(timeIntervalSince1970: 1_800_004_015))
        }
    }

    func testPreparedParentPayloadRejectsZeroAliasesAndCausalRegressions() throws {
        let fixture = try parentFixture(recheck: true, includesTimeZone: true)
        let selection = CheckOutcomeSelection.resolved(note: nil)
        let field = try preparedField(fixture: fixture, outcome: editableOutcome(selection),
            mediaCount: 2, seed: 5_000)
        let attempt = try finalizationAttempt(fixture: fixture, field: field, selection: selection, seed: 6_000)
        let valid = try jsonObject(CheckRunnerItemDraftPayloadV1(prepared: fixture.source,
            field: field, attempt: attempt))
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)).uuidString
        let zeroPaths = [
            ["field", "begin", "attempt", "recordMutationID"],
            ["field", "begin", "attempt", "timeZone", "mutationID"],
            ["finalizationAttempt", "identifiers", "mutationID"],
            ["finalizationAttempt", "identifiers", "packetID"],
            ["finalizationAttempt", "fieldDraftPlanID"],
            ["finalizationAttempt", "preparedSagaMutationID"],
            ["field", "wideContext", "childDraftID"],
            ["field", "wideContext", "evidenceID"],
        ]
        for path in zeroPaths {
            var hostile = valid; try setJSON(&hostile, path: path, value: zero)
            XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile)), "\(path)")
        }
        let aliasPairs: [([String], [String])] = [
            (["finalizationAttempt", "identifiers", "packetID"], ["finalizationAttempt", "identifiers", "mutationID"]),
            (["finalizationAttempt", "identifiers", "mutationID"], ["finalizationAttempt", "preparedSagaID"]),
            (["finalizationAttempt", "targetCommittedSagaID"], ["finalizationAttempt", "preparedSagaID"]),
            (["finalizationAttempt", "commitReceiptID"], ["field", "begin", "attempt", "recordCommand", "recordID"]),
            (["finalizationAttempt", "preparedSagaMutationID"],
                ["field", "begin", "attempt", "timeZone", "mutationID"]),
            (["finalizationAttempt", "preparedSagaID"], ["finalizationAttempt", "identifiers", "issueID"]),
            (["finalizationAttempt", "identifiers", "issueID"], ["finalizationAttempt", "identifiers", "reportID"]),
        ]
        for (target, source) in aliasPairs {
            var hostile = valid; try setJSON(&hostile, path: target, value: try getJSON(hostile, path: source))
            XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile)), "\(target)")
        }
        for (path, earlierPath) in [
            (["finalizationAttempt", "snapshotCreatedAt"], ["finalizationAttempt", "completedAt"]),
            (["finalizationAttempt", "preparedSagaUpdatedAt"], ["finalizationAttempt", "snapshotCreatedAt"]),
            (["finalizationAttempt", "contentPromotedSagaUpdatedAt"], ["finalizationAttempt", "preparedSagaUpdatedAt"]),
            (["finalizationAttempt", "targetCommittedSagaUpdatedAt"], ["finalizationAttempt", "contentPromotedSagaUpdatedAt"]),
            (["finalizationAttempt", "draftRetirePendingSagaUpdatedAt"], ["finalizationAttempt", "targetCommittedSagaUpdatedAt"]),
            (["finalizationAttempt", "draftRetiredSagaUpdatedAt"], ["finalizationAttempt", "draftRetirePendingSagaUpdatedAt"]),
            (["finalizationAttempt", "terminalCheckpointUpdatedAt"], ["finalizationAttempt", "draftRetiredSagaUpdatedAt"]),
        ] {
            var hostile = valid
            let earlier = try XCTUnwrap(try getJSON(hostile, path: earlierPath) as? Double)
            try setJSON(&hostile, path: path, value: earlier - 1)
            XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile)), "\(path)")
        }
        var fractional = valid
        let terminal = try XCTUnwrap(try getJSON(fractional,
            path: ["finalizationAttempt", "terminalCheckpointUpdatedAt"]) as? Double)
        try setJSON(&fractional, path: ["finalizationAttempt", "terminalCheckpointUpdatedAt"],
            value: terminal + 0.25)
        let fractionalValue = try payloadJSONDecoder().decode(CheckRunnerItemDraftPayloadV1.self,
            from: canonical(fractional))
        let fractionalDate = try XCTUnwrap(fractionalValue.finalizationAttempt?.terminalCheckpointUpdatedAt)
        XCTAssertGreaterThan(fractionalDate, attempt.terminalCheckpointUpdatedAt)
        XCTAssertEqual(fractionalDate.timeIntervalSince1970, (terminal + 0.25) / 1_000,
            accuracy: 0.000_001)
        let fractionalBytes = try CheckRunnerItemDraftPayloadV1.encode(fractionalValue)
        let fractionalRoundTrip = try CheckRunnerItemDraftPayloadV1.decode(fractionalBytes)
        XCTAssertEqual(fractionalRoundTrip.finalizationAttempt?.terminalCheckpointUpdatedAt,
            fractionalValue.finalizationAttempt?.terminalCheckpointUpdatedAt)
        XCTAssertEqual(try CheckRunnerItemDraftPayloadV1.encode(fractionalRoundTrip), fractionalBytes)
        let preparedField = try parentField(begin: .prepared(attempt: fixture.attempt))
        let prepared = try jsonObject(CheckRunnerItemDraftPayloadV1(editing: fixture.source,
            field: preparedField))
        var reversedBeginEffects = prepared
        let recordCommittedAt = try XCTUnwrap(try getJSON(prepared,
            path: ["field", "begin", "attempt", "recordCommittedAt"]) as? Double)
        try setJSON(&reversedBeginEffects, path: ["field", "begin", "attempt", "timeZone", "committedAt"],
            value: recordCommittedAt + 1_000)
        let reversedTimeZoneAt = try XCTUnwrap(try getJSON(reversedBeginEffects,
            path: ["field", "begin", "attempt", "timeZone", "committedAt"]) as? Double)
        XCTAssertGreaterThan(reversedTimeZoneAt, recordCommittedAt)
        XCTAssertThrowsError(try payloadJSONDecoder().decode(CheckRunnerItemDraftPayloadV1.self,
            from: canonical(reversedBeginEffects)))
        let boundField = try parentField(begin: .bound(attempt: fixture.attempt,
            workflowReceiptReference: fixture.workflowReference,
            timeZoneReceiptReference: fixture.timeZoneReference))
        var pendingAlias = try jsonObject(CheckRunnerItemDraftPayloadV1(editing: fixture.source,
            field: try .init(preflight: boundField.preflight, begin: boundField.begin,
                outcome: boundField.outcome, wideContext: pendingSlot(id: largeID(6_900), step: .wide),
                closeDetail: pendingSlot(id: largeID(6_901), step: .close), semanticAnchor: .wideContext)))
        try setJSON(&pendingAlias, path: ["field", "closeDetail", "childDraftID"],
            value: largeID(6_900).uuidString)
        XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(pendingAlias)))
    }

    func testPreparedParentPayloadRejectsFieldSourceOutcomeProfileDriftAndNestedUnknownKeys() throws {
        let reason = try XCTUnwrap(pack.couldNotVerifyReasons.entries.first)
        let fixture = try parentFixture(recheck: false, includesTimeZone: false)
        let selection = CheckOutcomeSelection.couldNotVerify(reasonKey: reason.key, note: "trimmed")
        let field = try preparedField(fixture: fixture,
            outcome: .init(selection: .couldNotVerify(reasonKey: reason.key, note: "trimmed"),
                choice: .couldNotVerify, selectedCouldNotVerifyReasonKey: reason.key,
                couldNotVerifyNote: " trimmed ", recheckNote: "", startsWithCouldNotVerify: true),
            mediaCount: 0, seed: 7_000)
        let attempt = try finalizationAttempt(fixture: fixture, field: field, selection: selection, seed: 8_000)
        let payload = try CheckRunnerItemDraftPayloadV1(prepared: fixture.source, field: field, attempt: attempt)
        try payload.validatePreparedOutcome(signPack: pack, activeLifecycleProfile: { try self.profile })
        let valid = try jsonObject(payload)
        let drifts: [([String], Any)] = [
            (["field", "outcome", "couldNotVerifyNote"], "different"),
            (["source", "packageRelease", "workflowSHA256"], String(repeating: "0", count: 64)),
            (["finalizationAttempt", "normalizedOutcome", "note"], "different"),
            (["finalizationAttempt", "expectedWorkflowRecordRevision"], 0),
        ]
        for (path, value) in drifts {
            var hostile = valid; try setJSON(&hostile, path: path, value: value)
            var rejected = false
            do {
                let decoded = try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile))
                do { try decoded.validatePreparedOutcome(signPack: pack,
                    activeLifecycleProfile: { try self.profile }) }
                catch { rejected = true }
            } catch { rejected = true }
            XCTAssertTrue(rejected, "\(path)")
        }
        let driftPack = SignPack(schemaVersion: pack.schemaVersion,
            packID: "fixture.field.evidence.profile-drift.v1", contentVersion: pack.contentVersion,
            nouns: pack.nouns, evidencePurposes: pack.evidencePurposes,
            acknowledgements: pack.acknowledgements, issueLabels: pack.issueLabels,
            couldNotVerifyReasons: pack.couldNotVerifyReasons, stageDisplays: pack.stageDisplays,
            outcomeDisplays: pack.outcomeDisplays, disclaimer: pack.disclaimer)
        let driftProfile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: driftPack)
        XCTAssertThrowsError(try payload.validatePreparedOutcome(signPack: pack,
            activeLifecycleProfile: { driftProfile }))
        for path in [
            ["source", "future"], ["field", "preflight", "future"],
            ["field", "begin", "attempt", "future"], ["field", "outcome", "future"],
            ["finalizationAttempt", "future"], ["finalizationAttempt", "identifiers", "future"],
            ["finalizationAttempt", "sourceApp", "future"],
        ] {
            var hostile = valid; try setJSON(&hostile, path: path, value: true)
            XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile)), "\(path)")
        }
    }

    func testPhotoChildAllFourPhasesRoundTripAcrossRoutesStagesAndSteps() throws {
        for recheck in [false, true] {
            for step in [WorkflowDraftStep.wide, .close] {
                for origin in [OriginalContentOriginV1.humanCapture, .localImport] {
                    let f = try photoFixture(recheck: recheck, step: step, origin: origin)
                    let phases: [CheckRunnerPhotoDurablePhaseV1] = [.awaitingRawStage(f.intent), .rawReady(f.raw),
                        .pairReady(f.pair), .preparedCommit(f.pair, f.attempt)]
                    for (index, phase) in phases.enumerated() {
                        let payload = try photoPayload(f, phase: phase)
                        let bytes = try CheckRunnerPhotoDraftPayloadV1.encode(payload)
                        let decoded = try CheckRunnerPhotoDraftPayloadV1.decode(bytes)
                        XCTAssertEqual(decoded, payload)
                        XCTAssertEqual(try CheckRunnerPhotoDraftPayloadV1.encode(decoded), bytes)
                        XCTAssertEqual(decoded.phase.declaredStageIDs, index == 0 ? [] : [f.intent.stageID])
                        XCTAssertEqual(decoded.workflowStage, recheck ? .recheck : .check)
                        XCTAssertEqual(decoded.origin, origin)
                        XCTAssertNoThrow(try decoded.validate(parent: f.parent, parentDraftID: f.parentDraftID))
                    }
                }
            }
        }
    }

    func testPhotoChildClosedPhaseGrammarRejectsUnknownMissingAndPrematureValues() throws {
        let f = try photoFixture()
        let rows: [(CheckRunnerPhotoDurablePhaseV1, String, Set<String>, String)] = [
            (.awaitingRawStage(f.intent), "AWAITING_RAW_STAGE", ["tag", "intent"], "raw"),
            (.rawReady(f.raw), "RAW_READY", ["tag", "raw"], "pair"),
            (.pairReady(f.pair), "PAIR_READY", ["tag", "pair"], "attempt"),
            (.preparedCommit(f.pair, f.attempt), "PREPARED_COMMIT", ["tag", "pair", "attempt"], "intent"),
        ]
        for (phase, tag, keys, prematureKey) in rows {
            let value = try photoPayload(f, phase: phase)
            let original = try jsonObject(value)
            let phaseObject = try XCTUnwrap(original["phase"] as? [String: Any])
            XCTAssertEqual(Set(phaseObject.keys), keys)
            XCTAssertEqual(phaseObject["tag"] as? String, tag)
            for key in keys {
                var missing = original; try removeJSON(&missing, path: ["phase", key])
                XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoDraftPayloadV1.self, missing), key)
            }
            for badTag in ["PROCESSING", "COMMITTED", "rawReady"] {
                var bad = original; try setJSON(&bad, path: ["phase", "tag"], value: badTag)
                XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoDraftPayloadV1.self, bad), badTag)
            }
            var premature = original; try setJSON(&premature, path: ["phase", prematureKey], value: NSNull())
            XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoDraftPayloadV1.self, premature))
            var unknown = original; try setJSON(&unknown, path: ["phase", "receiptSHA256"], value: String(repeating: "a", count: 64))
            XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoDraftPayloadV1.self, unknown))
        }
    }

    func testPhotoChildSourceProfileAndInspectionEnforceAllSourceBounds() throws {
        let f = try photoFixture()
        let expected = ["public.jpeg": "image/jpeg", "public.heic": "image/heic",
                        "public.heif": "image/heif", "public.png": "image/png"]
        XCTAssertEqual(CheckRunnerPhotoSourceMetadataProfileV1.sourceUTIToMediaType, expected)
        XCTAssertEqual(Set(expected.keys), MediaContractV1.acceptedSourceTypeIdentifiers)
        XCTAssertEqual(CheckRunnerPhotoSourceMetadataProfileV1.profileID, "assetrounds.checkrunner-photo-source-metadata")
        XCTAssertEqual(CheckRunnerPhotoSourceMetadataProfileV1.profileVersion, "1")
        for (uti, mime) in expected {
            for count in [1, MediaContractV1.sourceByteCountMaximum] {
                let inspection = try CheckRunnerPhotoSourceInspectionV1(
                    facts: .init(sourceTypeIdentifier: uti, pixelWidth: 10_000, pixelHeight: 10_000, byteCount: count),
                    sourceSHA256: f.raw.inspection.sourceSHA256, workspaceID: f.parent.source.roundAtEntry.workspaceID,
                    provenanceID: f.intent.provenanceID)
                XCTAssertEqual(inspection.sourceMediaType, mime)
                XCTAssertEqual(inspection.decodedPixelCount, 100_000_000)
                XCTAssertEqual(inspection.sourceByteCount, Int64(count))
                XCTAssertEqual(inspection.frameCount, 1)
            }
        }
        let original = try jsonObject(f.raw.inspection)
        let mutations: [(String, Any)] = [
            ("sourceByteCount", 0), ("sourceByteCount", MediaContractV1.sourceByteCountMaximum + 1),
            ("sourceByteCount", 1.5), ("detectedUTI", "public.gif"), ("detectedUTI", "PUBLIC.JPEG"),
            ("sourceMediaType", "image/png"), ("pixelWidth", 0), ("pixelWidth", 16_385),
            ("pixelHeight", Int.max), ("decodedPixelCount", 201), ("frameCount", 2),
            ("rawContentID", ""), ("provenanceID", ""),
        ]
        for (key, value) in mutations {
            var bad = original; bad[key] = value
            XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoSourceInspectionV1.self, bad), key)
        }
        var tooManyPixels = original
        tooManyPixels["pixelWidth"] = 10_001; tooManyPixels["pixelHeight"] = 10_000
        tooManyPixels["decodedPixelCount"] = 100_010_000
        XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoSourceInspectionV1.self, tooManyPixels))
        var wrongAlgorithm = original
        wrongAlgorithm["sourceSHA256"] = try jsonValue(ContentDigestV1(algorithm: .sha512,
            hexadecimalValue: String(repeating: "b", count: 128)))
        XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoSourceInspectionV1.self, wrongAlgorithm))
        for badTime in [Date(timeIntervalSince1970: -1), Date(timeIntervalSince1970: .infinity)] {
            XCTAssertThrowsError(try CheckRunnerPhotoRawStageIntentV1(stageID: f.intent.stageID,
                stageMutationID: f.intent.stageMutationID, stageCreatedAt: f.intent.stageCreatedAt,
                expectedSourceByteCount: f.intent.expectedSourceByteCount, provenanceID: f.intent.provenanceID,
                evidenceID: f.intent.evidenceID, evidenceCreatedAt: badTime))
        }
        XCTAssertNoThrow(try CheckRunnerPhotoRawStageIntentV1(stageID: f.intent.stageID,
            stageMutationID: f.intent.stageMutationID, stageCreatedAt: f.intent.stageCreatedAt,
            expectedSourceByteCount: Int64(MediaContractV1.sourceByteCountMaximum), provenanceID: f.intent.provenanceID,
            evidenceID: f.intent.evidenceID, evidenceCreatedAt: f.intent.evidenceCreatedAt))
    }

    func testPhotoChildValidatesRawStageAndProvenanceValueJoins() throws {
        let f = try photoFixture()
        let original = try jsonObject(f.raw)
        let mutations: [([String], Any)] = [
            (["stagePublicationMutationID"], largeID(4_001).uuidString),
            (["inspection", "rawContentID"], "draft-content-wrong"),
            (["inspection", "provenanceID"], "wrong-provenance"),
            (["originalProvenance", "workspaceID"], largeID(4_002).uuidString.lowercased()),
            (["originalProvenance", "contentID"], "wrong-content"),
            (["originalProvenance", "provenanceID"], "wrong-provenance"),
            (["originalProvenance", "recordedAt"], f.raw.originalProvenance.recordedAt.replacingOccurrences(of: "Z", with: "+00:00")),
            (["readyItem", "stageSHA256"], String(repeating: "f", count: 64)),
        ]
        for (path, value) in mutations {
            var bad = original; try setJSON(&bad, path: path, value: value)
            XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoRawReadyV1.self, bad), path.joined(separator: "."))
        }
        let item = f.raw.readyItem
        let processing = try AttachmentStagingItemV1(stageID: item.stageID, draftID: item.draftID,
            workspaceID: item.workspaceID, attachmentKind: .photo, scratchLeaseID: item.scratchLeaseID,
            expectedByteCount: item.expectedByteCount, actualByteCount: item.actualByteCount,
            contentDigest: item.contentDigest, retryClass: .none, state: .processing,
            protectionState: .available, revision: 1, mutationID: item.mutationID)
        XCTAssertNoThrow(try processing.validate())
        XCTAssertThrowsError(try CheckRunnerPhotoRawReadyV1(intent: f.intent, inspection: f.raw.inspection,
            readyItem: processing, stagePublicationMutationID: f.intent.stageMutationID,
            originalProvenance: f.raw.originalProvenance))
        var unknown = original; try setJSON(&unknown, path: ["readyItem", "createdAt"], value: 1_800_000_201_000)
        XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoRawReadyV1.self, unknown))
        XCTAssertEqual(f.raw.originalProvenance.recordedAt,
            try CheckRunnerPhotoRawReadyV1.formatOriginalRecordedAt(f.intent.stageCreatedAt))
        XCTAssertEqual(f.raw.originalProvenance.recordedAt, DraftAttachmentStagingAdapterV1.iso8601(f.intent.stageCreatedAt))
        XCTAssertEqual(f.raw.inspection.rawContentID, DraftAttachmentStagingAdapterV1.contentID(
            workspaceID: item.workspaceID, digest: f.raw.inspection.sourceSHA256))
        XCTAssertNil(item.contentReference); XCTAssertNil(item.processingJobID)
    }

    func testPhotoChildPairBoundsPathsAndDerivativeProfileAreClosed() throws {
        let f = try photoFixture()
        let original = try jsonObject(f.pair.normalizedPair)
        var maximum = original
        maximum["originalByteCount"] = MediaContractV1.originalByteCountMaximum
        maximum["originalPixelWidth"] = MediaContractV1.originalLongestEdgeMaximum
        maximum["originalPixelHeight"] = MediaContractV1.originalLongestEdgeMaximum
        maximum["thumbnailByteCount"] = MediaContractV1.thumbnailByteCountMaximum
        maximum["thumbnailPixelWidth"] = MediaContractV1.thumbnailLongestEdgeMaximum
        maximum["thumbnailPixelHeight"] = MediaContractV1.thumbnailLongestEdgeMaximum
        try setJSON(&maximum, path: ["thumbnailDerivative", "pixelWidth"], value: 512)
        try setJSON(&maximum, path: ["thumbnailDerivative", "pixelHeight"], value: 512)
        XCTAssertNoThrow(try decodeObject(CheckRunnerPhotoNormalizedPairV1.self, maximum))
        let mutations: [([String], Any)] = [
            (["originalRelativePath"], "../original.jpg"),
            (["originalRelativePath"], f.pair.normalizedPair.originalRelativePath.uppercased()),
            (["thumbnailRelativePath"], f.pair.normalizedPair.originalRelativePath),
            (["originalByteCount"], 0), (["originalByteCount"], MediaContractV1.originalByteCountMaximum + 1),
            (["thumbnailByteCount"], 0), (["thumbnailByteCount"], MediaContractV1.thumbnailByteCountMaximum + 1),
            (["originalPixelWidth"], 4_097), (["thumbnailPixelHeight"], 513),
            (["originalSHA256"], String(repeating: "A", count: 64)),
            (["thumbnailSHA256"], "abc"),
            (["sanitizedDerivative", "sanitizerID"], "different-sanitizer"),
            (["sanitizedDerivative", "sanitizerVersion"], "2"),
            (["thumbnailDerivative", "rendererID"], "different-renderer"),
            (["thumbnailDerivative", "rendererVersion"], "2"),
            (["thumbnailDerivative", "pixelWidth"], 11),
        ]
        for (path, value) in mutations {
            var bad = original; try setJSON(&bad, path: path, value: value)
            XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoNormalizedPairV1.self, bad), path.joined(separator: "."))
        }
        XCTAssertEqual(f.pair.normalizedPair.sanitizedDerivative.sanitizerID, "assetrounds.media-normalizer.metadata")
        XCTAssertEqual(f.pair.normalizedPair.thumbnailDerivative.rendererID, "assetrounds.media-normalizer.thumbnail")
    }

    func testPhotoChildPairMarkerBindsParentChildRawAndBothOutputs() throws {
        let f = try photoFixture()
        let baseline = try photoPayload(f, phase: .pairReady(f.pair))
        XCTAssertEqual(f.pair.pairPublicationMarkerSHA256, try CheckRunnerPhotoPairReadyV1.markerSHA256(
            childDraftID: f.childDraftID, parentDraftID: f.parentDraftID, raw: f.raw, normalizedPair: f.pair.normalizedPair))
        XCTAssertNotEqual(f.pair.pairPublicationMarkerSHA256, try CheckRunnerPhotoPairReadyV1.markerSHA256(
            childDraftID: f.childDraftID, parentDraftID: largeID(4_100), raw: f.raw, normalizedPair: f.pair.normalizedPair))
        XCTAssertThrowsError(try CheckRunnerPhotoPairReadyV1.markerSHA256(childDraftID: largeID(4_101),
            parentDraftID: f.parentDraftID, raw: f.raw, normalizedPair: f.pair.normalizedPair))
        for key in ["originalSHA256", "thumbnailSHA256"] {
            var pairObject = try jsonObject(f.pair.normalizedPair)
            pairObject[key] = String(repeating: "d", count: 64)
            let changedPair = try decodeObject(CheckRunnerPhotoNormalizedPairV1.self, pairObject)
            let stale = try CheckRunnerPhotoPairReadyV1(raw: f.raw, normalizedPair: changedPair,
                pairPublicationMarkerSHA256: f.pair.pairPublicationMarkerSHA256)
            XCTAssertNoThrow(try stale.validate())
            XCTAssertThrowsError(try photoPayload(f, phase: .pairReady(stale)), key)
            XCTAssertNotEqual(try CheckRunnerPhotoPairReadyV1.markerSHA256(childDraftID: f.childDraftID,
                parentDraftID: f.parentDraftID, raw: f.raw, normalizedPair: changedPair),
                f.pair.pairPublicationMarkerSHA256)
        }
        var wrongSource = try jsonObject(f.pair)
        try setJSON(&wrongSource, path: ["normalizedPair", "sourceBinding", "contentID"], value: "wrong-raw-content")
        XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoPairReadyV1.self, wrongSource))
        var wrongEvidence = try jsonObject(f.pair)
        try setJSON(&wrongEvidence, path: ["normalizedPair", "evidenceID"], value: largeID(4_102).uuidString)
        XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoPairReadyV1.self, wrongEvidence))
        let bytes = try CheckRunnerPhotoDraftPayloadV1.encode(baseline)
        XCTAssertEqual(try CheckRunnerPhotoDraftPayloadV1.encode(CheckRunnerPhotoDraftPayloadV1.decode(bytes)), bytes)
    }

    func testPhotoChildPreparedAttemptPreservesEveryFrozenIdentityAndTime() throws {
        let f = try photoFixture()
        let payload = try photoPayload(f, phase: .preparedCommit(f.pair, f.attempt))
        let bytes = try CheckRunnerPhotoDraftPayloadV1.encode(payload)
        let decoded = try CheckRunnerPhotoDraftPayloadV1.decode(bytes)
        let attempt = try XCTUnwrap(decoded.phase.attempt)
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(attempt), try FieldDraftCanonicalCodecV1.encode(f.attempt))
        let rows = try attempt.rowMutationIDs(stageID: f.intent.stageID)
        XCTAssertEqual(rows.reservationByStageID, [f.intent.stageID: attempt.reservationMutationID])
        XCTAssertEqual(rows.terminalBundleMutationID, attempt.terminalBundleMutationID)
        let mutations = [attempt.preparedSagaMutationID, attempt.contentPromotedSagaMutationID,
                         attempt.targetCommittedSagaMutationID, attempt.draftRetirePendingSagaMutationID]
        XCTAssertNoThrow(try rows.validate(stageIDs: [f.intent.stageID], targetMutationID: attempt.targetMutationID,
                                           sagaMutationIDs: mutations))
        XCTAssertThrowsError(try rows.validate(stageIDs: [f.intent.stageID], targetMutationID: attempt.targetMutationID,
                                               sagaMutationIDs: mutations + [attempt.terminalBundleMutationID]))
        let plan = try DraftCommitPlanV1(planID: attempt.planID, workspaceID: payload.workspaceID,
            draftID: payload.childDraftID, draftRevision: 4, baseCanonicalRevision: 0,
            payloadSHA256: FieldDraftCanonicalCodecV1.sha256(bytes), stageDigests: [f.raw.readyItem.stageSHA256],
            targetCommandKind: .acceptCheckEvidence, expectedTargetRevision: attempt.expectedWorkflowRecordRevision,
            mutationID: attempt.targetMutationID, outputKeys: attempt.outputKeys)
        let definitions: [(UUID, DraftCommitSagaStateV1, MutationIDV1, Date)] = [
            (attempt.preparedSagaID, .prepared, attempt.preparedSagaMutationID, attempt.preparedUpdatedAt),
            (attempt.contentPromotedSagaID, .contentPromotedUnbound, attempt.contentPromotedSagaMutationID, attempt.contentPromotedUpdatedAt),
            (attempt.targetCommittedSagaID, .targetCommitted, attempt.targetCommittedSagaMutationID, attempt.targetCommittedUpdatedAt),
            (attempt.draftRetirePendingSagaID, .draftRetirePending, attempt.draftRetirePendingSagaMutationID, attempt.draftRetirePendingUpdatedAt),
            (attempt.draftRetiredSagaID, .draftRetired, attempt.terminalBundleMutationID, attempt.draftRetiredUpdatedAt),
        ]
        var previous: DraftCommitSagaV1?
        for (offset, definition) in definitions.enumerated() {
            let row = try DraftCommitSagaV1(sagaID: definition.0, workspaceID: payload.workspaceID,
                draftID: payload.childDraftID, plan: plan, state: definition.1, predecessorSagaID: previous?.sagaID,
                revision: UInt64(offset + 1), mutationID: definition.2, updatedAt: definition.3)
            if let previous { XCTAssertNoThrow(try row.validateSuccessor(of: previous)) }
            previous = row
        }
        XCTAssertEqual(previous?.mutationID, attempt.terminalBundleMutationID)
        XCTAssertEqual(previous?.revision, 5)
        XCTAssertEqual(plan.draftID, payload.childDraftID)
        XCTAssertEqual(attempt.targetMutationID.rawValue, f.intent.evidenceID)
        XCTAssertEqual(try CheckRunnerPhotoDraftPayloadV1.encode(decoded), bytes)
    }

    func testPhotoChildPreparedAttemptRejectsAliasesWrongOutputsAndTimeRegressions() throws {
        let f = try photoFixture()
        let original = try jsonObject(f.attempt)
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(
            decodeObject(CheckRunnerPhotoCommitAttemptV1.self, original)),
            try FieldDraftCanonicalCodecV1.encode(f.attempt))
        let idKeys = ["planID", "preparedSagaID", "contentPromotedSagaID", "targetCommittedSagaID",
            "draftRetirePendingSagaID", "draftRetiredSagaID", "commitReceiptID", "targetMutationID",
            "reservationMutationID", "preparedSagaMutationID", "contentPromotedSagaMutationID",
            "targetCommittedSagaMutationID", "draftRetirePendingSagaMutationID", "terminalBundleMutationID"]
        for key in idKeys {
            var zero = original; zero[key] = FieldDraftValidationV1.zero.uuidString
            XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoCommitAttemptV1.self, zero), key)
            var bad = original
            bad[key] = largeID(4_200).uuidString
            let firstOther = idKeys.first { $0 != key && !$0.contains("MutationID") }!
            bad[firstOther] = largeID(4_200).uuidString
            XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoCommitAttemptV1.self, bad), key)
        }
        for revision in [UInt64(0), UInt64.max] {
            var bad = original; bad["expectedWorkflowRecordRevision"] = NSNumber(value: revision)
            XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoCommitAttemptV1.self, bad))
        }
        for outputs in [Array(f.attempt.outputKeys.reversed()), [f.attempt.outputKeys[0]],
                        [f.attempt.outputKeys[0], f.attempt.outputKeys[0]]] {
            var bad = original; bad["outputKeys"] = outputs
            XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoCommitAttemptV1.self, bad))
        }
        var wrongOutputs = original
        wrongOutputs["outputKeys"] = try [WorkspaceEntityIdentityV1(kind: .workflowRecord, id: largeID(4_201)).stableKey,
            WorkspaceEntityIdentityV1(kind: .evidenceFile, id: f.intent.evidenceID).stableKey].sorted()
        let differentTarget = try decodeObject(CheckRunnerPhotoCommitAttemptV1.self, wrongOutputs)
        XCTAssertNotEqual(differentTarget.outputKeys, f.attempt.outputKeys)
        XCTAssertEqual(differentTarget.targetMutationID, f.attempt.targetMutationID)
        XCTAssertThrowsError(try differentTarget.validate(raw: f.raw, recordID: f.parentFixture.attempt.recordCommand.recordID))
        for key in ["promotionAt", "contentPromotedUpdatedAt", "targetCommittedUpdatedAt",
                    "draftRetirePendingUpdatedAt", "draftRetiredUpdatedAt", "terminalCheckpointUpdatedAt", "reservationReviewAfter"] {
            var bad = original; bad[key] = 1_800_000_202_000
            XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoCommitAttemptV1.self, bad), key)
        }
        var negative = original; negative["preparedUpdatedAt"] = -1
        XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoCommitAttemptV1.self, negative))
    }

    func testPhotoChildParentCorrespondenceRequiresExactBeginSourceAndSlot() throws {
        let f = try photoFixture()
        let payload = try photoPayload(f, phase: .awaitingRawStage(f.intent))
        XCTAssertNoThrow(try payload.validate(parent: f.parent, parentDraftID: f.parentDraftID))
        XCTAssertThrowsError(try payload.validate(parent: f.parent, parentDraftID: largeID(4_300)))
        let other = try photoFixture(recheck: true)
        XCTAssertThrowsError(try payload.validate(parent: other.parent, parentDraftID: f.parentDraftID))
        XCTAssertThrowsError(try payload.validate(parent: photoParent(f, slot: nil), parentDraftID: f.parentDraftID))
        let otherSlot = CheckRunnerPhotoSlotV1.pending(childDraftID: largeID(4_301), captureStep: f.step,
            purposeKey: payload.purposeKey)
        XCTAssertThrowsError(try payload.validate(parent: photoParent(f, slot: otherSlot), parentDraftID: f.parentDraftID))
        let unbegun = try CheckRunnerItemDraftPayloadV1(editing: f.parent.source,
            field: parentField(begin: .notBegun))
        XCTAssertThrowsError(try payload.validate(parent: unbegun, parentDraftID: f.parentDraftID))
        var wrongRecord = try jsonObject(payload); wrongRecord["recordID"] = largeID(4_302).uuidString
        let shapeOnly = try decodeObject(CheckRunnerPhotoDraftPayloadV1.self, wrongRecord)
        XCTAssertThrowsError(try shapeOnly.validate(parent: f.parent, parentDraftID: f.parentDraftID))
        let mutations: [(String, Any)] = [
            ("workspaceID", try jsonValue(WorkspaceID(rawValue: largeID(4_303)))),
            ("assetID", largeID(4_304).uuidString), ("workflowStage", "work"),
            ("captureStep", "outcome"), ("purposeKey", "close_detail"),
            ("parentDraftID", f.childDraftID.uuidString),
        ]
        for (key, value) in mutations {
            var bad = try jsonObject(payload); bad[key] = value
            XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoDraftPayloadV1.self, bad), key)
        }
        var wrongOrigin = try jsonObject(photoPayload(f, phase: .rawReady(f.raw)))
        wrongOrigin["origin"] = OriginalContentOriginV1.localImport.rawValue
        XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoDraftPayloadV1.self, wrongOrigin))
    }

    func testPhotoChildPreparationTimeBoundariesReuseFrozenInputs() throws {
        let f = try photoFixture()
        let initial = try photoPayload(f, phase: .awaitingRawStage(f.intent))
        XCTAssertNoThrow(try initial.validateRawStageIntent(parentSlotCheckpointUpdatedAt: f.intent.stageCreatedAt))
        XCTAssertThrowsError(try initial.validateRawStageIntent(
            parentSlotCheckpointUpdatedAt: f.intent.stageCreatedAt.addingTimeInterval(0.001)))
        XCTAssertThrowsError(try initial.validateRawStageIntent(parentSlotCheckpointUpdatedAt: Date(timeIntervalSince1970: -1)))
        XCTAssertThrowsError(try initial.validateCommitPreparation(pairReadyCheckpointUpdatedAt: f.intent.stageCreatedAt))
        let prepared = try photoPayload(f, phase: .preparedCommit(f.pair, f.attempt))
        for boundary in [f.intent.stageCreatedAt, f.attempt.preparedUpdatedAt] {
            XCTAssertNoThrow(try prepared.validateCommitPreparation(pairReadyCheckpointUpdatedAt: boundary))
        }
        for boundary in [f.intent.stageCreatedAt.addingTimeInterval(-0.001),
                         f.attempt.preparedUpdatedAt.addingTimeInterval(0.001)] {
            XCTAssertThrowsError(try prepared.validateCommitPreparation(pairReadyCheckpointUpdatedAt: boundary))
        }
        var equalTimes = try jsonObject(f.attempt)
        let timeKeys = ["preparedUpdatedAt", "promotionAt", "contentPromotedUpdatedAt", "targetCommittedUpdatedAt",
                        "draftRetirePendingUpdatedAt", "draftRetiredUpdatedAt", "terminalCheckpointUpdatedAt", "reservationReviewAfter"]
        for key in timeKeys {
            equalTimes[key] = f.intent.stageCreatedAt.timeIntervalSince1970 * 1_000
        }
        let equalAttempt = try decodeObject(CheckRunnerPhotoCommitAttemptV1.self, equalTimes)
        var originalFrozenFields = try jsonObject(f.attempt)
        var recoveredFrozenFields = try jsonObject(equalAttempt)
        for key in timeKeys {
            originalFrozenFields.removeValue(forKey: key)
            recoveredFrozenFields.removeValue(forKey: key)
        }
        XCTAssertEqual(try canonical(recoveredFrozenFields), try canonical(originalFrozenFields))
        XCTAssertEqual(equalAttempt.outputKeys, f.attempt.outputKeys)
        XCTAssertEqual(equalAttempt.expectedWorkflowRecordRevision, f.attempt.expectedWorkflowRecordRevision)
        let equalPayload = try photoPayload(f, phase: .preparedCommit(f.pair, equalAttempt))
        XCTAssertNoThrow(try equalPayload.validateCommitPreparation(pairReadyCheckpointUpdatedAt: f.intent.stageCreatedAt))
        let bytes = try CheckRunnerPhotoDraftPayloadV1.encode(equalPayload)
        let decoded = try CheckRunnerPhotoDraftPayloadV1.decode(bytes)
        XCTAssertEqual(decoded.phase.attempt?.promotionAt, f.intent.stageCreatedAt)
        XCTAssertEqual(decoded.phase.attempt?.terminalCheckpointUpdatedAt, f.intent.stageCreatedAt)
        XCTAssertEqual(try CheckRunnerPhotoDraftPayloadV1.encode(decoded), bytes)
    }

    func testPhotoChildCanonicalCodecRejectsOversizeNoncanonicalAndNestedUnknownBytes() throws {
        let f = try photoFixture()
        let payload = try photoPayload(f, phase: .preparedCommit(f.pair, f.attempt))
        let bytes = try CheckRunnerPhotoDraftPayloadV1.encode(payload)
        XCTAssertLessThan(bytes.count, CheckRunnerPhotoDraftPayloadV1.maximumPayloadBytes)
        XCTAssertEqual(CheckRunnerPhotoDraftPayloadV1.maximumPayloadBytes, 2 * 1_024 * 1_024)
        XCTAssertThrowsError(try CheckRunnerPhotoDraftPayloadV1.decode(bytes + Data([0x20])))
        XCTAssertThrowsError(try CheckRunnerPhotoDraftPayloadV1.decode(Data()))
        XCTAssertThrowsError(try CheckRunnerPhotoDraftPayloadV1.decode(
            Data(repeating: 0x20, count: CheckRunnerPhotoDraftPayloadV1.maximumPayloadBytes + 1))) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .limitExceeded)
        }
        let original = try jsonObject(payload)
        let objects: [[String]] = [[], ["phase"], ["phase", "pair"], ["phase", "pair", "raw"],
            ["phase", "pair", "raw", "intent"], ["phase", "pair", "raw", "inspection"],
            ["phase", "pair", "raw", "readyItem"], ["phase", "pair", "raw", "originalProvenance"],
            ["phase", "pair", "normalizedPair"], ["phase", "pair", "normalizedPair", "sourceBinding"],
            ["phase", "pair", "normalizedPair", "sanitizedDerivative"],
            ["phase", "pair", "normalizedPair", "thumbnailDerivative"], ["phase", "attempt"]]
        for path in objects {
            var bad = original; try setJSON(&bad, path: path + ["unexpected"], value: true)
            XCTAssertThrowsError(try CheckRunnerPhotoDraftPayloadV1.decode(canonical(bad)), path.joined(separator: "."))
        }
        for key in original.keys {
            var missing = original; missing.removeValue(forKey: key)
            XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoDraftPayloadV1.self, missing), key)
        }
        var schema = original; schema["schemaVersion"] = 2
        XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoDraftPayloadV1.self, schema))
        var wrongType = original; try setJSON(&wrongType, path: ["phase", "attempt", "promotionAt"], value: "now")
        XCTAssertThrowsError(try decodeObject(CheckRunnerPhotoDraftPayloadV1.self, wrongType))
        XCTAssertEqual(try CheckRunnerPhotoDraftPayloadV1.encode(CheckRunnerPhotoDraftPayloadV1.decode(bytes)), bytes)
    }

    func testPhotoChildCommittedParentRequiresPreparedTerminalValues() throws {
        let f = try photoFixture()
        let slot = try committedFixtureSlot(child: f.childDraftID, evidence: f.intent.evidenceID,
            step: f.step, receipt: f.attempt.commitReceiptID)
        let committedParent = try photoParent(f, slot: slot)
        let early: [CheckRunnerPhotoDurablePhaseV1] = [.awaitingRawStage(f.intent), .rawReady(f.raw), .pairReady(f.pair)]
        for phase in early {
            XCTAssertThrowsError(try photoPayload(f, phase: phase).validate(
                parent: committedParent, parentDraftID: f.parentDraftID))
        }
        let prepared = try photoPayload(f, phase: .preparedCommit(f.pair, f.attempt))
        XCTAssertNoThrow(try prepared.validate(parent: committedParent, parentDraftID: f.parentDraftID))
        let otherEvidence = try committedFixtureSlot(child: f.childDraftID, evidence: largeID(4_400),
            step: f.step, receipt: f.attempt.commitReceiptID)
        XCTAssertThrowsError(try prepared.validate(parent: photoParent(f, slot: otherEvidence), parentDraftID: f.parentDraftID))
        let otherReceipt = try committedFixtureSlot(child: f.childDraftID, evidence: f.intent.evidenceID,
            step: f.step, receipt: largeID(4_401))
        XCTAssertNoThrow(try otherReceipt.validate())
        XCTAssertThrowsError(try prepared.validate(parent: photoParent(f, slot: otherReceipt), parentDraftID: f.parentDraftID))
        // This is the retained raw witness, not a read of the live stage. A
        // committed parent claim does not rewrite it or imply receipt proof.
        XCTAssertEqual(prepared.phase.raw?.readyItem.state, .readyLocal)
        XCTAssertEqual(prepared.phase.raw?.readyItem.revision, 1)
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(prepared.phase.raw),
                       try FieldDraftCanonicalCodecV1.encode(f.raw))
    }

    func testCodecDefinitionsBindTheCombinedGrammarAndRequiredPhotoProfile() throws {
        let parent = try CheckRunnerItemDraftCodecV1.definition()
        let photo = try CheckRunnerPhotoDraftCodecV1.definition()
        XCTAssertEqual(parent.codec.codecID, "assetrounds.check-runner-item.v1")
        XCTAssertEqual(photo.codec.codecID, "assetrounds.check-runner-photo.v1")
        XCTAssertEqual(parent.codec.codecVersion, 1)
        XCTAssertEqual(photo.codec.codecVersion, 1)
        XCTAssertEqual(parent.codec.releaseSHA256, "e2f9c5cfa69006a5dc7f3bb86c36a030998afc1c8f8b421def6981dd42f72292")
        XCTAssertEqual(photo.codec.releaseSHA256, "91ab8725776d6c6508e2e1b937fbe4a89df487a99a58c4203328ba8e5bb4f5d2")
        XCTAssertEqual(parent.codec.releaseSHA256,
            FieldDraftCanonicalCodecV1.sha256(Data(CheckRunnerItemDraftCodecV1.grammarDescriptor.utf8)))
        XCTAssertEqual(photo.codec.releaseSHA256,
            FieldDraftCanonicalCodecV1.sha256(Data(CheckRunnerPhotoDraftCodecV1.grammarDescriptor.utf8)))
        XCTAssertEqual(CheckRunnerItemDraftCodecV1.grammarDescriptor.split(separator: "\n").dropFirst(2),
                       CheckRunnerPhotoDraftCodecV1.grammarDescriptor.split(separator: "\n").dropFirst(2))
        XCTAssertNotEqual(parent.codec, photo.codec)
        for definition in [parent, photo] {
            XCTAssertEqual(definition.purpose, .inspectionReview)
            XCTAssertEqual(definition.maximumPayloadBytes, 2_097_152)
            XCTAssertEqual(definition.retention, .retireAfterCommit)
            XCTAssertNoThrow(try definition.validate())
        }
        XCTAssertEqual(parent.maximumStageItems, 0)
        XCTAssertEqual(parent.targetCommandKind, .finalizeCheck)
        XCTAssertEqual(parent.attachmentKinds, [])
        XCTAssertEqual(parent.privacyClass, .workspacePrivate)
        XCTAssertEqual(photo.maximumStageItems, 1)
        XCTAssertEqual(photo.targetCommandKind, .acceptCheckEvidence)
        XCTAssertEqual(photo.attachmentKinds, [.photo])
        XCTAssertEqual(photo.privacyClass, .restrictedEvidence)
        XCTAssertEqual(CheckRunnerPhotoSourceMetadataProfileV1.sourceUTIToMediaType,
            ["public.jpeg": "image/jpeg", "public.heic": "image/heic", "public.heif": "image/heif", "public.png": "image/png"])
        XCTAssertTrue(CheckRunnerPhotoDraftCodecV1.grammarDescriptor.contains("media.rawByteCount=1...83886080;frameCount=1"))
    }

    func testCodecPurposeAuthorityRejectsWrongPurposesAndEveryModifiedReleaseComponent() throws {
        let authority = try CheckRunnerDraftPurposeAuthorityV1()
        let parent = try CheckRunnerItemDraftCodecV1.definition()
        let photo = try CheckRunnerPhotoDraftCodecV1.definition()
        XCTAssertEqual(try authority.require(.inspectionReview, codec: parent.codec), parent)
        XCTAssertEqual(try authority.require(.inspectionReview, codec: photo.codec), photo)
        for purpose in DraftPurposeV1.allCases where purpose != .inspectionReview {
            for codec in [parent.codec, photo.codec] {
                XCTAssertThrowsError(try authority.require(purpose, codec: codec)) {
                    XCTAssertEqual($0 as? FieldDraftFailureV1, .unknownPurpose)
                }
            }
        }
        for (codec, other) in [(parent.codec, photo.codec), (photo.codec, parent.codec)] {
            let altered = [
                try DraftPayloadCodecReleaseV1(codecID: codec.codecID + ".unknown", codecVersion: codec.codecVersion,
                    releaseSHA256: codec.releaseSHA256),
                try DraftPayloadCodecReleaseV1(codecID: codec.codecID, codecVersion: codec.codecVersion + 1,
                    releaseSHA256: codec.releaseSHA256),
                try DraftPayloadCodecReleaseV1(codecID: codec.codecID, codecVersion: codec.codecVersion,
                    releaseSHA256: String(repeating: "f", count: 64)),
                try DraftPayloadCodecReleaseV1(codecID: codec.codecID, codecVersion: codec.codecVersion,
                    releaseSHA256: other.releaseSHA256),
            ]
            for value in altered {
                XCTAssertThrowsError(try authority.require(.inspectionReview, codec: value)) {
                    XCTAssertEqual($0 as? FieldDraftFailureV1, .unknownCodec)
                }
            }
        }
        XCTAssertThrowsError(try authority.require(.inspectionReview, codec: RepetitiveCaptureDraftCodecV1.release())) {
            XCTAssertEqual($0 as? FieldDraftFailureV1, .unknownCodec)
        }
    }

    func testReleasedCodecsPreservePayloadBytesAndRejectCrossRoleOrNoncanonicalInput() throws {
        let f = try photoFixture()
        let child = try photoPayload(f, phase: .preparedCommit(f.pair, f.attempt))
        let parentBytes = try CheckRunnerItemDraftCodecV1.encode(f.parent)
        let photoBytes = try CheckRunnerPhotoDraftCodecV1.encode(child)
        XCTAssertEqual(parentBytes, try CheckRunnerItemDraftPayloadV1.encode(f.parent))
        XCTAssertEqual(photoBytes, try CheckRunnerPhotoDraftPayloadV1.encode(child))
        XCTAssertEqual(try CheckRunnerItemDraftCodecV1.encode(CheckRunnerItemDraftCodecV1.decode(parentBytes)), parentBytes)
        XCTAssertEqual(try CheckRunnerPhotoDraftCodecV1.encode(CheckRunnerPhotoDraftCodecV1.decode(photoBytes)), photoBytes)
        XCTAssertThrowsError(try CheckRunnerItemDraftCodecV1.decode(photoBytes))
        XCTAssertThrowsError(try CheckRunnerPhotoDraftCodecV1.decode(parentBytes))
        XCTAssertThrowsError(try CheckRunnerItemDraftCodecV1.decode(parentBytes + Data([0x20])))
        XCTAssertThrowsError(try CheckRunnerPhotoDraftCodecV1.decode(photoBytes + Data([0x20])))
        var parentObject = try jsonObject(f.parent)
        try setJSON(&parentObject, path: ["field", "preflight", "unexpected"], value: true)
        XCTAssertThrowsError(try CheckRunnerItemDraftCodecV1.decode(canonical(parentObject)))
        var photoObject = try jsonObject(child)
        try setJSON(&photoObject, path: ["phase", "pair", "raw", "inspection", "unexpected"], value: true)
        XCTAssertThrowsError(try CheckRunnerPhotoDraftCodecV1.decode(canonical(photoObject)))
    }

    func testReleasedCodecLimitsUseCompleteUTF8PayloadBytes() throws {
        let fixture = try parentFixture(recheck: false, includesTimeZone: false)
        func payload(_ note: String) throws -> CheckRunnerItemDraftPayloadV1 {
            try .init(editing: fixture.source, field: parentField(begin: .notBegun,
                outcome: .init(selection: nil, couldNotVerifyNote: note, recheckNote: "")))
        }
        let prefix = " \t/e\u{301}\n"
        let baseline = try CheckRunnerItemDraftCodecV1.encode(payload(prefix)).count
        let note = prefix + String(repeating: "a", count: CheckRunnerItemDraftCodecV1.maximumPayloadBytes - baseline)
        let bytes = try CheckRunnerItemDraftCodecV1.encode(payload(note))
        XCTAssertEqual(bytes.count, 2_097_152)
        let decoded = try CheckRunnerItemDraftCodecV1.decode(bytes)
        XCTAssertEqual(Data(decoded.field.outcome.couldNotVerifyNote.utf8), Data(note.utf8))
        XCTAssertEqual(try CheckRunnerItemDraftCodecV1.encode(decoded), bytes)
        XCTAssertThrowsError(try CheckRunnerItemDraftCodecV1.encode(payload(note + "é"))) {
            XCTAssertEqual($0 as? FieldDraftFailureV1, .limitExceeded)
        }
        for invalid in [Data(), Data(repeating: 0x20, count: 2_097_153)] {
            XCTAssertThrowsError(try CheckRunnerItemDraftCodecV1.decode(invalid)) {
                XCTAssertEqual($0 as? FieldDraftFailureV1, .limitExceeded)
            }
            XCTAssertThrowsError(try CheckRunnerPhotoDraftCodecV1.decode(invalid)) {
                XCTAssertEqual($0 as? FieldDraftFailureV1, .limitExceeded)
            }
        }
    }

    func testParentCodecCheckpointBindsPreBeginScopeBaseAndAllSemanticAnchors() throws {
        let f = try parentFixture(recheck: false, includesTimeZone: false)
        let expectedScope = try DraftScopeKeyV1(scopeKind: "INSPECTION_REVIEW", stableComponentIDs: [
            f.source.roundAtEntry.sessionID.uuidString.lowercased(), f.source.originalItem.itemID.uuidString.lowercased()])
        for anchor in CheckRunnerItemSemanticAnchorV1.allCases {
            let field = try CheckRunnerItemFieldStateV1(preflight: .init(), begin: .notBegun, outcome: .init(),
                wideContext: nil, closeDetail: nil, semanticAnchor: anchor)
            let payload = try CheckRunnerItemDraftPayloadV1(editing: f.source, field: field)
            let checkpoint = try codecParentCheckpoint(payload)
            XCTAssertNil(payload.field.begin.attempt)
            XCTAssertEqual(checkpoint.scope, expectedScope)
            XCTAssertFalse(checkpoint.scope.stableComponentIDs.contains(f.attempt.recordCommand.recordID.uuidString.lowercased()))
            XCTAssertEqual(checkpoint.baseCanonicalRevision, f.source.roundAtEntry.revision)
            XCTAssertEqual(checkpoint.stageIDs, [])
            XCTAssertEqual(checkpoint.resumeAnchor.sectionID, anchor.rawValue.lowercased())
            XCTAssertEqual(checkpoint.resumeAnchor.selectedStableID, f.source.assetID.uuidString.lowercased())
            XCTAssertNil(checkpoint.resumeAnchor.fieldID)
            XCTAssertNil(checkpoint.resumeAnchor.boundedPosition)
            XCTAssertEqual(try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint), payload)
        }
    }

    func testParentCodecRejectsRehashedEnvelopeSubstitutionsAndPhotoRole() throws {
        let f = try parentFixture(recheck: false, includesTimeZone: false)
        let payload = try CheckRunnerItemDraftPayloadV1(editing: f.source, field: parentField(begin: .notBegun))
        let checkpoint = try codecParentCheckpoint(payload)
        let hostile = [
            try codecRehashedCheckpoint(checkpoint, workspaceID: .init(rawValue: largeID(81_001))),
            try codecRehashedCheckpoint(checkpoint, scope: .init(scopeKind: "INSPECTION_REVIEW", stableComponentIDs: [
                f.source.roundAtEntry.sessionID.uuidString.lowercased(), f.attempt.recordCommand.recordID.uuidString.lowercased()])),
            try codecRehashedCheckpoint(checkpoint, scope: .init(scopeKind: "OTHER", stableComponentIDs: checkpoint.scope.stableComponentIDs)),
            try codecRehashedCheckpoint(checkpoint, baseCanonicalRevision: checkpoint.baseCanonicalRevision + 1),
            try codecRehashedCheckpoint(checkpoint, resumeAnchor: .init(sectionID: "review",
                selectedStableID: f.source.assetID.uuidString.lowercased())),
            try codecRehashedCheckpoint(checkpoint, resumeAnchor: .init(sectionID: "preflight",
                selectedStableID: largeID(81_002).uuidString.lowercased())),
            try codecRehashedCheckpoint(checkpoint, resumeAnchor: .init(sectionID: "preflight", fieldID: "unexpected",
                selectedStableID: f.source.assetID.uuidString.lowercased())),
            try codecRehashedCheckpoint(checkpoint, stageIDs: [largeID(81_003)]),
        ]
        for value in hostile {
            XCTAssertNoThrow(try value.validate())
            XCTAssertEqual(value.payloadSHA256, checkpoint.payloadSHA256)
            XCTAssertNotEqual(value.checkpointSHA256, checkpoint.checkpointSHA256)
            XCTAssertThrowsError(try CheckRunnerItemDraftCodecV1.validateCheckpoint(value))
        }
        let crossed = try codecRehashedCheckpoint(checkpoint, codec: CheckRunnerPhotoDraftCodecV1.release())
        XCTAssertNoThrow(try crossed.validate(authority: CheckRunnerDraftPurposeAuthorityV1()))
        XCTAssertThrowsError(try CheckRunnerItemDraftCodecV1.validateCheckpoint(crossed)) {
            XCTAssertEqual($0 as? FieldDraftFailureV1, .unknownCodec)
        }
    }

    func testPhotoCodecCheckpointBindsBothStepsAndAllFourDurablePhases() throws {
        for recheck in [false, true] {
            for step in [WorkflowDraftStep.wide, .close] {
                let f = try photoFixture(recheck: recheck, step: step)
                let phases: [CheckRunnerPhotoDurablePhaseV1] = [
                    .awaitingRawStage(f.intent), .rawReady(f.raw), .pairReady(f.pair), .preparedCommit(f.pair, f.attempt)]
                let expectedScope = try DraftScopeKeyV1(scopeKind: "INSPECTION_REVIEW_PHOTO", stableComponentIDs: [
                    f.parentDraftID.uuidString.lowercased(), f.childDraftID.uuidString.lowercased()])
                for (index, phase) in phases.enumerated() {
                    let payload = try photoPayload(f, phase: phase)
                    let checkpoint = try codecPhotoCheckpoint(payload)
                    XCTAssertEqual(checkpoint.scope, expectedScope)
                    XCTAssertEqual(checkpoint.draftID, f.childDraftID)
                    XCTAssertEqual(checkpoint.workspaceID, f.parent.source.roundAtEntry.workspaceID)
                    XCTAssertEqual(checkpoint.baseCanonicalRevision, f.parent.source.roundAtEntry.revision)
                    XCTAssertEqual(checkpoint.stageIDs, index == 0 ? [] : [f.intent.stageID])
                    XCTAssertEqual(checkpoint.resumeAnchor.sectionID, step == .wide ? "wide_context" : "close_detail")
                    XCTAssertEqual(checkpoint.resumeAnchor.selectedStableID, f.parent.source.assetID.uuidString.lowercased())
                    XCTAssertNil(checkpoint.resumeAnchor.fieldID)
                    XCTAssertNil(checkpoint.resumeAnchor.boundedPosition)
                    XCTAssertEqual(try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint), payload)
                    XCTAssertEqual(try CheckRunnerPhotoDraftCodecV1.encode(
                        CheckRunnerPhotoDraftCodecV1.decode(checkpoint.payloadData)), checkpoint.payloadData)
                }
            }
        }
    }

    func testPhotoCodecRejectsRehashedIdentityScopeBaseAnchorStageAndRoleSubstitutions() throws {
        let f = try photoFixture(step: .close)
        let payload = try photoPayload(f, phase: .rawReady(f.raw))
        let checkpoint = try codecPhotoCheckpoint(payload)
        let hostile = [
            try codecRehashedCheckpoint(checkpoint, draftID: largeID(82_001)),
            try codecRehashedCheckpoint(checkpoint, workspaceID: .init(rawValue: largeID(82_002))),
            try codecRehashedCheckpoint(checkpoint, scope: .init(scopeKind: "INSPECTION_REVIEW_PHOTO", stableComponentIDs: [
                largeID(82_003).uuidString.lowercased(), f.childDraftID.uuidString.lowercased()])),
            try codecRehashedCheckpoint(checkpoint, scope: .init(scopeKind: "INSPECTION_REVIEW_PHOTO", stableComponentIDs: [
                f.parentDraftID.uuidString.lowercased(), largeID(82_004).uuidString.lowercased()])),
            try codecRehashedCheckpoint(checkpoint, scope: .init(scopeKind: "INSPECTION_REVIEW", stableComponentIDs: checkpoint.scope.stableComponentIDs)),
            try codecRehashedCheckpoint(checkpoint, baseCanonicalRevision: checkpoint.baseCanonicalRevision + 1),
            try codecRehashedCheckpoint(checkpoint, resumeAnchor: .init(sectionID: "wide_context",
                selectedStableID: payload.assetID.uuidString.lowercased())),
            try codecRehashedCheckpoint(checkpoint, resumeAnchor: .init(sectionID: "close_detail",
                selectedStableID: largeID(82_005).uuidString.lowercased())),
            try codecRehashedCheckpoint(checkpoint, resumeAnchor: .init(sectionID: "close_detail", fieldID: "processing",
                selectedStableID: payload.assetID.uuidString.lowercased(), boundedPosition: 1)),
            try codecRehashedCheckpoint(checkpoint, stageIDs: []),
            try codecRehashedCheckpoint(checkpoint, stageIDs: [largeID(82_006)]),
            try codecRehashedCheckpoint(checkpoint, stageIDs: [f.intent.stageID, largeID(82_007)]),
        ]
        for value in hostile {
            XCTAssertNoThrow(try value.validate())
            XCTAssertEqual(value.payloadSHA256, checkpoint.payloadSHA256)
            XCTAssertNotEqual(value.checkpointSHA256, checkpoint.checkpointSHA256)
            XCTAssertThrowsError(try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(value))
        }
        let awaiting = try codecPhotoCheckpoint(photoPayload(f, phase: .awaitingRawStage(f.intent)))
        let prematureStage = try codecRehashedCheckpoint(awaiting, stageIDs: [f.intent.stageID])
        XCTAssertNoThrow(try prematureStage.validate(authority: CheckRunnerDraftPurposeAuthorityV1()))
        XCTAssertThrowsError(try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(prematureStage))
        let crossed = try codecRehashedCheckpoint(awaiting, codec: CheckRunnerItemDraftCodecV1.release())
        XCTAssertNoThrow(try crossed.validate(authority: CheckRunnerDraftPurposeAuthorityV1()))
        XCTAssertThrowsError(try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(crossed)) {
            XCTAssertEqual($0 as? FieldDraftFailureV1, .unknownCodec)
        }
    }

    func testCodecEnvelopeValidationPreservesRecoveryStateWithoutGrantingLifecycleAuthority() throws {
        let f = try photoFixture()
        let parent = try codecParentCheckpoint(f.parent)
        let child = try codecPhotoCheckpoint(photoPayload(f, phase: .rawReady(f.raw)))
        // These are stored value envelopes, not a sequence of permitted writes.
        // The writer and authenticated history remain responsible for transitions.
        for state in [FieldDraftStateV1.conflicted, .recoveryRequired, .discardPending] {
            let parentValue = try codecRehashedCheckpoint(parent, state: state)
            let childValue = try codecRehashedCheckpoint(child, state: state)
            XCTAssertEqual(try CheckRunnerItemDraftCodecV1.validateCheckpoint(parentValue), f.parent)
            XCTAssertEqual(try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(childValue).phase, .rawReady(f.raw))
            XCTAssertEqual(parentValue.state, state)
            XCTAssertEqual(childValue.state, state)
            XCTAssertNil(parentValue.lastReceiptSHA256)
            XCTAssertNil(childValue.lastReceiptSHA256)
        }
    }

    func testParentCommitReconstructionDerivesExactOutputsForAllSevenOutcomes() throws {
        let label = try XCTUnwrap(pack.issueLabels.first)
        let reason = try XCTUnwrap(pack.couldNotVerifyReasons.entries.first)
        let rows: [(Bool, CheckOutcomeSelection, Int)] = [
            (false, .noVisibleIssue, 3), (false, .visibleIssue(labelKey: label.key), 4),
            (false, .couldNotVerify(reasonKey: reason.key, note: "unavailable"), 3),
            (true, .resolved(note: "resolved"), 4), (true, .issueStillVisible(note: "retained"), 4),
            (true, .originalResolvedDifferentIssue(labelKey: label.key, note: "different"), 5),
            (true, .couldNotVerify(reasonKey: reason.key, note: "unavailable"), 4),
        ]
        for (index, row) in rows.enumerated() {
            let payload = try reconstructionParentPayload(recheck: row.0, selection: row.1, seed: 90_000 + index * 100)
            let checkpoint = try reconstructionParentCheckpoint(payload)
            let value = try reconstructParent(checkpoint)
            let attempt = try XCTUnwrap(payload.finalizationAttempt)
            guard case let .bound(begin, _, _) = payload.field.begin else { return XCTFail("Missing fixture Begin") }
            var expected = try [
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: begin.recordCommand.recordID).stableKey,
                WorkspaceEntityIdentityV1(kind: .packet, id: attempt.identifiers.packetID).stableKey,
                WorkspaceEntityIdentityV1(kind: .report, id: attempt.identifiers.reportID).stableKey,
            ]
            for issueID in [attempt.identifiers.issueID, attempt.identifiers.newIssueID].compactMap({ $0 }) {
                expected.append(try WorkspaceEntityIdentityV1(kind: .issue, id: issueID).stableKey)
            }
            XCTAssertEqual(value.plan.outputKeys, expected.sorted())
            XCTAssertEqual(value.plan.outputKeys.count, row.2)
            XCTAssertFalse(value.plan.outputKeys.contains { $0.contains(attempt.identifiers.stableRootID.uuidString.lowercased()) })
            XCTAssertEqual(value.plan.targetCommandKind, .finalizeCheck)
            XCTAssertEqual(value.plan.planID, attempt.fieldDraftPlanID)
            XCTAssertEqual(value.plan.mutationID.rawValue, attempt.identifiers.mutationID)
            XCTAssertEqual(value.plan.expectedTargetRevision, 7)
            XCTAssertEqual(value.items, [])
            XCTAssertEqual(value.plan.stageDigests, [])
            XCTAssertEqual(value.rowMutationIDs.reservationByStageID, [:])
        }
    }

    func testParentCommitReconstructionReusesFrozenSagasAndRowMutationsAfterColdDecode() throws {
        let fixture = try parentFixture(recheck: true, includesTimeZone: true)
        let selection = CheckOutcomeSelection.resolved(note: "e\u{301} retained")
        let field = try preparedField(fixture: fixture,
            outcome: .init(selection: .resolved(note: "e\u{301} retained"), recheckNote: " e\u{301} retained "),
            mediaCount: 2, seed: 93_000)
        let payload = try CheckRunnerItemDraftPayloadV1(prepared: fixture.source, field: field,
            attempt: finalizationAttempt(fixture: fixture, field: field, selection: selection, seed: 92_000))
        let checkpoint = try reconstructionParentCheckpoint(payload)
        let cold = try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self,
            from: FieldDraftCanonicalCodecV1.encode(checkpoint))
        let value = try reconstructParent(cold)
        XCTAssertEqual(value, try reconstructParent(checkpoint))
        let attempt = try XCTUnwrap(payload.finalizationAttempt)
        XCTAssertEqual(attempt.normalizedOutcome.selection, selection)
        XCTAssertEqual(Data(payload.field.outcome.recheckNote.utf8), Data(" e\u{301} retained ".utf8))
        XCTAssertEqual(value.sagas.map(\.sagaID), [attempt.preparedSagaID, attempt.contentPromotedSagaID,
            attempt.targetCommittedSagaID, attempt.draftRetirePendingSagaID, attempt.draftRetiredSagaID])
        XCTAssertEqual(value.sagas.map(\.state), [.prepared, .contentPromotedUnbound, .targetCommitted, .draftRetirePending, .draftRetired])
        XCTAssertEqual(value.sagas.map(\.revision), [1, 2, 3, 4, 5])
        XCTAssertEqual(value.sagas.map(\.predecessorSagaID), [nil, attempt.preparedSagaID,
            attempt.contentPromotedSagaID, attempt.targetCommittedSagaID, attempt.draftRetirePendingSagaID])
        XCTAssertEqual(value.sagas.map(\.mutationID), [attempt.preparedSagaMutationID,
            attempt.contentPromotedSagaMutationID, attempt.targetCommittedSagaMutationID,
            attempt.draftRetirePendingSagaMutationID, attempt.terminalBundleMutationID])
        XCTAssertEqual(value.sagas.map(\.updatedAt), [attempt.preparedSagaUpdatedAt,
            attempt.contentPromotedSagaUpdatedAt, attempt.targetCommittedSagaUpdatedAt,
            attempt.draftRetirePendingSagaUpdatedAt, attempt.draftRetiredSagaUpdatedAt])
        for event in value.sagas {
            XCTAssertEqual(event.plan, value.plan)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.decode(DraftCommitSagaV1.self,
                from: FieldDraftCanonicalCodecV1.encode(event)), event)
        }
        XCTAssertEqual(value.commitReceiptID, attempt.commitReceiptID)
        XCTAssertEqual(value.terminalCheckpointUpdatedAt, attempt.terminalCheckpointUpdatedAt)
        XCTAssertEqual(value.retired.mutationID, value.rowMutationIDs.terminalBundleMutationID)
    }

    func testParentCommitReconstructionRejectsUnpreparedAndNonCommittingCheckpoints() throws {
        let payload = try reconstructionParentPayload(seed: 93_000)
        let checkpoint = try reconstructionParentCheckpoint(payload)
        for state in FieldDraftStateV1.allCases where state != .committing {
            let other = try reconstructionCheckpoint(checkpoint, state: state)
            try other.validate(authority: CheckRunnerDraftPurposeAuthorityV1())
            XCTAssertThrowsError(try reconstructParent(other), state.rawValue)
        }
        let editing = try CheckRunnerItemDraftPayloadV1(editing: payload.source, field: payload.field)
        let unprepared = try reconstructionCheckpoint(codecParentCheckpoint(editing), state: .committing)
        XCTAssertThrowsError(try reconstructParent(unprepared))
        let beforeBegin = try CheckRunnerItemDraftPayloadV1(editing: payload.source, field: parentField(begin: .notBegun))
        XCTAssertThrowsError(try reconstructParent(reconstructionCheckpoint(codecParentCheckpoint(beforeBegin), state: .committing)))
    }

    func testParentCommitReconstructionRejectsUnusableTerminalRevisionTimeAndMutation() throws {
        let payload = try reconstructionParentPayload(seed: 94_000)
        let checkpoint = try reconstructionParentCheckpoint(payload)
        let attempt = try XCTUnwrap(payload.finalizationAttempt)
        let candidates = try [
            reconstructionCheckpoint(checkpoint, revision: UInt64.max),
            reconstructionCheckpoint(checkpoint, updatedAt: attempt.terminalCheckpointUpdatedAt.addingTimeInterval(0.001)),
            reconstructionCheckpoint(checkpoint, mutationID: attempt.terminalBundleMutationID),
        ]
        for candidate in candidates {
            try candidate.validate(authority: CheckRunnerDraftPurposeAuthorityV1())
            XCTAssertThrowsError(try reconstructParent(candidate))
        }
        let lastUsable = try reconstructionCheckpoint(checkpoint, revision: UInt64.max - 1,
            updatedAt: attempt.terminalCheckpointUpdatedAt)
        XCTAssertEqual(try reconstructParent(lastUsable).plan.draftRevision, UInt64.max - 1)
    }

    func testParentCommitReconstructionRequiresExactPackageAndPreparedOutcome() throws {
        let reason = try XCTUnwrap(pack.couldNotVerifyReasons.entries.first)
        let payload = try reconstructionParentPayload(selection: .couldNotVerify(reasonKey: reason.key, note: "original"), seed: 95_000)
        let checkpoint = try reconstructionParentCheckpoint(payload)
        var changedRaw = try jsonObject(payload)
        try setJSON(&changedRaw, path: ["field", "outcome", "couldNotVerifyNote"], value: "changed editor")
        let changedPayload = try decodeObject(CheckRunnerItemDraftPayloadV1.self, changedRaw)
        XCTAssertEqual(changedPayload.finalizationAttempt, payload.finalizationAttempt)
        XCTAssertNotEqual(changedPayload.field.outcome.couldNotVerifyNote, payload.field.outcome.couldNotVerifyNote)
        let changedCheckpoint = try reconstructionParentCheckpoint(changedPayload)
        XCTAssertThrowsError(try reconstructParent(changedCheckpoint))
        let driftPack = SignPack(schemaVersion: pack.schemaVersion,
            packID: "fixture.reconstruction.wrong-package.v1", contentVersion: pack.contentVersion,
            nouns: pack.nouns, evidencePurposes: pack.evidencePurposes, acknowledgements: pack.acknowledgements,
            issueLabels: pack.issueLabels, couldNotVerifyReasons: pack.couldNotVerifyReasons,
            stageDisplays: pack.stageDisplays, outcomeDisplays: pack.outcomeDisplays, disclaimer: pack.disclaimer)
        let driftProfile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: driftPack)
        XCTAssertThrowsError(try CheckRunnerItemDraftCodecV1.reconstructFinalizationCommit(from: checkpoint,
            signPack: driftPack, activeLifecycleProfile: { driftProfile }))
        XCTAssertThrowsError(try CheckRunnerItemDraftCodecV1.reconstructFinalizationCommit(from: checkpoint,
            signPack: pack, activeLifecycleProfile: { driftProfile }))
        XCTAssertNoThrow(try reconstructParent(checkpoint))
    }

    func testPhotoCommitReconstructionBindsBothStepsAndFrozenReadyStage() throws {
        for recheck in [false, true] {
            for step in [WorkflowDraftStep.wide, .close] {
                for origin in [OriginalContentOriginV1.humanCapture, .localImport] {
                    let fixture = try photoFixture(recheck: recheck, step: step, origin: origin)
                    let payload = try photoPayload(fixture, phase: .preparedCommit(fixture.pair, fixture.attempt))
                    let checkpoint = try codecPhotoCheckpoint(payload)
                    let value = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: checkpoint)
                    let commit = value.draftCommit, command = value.targetCommand
                    XCTAssertEqual(commit.items, [fixture.raw.readyItem])
                    XCTAssertEqual(commit.items[0].state, .readyLocal)
                    XCTAssertEqual(commit.plan.stageDigests, [fixture.raw.readyItem.stageSHA256])
                    XCTAssertEqual(commit.plan.targetCommandKind, .acceptCheckEvidence)
                    XCTAssertEqual(commit.plan.planID, fixture.attempt.planID)
                    XCTAssertEqual(commit.plan.outputKeys, fixture.attempt.outputKeys)
                    XCTAssertEqual(commit.plan.expectedTargetRevision, fixture.attempt.expectedWorkflowRecordRevision)
                    XCTAssertEqual(commit.rowMutationIDs.reservationByStageID, [fixture.intent.stageID: fixture.attempt.reservationMutationID])
                    XCTAssertEqual(command.draftID, fixture.parentFixture.attempt.recordCommand.recordID)
                    XCTAssertNotEqual(command.draftID, fixture.childDraftID)
                    XCTAssertEqual(command.evidenceID, fixture.intent.evidenceID)
                    XCTAssertEqual(commit.plan.mutationID.rawValue, command.evidenceID)
                    XCTAssertEqual(command.purposeKey, step == .wide ? "wide_context" : "close_detail")
                    XCTAssertEqual(command.nextDraftStepKey, step == .wide ? WorkflowDraftStep.close.rawValue : WorkflowDraftStep.outcome.rawValue)
                    XCTAssertEqual(command.relativePath, fixture.pair.normalizedPair.originalRelativePath)
                    XCTAssertEqual(command.mimeType, "image/jpeg")
                    XCTAssertEqual(command.byteCount, 128)
                    XCTAssertEqual(command.sha256, String(repeating: "c", count: 64))
                    XCTAssertEqual(command.thumbnailRelativePath, fixture.pair.normalizedPair.thumbnailRelativePath)
                    XCTAssertEqual(command.thumbnailByteCount, 64)
                    XCTAssertEqual(command.thumbnailSHA256, String(repeating: "e", count: 64))
                    XCTAssertEqual(command.createdAt, Date(timeIntervalSince1970: 1_800_000_200))
                }
            }
        }
    }

    @MainActor
    func testPhotoCommitReconstructionReusesFrozenSagasRowsAndCommandsAfterColdDecode() throws {
        let codecFixture = try photoFixture(recheck: true, step: .close, origin: .localImport)
        let payload = try photoPayload(codecFixture, phase: .preparedCommit(codecFixture.pair, codecFixture.attempt))
        let checkpoint = try codecPhotoCheckpoint(payload)
        let cold = try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self,
            from: FieldDraftCanonicalCodecV1.encode(checkpoint))
        let first = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: checkpoint)
        XCTAssertEqual(try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: cold), first)
        let value = first.draftCommit, attempt = codecFixture.attempt
        XCTAssertEqual(value.sagas.map(\.state), [.prepared, .contentPromotedUnbound, .targetCommitted, .draftRetirePending, .draftRetired])
        XCTAssertEqual(value.sagas.map(\.sagaID), [attempt.preparedSagaID, attempt.contentPromotedSagaID,
            attempt.targetCommittedSagaID, attempt.draftRetirePendingSagaID, attempt.draftRetiredSagaID])
        XCTAssertEqual(value.sagas.map(\.revision), [1, 2, 3, 4, 5])
        XCTAssertEqual(value.sagas.map(\.predecessorSagaID), [nil, attempt.preparedSagaID,
            attempt.contentPromotedSagaID, attempt.targetCommittedSagaID, attempt.draftRetirePendingSagaID])
        XCTAssertEqual(value.sagas.map(\.mutationID), [attempt.preparedSagaMutationID,
            attempt.contentPromotedSagaMutationID, attempt.targetCommittedSagaMutationID,
            attempt.draftRetirePendingSagaMutationID, attempt.terminalBundleMutationID])
        XCTAssertEqual(value.sagas.map(\.updatedAt), [attempt.preparedUpdatedAt, attempt.contentPromotedUpdatedAt,
            attempt.targetCommittedUpdatedAt, attempt.draftRetirePendingUpdatedAt, attempt.draftRetiredUpdatedAt])
        for (prior, next) in zip(value.sagas, value.sagas.dropFirst()) { try next.validateSuccessor(of: prior) }
        XCTAssertEqual(value.commitReceiptID, attempt.commitReceiptID)
        XCTAssertEqual(value.terminalCheckpointUpdatedAt, attempt.terminalCheckpointUpdatedAt)
        XCTAssertEqual(value.retired.mutationID, value.rowMutationIDs.terminalBundleMutationID)
        XCTAssertEqual(value.plan.payloadSHA256, checkpoint.payloadSHA256)

        func observe<T>(_ boundary: String, _ operation: () throws -> T) throws -> T {
#if DEBUG
            do {
                return try operation()
            } catch {
                let nsError = error as NSError
                let detail = "V23_FIELD_BOUNDARY boundary=\(boundary) reflectedType=\(String(reflecting: type(of: error))) domain=\(nsError.domain) code=\(nsError.code)"
                FileHandle.standardError.write(Data((detail + "\n").utf8))
                XCTFail(detail)
                throw error
            }
#else
            return try operation()
#endif
        }

        let fixture = try photoFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23-photo-commit-read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: fixture.parent.source.roundAtEntry.workspaceID,
            replicaID: .init(rawValue: largeID(70_001)))
        let factory = StoreGenerationFactory(applicationSupportURL: root, pointerEnrichmentIdentity: identity)
        let clock = FrozenBeginClock(value: Date(timeIntervalSince1970: 1_800_001_000))
        var session: StoreGenerationSession? = try observe("openInitial") {
            try factory.openOrBootstrapCurrent()
        }
        var coordinator: StoreSessionCoordinator? = try observe("coordinatorInitial") {
            try StoreSessionCoordinator(validatingSession: try XCTUnwrap(session), clock: clock)
        }
        defer { try? coordinator?.invalidateAndReleaseWriter() }
        let stored = try observe("persistPhotoCommit") {
            try persistPhotoCommit(fixture, coordinator: try XCTUnwrap(coordinator))
        }
        let writer = try XCTUnwrap(coordinator).workspaceWriter
        let before = try observe("initialSnapshotAndReads") { try writer.sourceMutationHistorySnapshot() }
        let actual = try observe("initialSnapshotAndReads") {
            try XCTUnwrap(writer.checkRunnerPhotoCommitEvidence(
                workspaceID: stored.checkpoint.workspaceID, draftID: stored.checkpoint.draftID))
        }
        XCTAssertEqual(actual, stored.evidence)
        XCTAssertEqual(actual.committing.mutation, stored.history.first {
            if case let .reviseCheckpoint(value) = $0.mutation.postImage { return value.state == .committing }; return false
        }?.mutation)
        XCTAssertEqual(actual.terminal.mutation.mutationID, fixture.attempt.terminalBundleMutationID)
        XCTAssertEqual(try observe("initialSnapshotAndReads") {
            try writer.sourceMutationHistorySnapshot()
        }, before)
        let parentActual = try observe("initialSnapshotAndReads") {
            try XCTUnwrap(writer.checkRunnerPhotoParentEvidence(
                workspaceID: stored.parentCheckpoint.workspaceID, parentDraftID: fixture.parentDraftID,
                childDraftID: fixture.childDraftID))
        }
        XCTAssertEqual(parentActual, stored.parentEvidence)
        XCTAssertEqual(parentActual.checkpoint, stored.parentCheckpoint)
        XCTAssertEqual(parentActual.pending.mutation.mutationID, stored.parentPendingCheckpoint.mutationID)
        XCTAssertEqual(parentActual.slot, try XCTUnwrap(
            CheckRunnerItemDraftCodecV1.validateCheckpoint(stored.parentCheckpoint).field.wideContext))
        XCTAssertEqual(parentActual.child.creating.mutation.mutationID, stored.history[0].mutation.mutationID)
        XCTAssertEqual(parentActual.child, stored.evidence)
        let readCurrentPhoto = {
            try writer.checkRunnerPhotoCurrentTargetEvidence(workspaceID: stored.parentCheckpoint.workspaceID,
                parentDraftID: fixture.parentDraftID, childDraftID: fixture.childDraftID)
        }
        let currentPhoto = try observe("currentPhotoInitial") { try XCTUnwrap(readCurrentPhoto()) }
        XCTAssertEqual(currentPhoto.parent, parentActual)
        XCTAssertEqual(currentPhoto.workflow.id, actual.target.command.draftID)
        XCTAssertEqual(currentPhoto.workflow.draftStepKey, WorkflowDraftStep.close.rawValue)
        XCTAssertTrue(actual.target.receipt.postImages.contains(currentPhoto.workflowPostImage))
        XCTAssertTrue(actual.target.receipt.postImages.contains(currentPhoto.evidencePostImage))
        XCTAssertEqual(currentPhoto.evidence.id, actual.target.command.evidenceID)
        XCTAssertEqual(currentPhoto.evidencePostImage.revision, 1)
        XCTAssertTrue(currentPhoto.laterPhotos.isEmpty)
        XCTAssertNil(currentPhoto.finalization)
        let workflowChanges: [(String, Any)] = [
            ("assetID", largeID(70_020).uuidString.lowercased()), ("stage", WorkflowStage.recheck.rawValue),
            ("packContentVersion", currentPhoto.workflow.packContentVersion + 1),
            ("draftStepKey", WorkflowDraftStep.review.rawValue),
            ("recordRevisionRootID", largeID(70_021).uuidString.lowercased()),
            ("observationBasisV1Data", Data("changed".utf8).base64EncodedString()),
        ]
        for (key, value) in workflowChanges {
            var object = try jsonObject(currentPhoto.workflow); object[key] = value
            let changed = try decodeObject(V4BackupWorkflowRecordDTO.self, object)
            XCTAssertThrowsError(try CheckRunnerPhotoCurrentTargetEvidenceV1(parent: currentPhoto.parent,
                workflow: changed, workflowPostImage: currentPhoto.workflowPostImage,
                evidence: currentPhoto.evidence, evidencePostImage: currentPhoto.evidencePostImage,
                laterReceipts: []), key)
        }
        let evidenceChanges: [(String, Any)] = [
            ("recordID", largeID(70_022).uuidString.lowercased()), ("purposeKey", "close_detail"),
            ("byteCount", currentPhoto.evidence.byteCount + 1), ("sha256", String(repeating: "f", count: 64)),
            ("relativePath", "evidence/replaced.jpg"),
        ]
        for (key, value) in evidenceChanges {
            var object = try jsonObject(currentPhoto.evidence); object[key] = value
            let changed = try decodeObject(V4BackupEvidenceFileDTO.self, object)
            XCTAssertThrowsError(try CheckRunnerPhotoCurrentTargetEvidenceV1(parent: currentPhoto.parent,
                workflow: currentPhoto.workflow, workflowPostImage: currentPhoto.workflowPostImage,
                evidence: changed, evidencePostImage: currentPhoto.evidencePostImage,
                laterReceipts: []), key)
        }
        XCTAssertThrowsError(try writer.checkRunnerPhotoCurrentTargetEvidence(
            workspaceID: WorkspaceID(rawValue: largeID(70_003)), parentDraftID: fixture.parentDraftID,
            childDraftID: fixture.childDraftID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongWorkspace)
        }
        XCTAssertNil(try writer.checkRunnerPhotoCurrentTargetEvidence(workspaceID: stored.parentCheckpoint.workspaceID,
            parentDraftID: fixture.parentDraftID, childDraftID: largeID(70_002)))
        XCTAssertThrowsError(try writer.checkRunnerPhotoCurrentTargetEvidence(
            workspaceID: stored.parentCheckpoint.workspaceID, parentDraftID: fixture.parentDraftID,
            childDraftID: stored.missingSelectedChildID))
        XCTAssertThrowsError(try writer.checkRunnerPhotoCurrentTargetEvidence(
            workspaceID: stored.parentCheckpoint.workspaceID, parentDraftID: stored.partialParentDraftID,
            childDraftID: fixture.childDraftID))
        // Deliberately corrupt only this disposable store's physical target.
        // Restore exact values after each denial; receipt history never changes.
        let currentContext = try XCTUnwrap(session).modelContext
        let originalEvidenceRow = try XCTUnwrap(currentContext.fetch(FetchDescriptor<EvidenceFile>()).first {
            $0.id == currentPhoto.evidence.id
        })
        originalEvidenceRow.byteCount += 1
        XCTAssertThrowsError(try readCurrentPhoto()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .persistenceFailed)
        }
        try observe("currentPhotoChangedEvidence") { try currentContext.save() }
        XCTAssertThrowsError(try readCurrentPhoto())
        originalEvidenceRow.byteCount = currentPhoto.evidence.byteCount
        try observe("currentPhotoRestoreEvidence") { try currentContext.save() }
        XCTAssertEqual(try readCurrentPhoto(), currentPhoto)
        let workflowRevisionRow = try XCTUnwrap(currentContext.fetch(FetchDescriptor<EntityMutationRevisionRow>()).first {
            $0.entityID == currentPhoto.workflow.id && $0.kind == WorkspaceEntityKindV1.workflowRecord.rawValue
        })
        let exactWorkflowRevision = workflowRevisionRow.revision
        workflowRevisionRow.revision += 1
        try observe("currentPhotoRevisionGap") { try currentContext.save() }
        XCTAssertThrowsError(try readCurrentPhoto())
        workflowRevisionRow.revision = exactWorkflowRevision
        try observe("currentPhotoRestoreRevision") { try currentContext.save() }
        currentContext.delete(originalEvidenceRow)
        try observe("currentPhotoMissingEvidence") { try currentContext.save() }
        XCTAssertThrowsError(try readCurrentPhoto())
        let image = currentPhoto.evidence
        currentContext.insert(EvidenceFile(id: image.id, recordID: image.recordID, purposeKey: image.purposeKey,
            relativePath: image.relativePath, mimeType: image.mimeType, byteCount: image.byteCount,
            sha256: image.sha256, createdAt: image.createdAt, thumbnailRelativePath: image.thumbnailRelativePath,
            thumbnailByteCount: image.thumbnailByteCount, thumbnailSHA256: image.thumbnailSHA256))
        try observe("currentPhotoRestoreEvidence") { try currentContext.save() }
        XCTAssertEqual(try readCurrentPhoto(), currentPhoto)
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), before)
        let parentPreparedReceipt = stored.parentHistory[1].receipt
        XCTAssertEqual(parentPreparedReceipt.resultingRevision.generationID,
            stored.timeZoneEvidence.receipt.resultingRevision.generationID)
        XCTAssertLessThan(parentPreparedReceipt.resultingRevision.workspaceRevision,
            stored.timeZoneEvidence.receipt.resultingRevision.workspaceRevision)
        XCTAssertLessThan(stored.timeZoneEvidence.receipt.resultingRevision.workspaceRevision,
            stored.workflowEvidence.receipt.resultingRevision.workspaceRevision)
        XCTAssertLessThan(stored.parentEvidence.pending.receipt.resultingRevision.workspaceRevision,
            stored.evidence.creating.receipt.resultingRevision.workspaceRevision)
        XCTAssertLessThan(stored.evidence.terminal.receipt.resultingRevision.workspaceRevision,
            stored.parentHistory[4].receipt.resultingRevision.workspaceRevision)
        XCTAssertEqual(try observe("initialSnapshotAndReads") {
            try writer.sourceMutationHistorySnapshot()
        }, before)
        XCTAssertNil(try observe("initialSnapshotAndReads") {
            try writer.checkRunnerPhotoCommitEvidence(workspaceID: stored.checkpoint.workspaceID,
                draftID: largeID(70_002))
        })
        XCTAssertNil(try observe("initialSnapshotAndReads") {
            try writer.checkRunnerPhotoCommitEvidence(workspaceID: WorkspaceID(rawValue: largeID(70_003)),
                draftID: stored.checkpoint.draftID)
        })
        XCTAssertNil(try observe("initialSnapshotAndReads") {
            try writer.checkRunnerPhotoParentEvidence(workspaceID: stored.parentCheckpoint.workspaceID,
                parentDraftID: largeID(70_002), childDraftID: fixture.childDraftID)
        })
        XCTAssertNil(try observe("initialSnapshotAndReads") {
            try writer.checkRunnerPhotoParentEvidence(workspaceID: stored.parentCheckpoint.workspaceID,
                parentDraftID: fixture.parentDraftID, childDraftID: largeID(70_002))
        })
        XCTAssertNil(try observe("initialSnapshotAndReads") {
            try writer.checkRunnerPhotoParentEvidence(workspaceID: WorkspaceID(rawValue: largeID(70_003)),
                parentDraftID: fixture.parentDraftID, childDraftID: fixture.childDraftID)
        })
        XCTAssertThrowsError(try writer.checkRunnerPhotoParentEvidence(
            workspaceID: stored.parentCheckpoint.workspaceID, parentDraftID: fixture.parentDraftID,
            childDraftID: stored.missingSelectedChildID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertThrowsError(try writer.checkRunnerPhotoParentEvidence(
            workspaceID: stored.parentCheckpoint.workspaceID, parentDraftID: stored.partialParentDraftID,
            childDraftID: largeID(70_002))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(try observe("initialSnapshotAndReads") {
            try writer.sourceMutationHistorySnapshot()
        }, before)

        let closeID = largeID(70_005)
        let closeCommand = CheckEvidenceMutationV1(evidenceID: closeID,
            draftID: fixture.parentFixture.attempt.recordCommand.recordID, purposeKey: "close_detail",
            relativePath: "evidence/close.jpg", mimeType: "image/jpeg", byteCount: 1,
            sha256: String(repeating: "3", count: 64), thumbnailRelativePath: "evidence/close-thumb.jpg",
            thumbnailByteCount: 1, thumbnailSHA256: String(repeating: "4", count: 64),
            nextDraftStepKey: WorkflowDraftStep.outcome.rawValue,
            createdAt: fixture.attempt.terminalCheckpointUpdatedAt.addingTimeInterval(0.5))
        _ = try observe("currentPhotoCloseSuccessor") {
            try writer.execute(.acceptCheckEvidence(closeCommand), mutationID: .init(rawValue: closeID))
        }
        let closeOriginal = try XCTUnwrap(writer.checkRunnerPhotoEvidence(workspaceID: stored.checkpoint.workspaceID,
            mutationID: .init(rawValue: closeID)))
        let currentAfterClose = try observe("currentPhotoCloseSuccessor") { try XCTUnwrap(readCurrentPhoto()) }
        XCTAssertEqual(currentAfterClose.parent, currentPhoto.parent)
        XCTAssertEqual(currentAfterClose.evidence, currentPhoto.evidence)
        XCTAssertEqual(currentAfterClose.evidencePostImage, currentPhoto.evidencePostImage)
        XCTAssertEqual(currentAfterClose.workflow.draftStepKey, WorkflowDraftStep.outcome.rawValue)
        XCTAssertEqual(currentAfterClose.workflowPostImage.revision, currentPhoto.workflowPostImage.revision + 1)
        XCTAssertEqual(currentAfterClose.laterPhotos, [closeOriginal])
        XCTAssertNil(currentAfterClose.finalization)
        let closePair = (closeOriginal.envelope, closeOriginal.receipt)
        let rebuildCurrent = { (pairs: [(MutationEnvelopeV1, MutationReceiptV1)]) throws in
            try CheckRunnerPhotoCurrentTargetEvidenceV1(parent: currentAfterClose.parent,
                workflow: currentAfterClose.workflow, workflowPostImage: currentAfterClose.workflowPostImage,
                evidence: currentAfterClose.evidence, evidencePostImage: currentAfterClose.evidencePostImage,
                laterReceipts: pairs)
        }
        XCTAssertEqual(try rebuildCurrent([closePair]), currentAfterClose)
        XCTAssertThrowsError(try rebuildCurrent([]))
        XCTAssertThrowsError(try rebuildCurrent([closePair, closePair]))
        XCTAssertThrowsError(try rebuildCurrent([(actual.target.envelope, actual.target.receipt)]))
        let closeQuarantine = MutationQuarantineRow(workspaceID: stored.checkpoint.workspaceID,
            mutationID: closeOriginal.receipt.mutationID, identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: closeOriginal.receipt.envelopeSHA256,
            conflictingIdentitySHA256: String(repeating: "e", count: 64), detectedAt: Date())
        currentContext.insert(closeQuarantine)
        try observe("currentPhotoQuarantinedSuccessor") { try currentContext.save() }
        XCTAssertThrowsError(try readCurrentPhoto()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        currentContext.delete(closeQuarantine)
        try observe("currentPhotoRestoreSuccessor") { try currentContext.save() }
        XCTAssertEqual(try readCurrentPhoto(), currentAfterClose)

        let laterID = largeID(70_004)
        let laterCommand = CheckEvidenceMutationV1(evidenceID: laterID,
            draftID: fixture.parentFixture.attempt.recordCommand.recordID, purposeKey: "later_history",
            relativePath: "evidence/later.jpg", mimeType: "image/jpeg", byteCount: 1,
            sha256: String(repeating: "1", count: 64), thumbnailRelativePath: "evidence/later-thumb.jpg",
            thumbnailByteCount: 1, thumbnailSHA256: String(repeating: "2", count: 64),
            nextDraftStepKey: WorkflowDraftStep.outcome.rawValue,
            createdAt: fixture.attempt.terminalCheckpointUpdatedAt.addingTimeInterval(1))
        _ = try observe("laterMutationAndRead") {
            try writer.execute(.acceptCheckEvidence(laterCommand), mutationID: .init(rawValue: laterID))
        }
        XCTAssertEqual(try observe("laterMutationAndRead") {
            try writer.checkRunnerPhotoCommitEvidence(workspaceID: stored.checkpoint.workspaceID,
                draftID: stored.checkpoint.draftID)
        }, stored.evidence)
        let laterTarget = try observe("laterMutationAndRead") {
            try XCTUnwrap(writer.checkRunnerPhotoEvidence(workspaceID: stored.checkpoint.workspaceID,
                mutationID: .init(rawValue: laterID)))
        }
        // The original child remains historical evidence, but the unrelated
        // extra accept cannot authorize this current target, even at outcome.
        XCTAssertThrowsError(try readCurrentPhoto()) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertThrowsError(try rebuildCurrent([closePair, (laterTarget.envelope, laterTarget.receipt)]))

        let pure = { (history: [FieldDraftCommittedEvidenceV1], checkpoint: FieldDraftCheckpointV1,
                      sagas: [DraftCommitSagaV1], reservations: [DraftContentReservationV1],
                      stages: [AttachmentStagingItemV1], receipts: [DraftCommitReceiptV1],
                      target: CheckRunnerPhotoCommittedEvidenceV1) throws in
            try CheckRunnerPhotoCommitEvidenceV1(history: history, checkpoint: checkpoint, sagas: sagas,
                reservations: reservations, stages: stages, receipts: receipts, target: target)
        }
        let parentPure = { (history: [FieldDraftCommittedEvidenceV1], checkpoint: FieldDraftCheckpointV1,
                            child: CheckRunnerPhotoCommitEvidenceV1,
                            workflow: CheckRunnerBeginCommittedEvidenceV1,
                            timeZone: CheckRunnerBeginCommittedEvidenceV1?) throws in
            try CheckRunnerPhotoParentEvidenceV1(history: history, checkpoint: checkpoint,
                child: child, workflow: workflow, timeZone: timeZone)
        }
        let changedReservation = try DraftContentReservationV1(reservationID: stored.reservation.reservationID,
            workspaceID: stored.reservation.workspaceID, draftID: stored.reservation.draftID,
            stageID: stored.reservation.stageID, commitPlanSHA256: stored.reservation.commitPlanSHA256,
            mutationID: stored.reservation.mutationID, contentDigest: stored.reservation.contentDigest,
            locator: stored.reservation.locator, createdAt: stored.reservation.createdAt,
            reviewAfter: stored.reservation.reviewAfter.addingTimeInterval(1),
            reconciliationState: stored.reservation.reconciliationState, revision: stored.reservation.revision)
        let changedReceipt = try DraftCommitReceiptV1(receiptID: stored.receipt.receiptID,
            workspaceID: stored.receipt.workspaceID, draftID: stored.receipt.draftID,
            sagaID: stored.receipt.sagaID, commitPlanSHA256: stored.receipt.commitPlanSHA256,
            sagaEventSHA256Chain: stored.receipt.sagaEventSHA256Chain,
            targetMutationID: stored.receipt.targetMutationID,
            targetReceiptSHA256: String(repeating: "f", count: 64),
            consumedStageToContentID: stored.receipt.consumedStageToContentID,
            committedAt: stored.receipt.committedAt, revision: stored.receipt.revision,
            mutationID: stored.receipt.mutationID)
        let unrelatedStage = try photoFixture(step: .close).raw.readyItem
        XCTAssertEqual(try pure(stored.history, stored.checkpoint, stored.sagas, [stored.reservation],
            [stored.stage], [stored.receipt], stored.target), stored.evidence)
        let readyHistory = stored.history.filter { $0.mutation.mutationID != stored.stage.mutationID }
        let readyEvidence = try pure(readyHistory, stored.checkpoint, stored.sagas, [stored.reservation],
            [fixture.raw.readyItem], [stored.receipt], stored.target)
        XCTAssertEqual(readyEvidence.stage, fixture.raw.readyItem)
        XCTAssertEqual(readyEvidence.reconstruction, stored.evidence.reconstruction)
        for changed in [Array(stored.history.dropFirst()), stored.history + [stored.history[0]],
                        stored.history.filter { $0.mutation.mutationID != fixture.attempt.terminalBundleMutationID }] {
            XCTAssertThrowsError(try pure(changed, stored.checkpoint, stored.sagas, [stored.reservation],
                [stored.stage], [stored.receipt], stored.target))
        }
        XCTAssertThrowsError(try pure(stored.history, stored.checkpoint, Array(stored.sagas.dropLast()),
            [stored.reservation], [stored.stage], [stored.receipt], stored.target))
        XCTAssertThrowsError(try pure(stored.history, stored.checkpoint, stored.sagas, [],
            [stored.stage], [stored.receipt], stored.target))
        XCTAssertThrowsError(try pure(stored.history, stored.checkpoint, stored.sagas, [stored.reservation],
            [], [stored.receipt], stored.target))
        XCTAssertThrowsError(try pure(stored.history, stored.checkpoint, stored.sagas, [stored.reservation],
            [stored.stage], [], stored.target))
        XCTAssertThrowsError(try pure(stored.history, stored.checkpoint, stored.sagas, [stored.reservation],
            [stored.stage], [stored.receipt], laterTarget))
        XCTAssertThrowsError(try pure(stored.history, stored.checkpoint, stored.sagas, [changedReservation],
            [stored.stage], [stored.receipt], stored.target))
        XCTAssertThrowsError(try pure(stored.history, stored.checkpoint, stored.sagas, [stored.reservation],
            [unrelatedStage], [stored.receipt], stored.target))
        XCTAssertThrowsError(try pure(stored.history, stored.checkpoint, stored.sagas, [stored.reservation],
            [stored.stage], [changedReceipt], stored.target))
        XCTAssertThrowsError(try pure(stored.history, stored.checkpoint, stored.sagas,
            [stored.reservation, stored.reservation], [stored.stage], [stored.receipt], stored.target))
        XCTAssertThrowsError(try pure(stored.history, stored.checkpoint, stored.sagas, [stored.reservation],
            [stored.stage, stored.stage], [stored.receipt], stored.target))
        XCTAssertThrowsError(try pure(stored.history, stored.checkpoint, stored.sagas, [stored.reservation],
            [stored.stage], [stored.receipt, stored.receipt], stored.target))
        XCTAssertThrowsError(try pure(stored.history, stored.evidence.reconstruction.draftCommit.checkpoint,
            stored.sagas, [stored.reservation], [stored.stage], [stored.receipt], stored.target))
        XCTAssertEqual(try parentPure(stored.parentHistory, stored.parentCheckpoint,
            stored.evidence, stored.workflowEvidence, stored.timeZoneEvidence), stored.parentEvidence)
        XCTAssertEqual(try parentPure(Array(stored.parentHistory.reversed()), stored.parentCheckpoint,
            stored.evidence, stored.workflowEvidence, stored.timeZoneEvidence), stored.parentEvidence)
        let pendingParent = try parentPure(Array(stored.parentHistory.prefix(4)),
            stored.parentPendingCheckpoint, stored.evidence, stored.workflowEvidence, stored.timeZoneEvidence)
        XCTAssertEqual(pendingParent.pending.mutation.mutationID, stored.parentPendingCheckpoint.mutationID)
        XCTAssertEqual(pendingParent.slot, stored.parentEvidence.slot)
        XCTAssertEqual(pendingParent.child, stored.evidence)
        let pendingPayload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(stored.parentPendingCheckpoint)
        XCTAssertEqual(pendingPayload.field.outcome.couldNotVerifyNote, "raw pending note")
        let currentParentPayload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(stored.parentCheckpoint)
        XCTAssertEqual(currentParentPayload.field.outcome.couldNotVerifyNote, "raw retry note")
        let wrongParentTime = try parentCheckpoint(fixture, payload: currentParentPayload,
            revision: stored.parentCheckpoint.draftRevision,
            updatedAt: stored.parentCheckpoint.updatedAt.addingTimeInterval(0.001),
            mutationID: stored.parentCheckpoint.mutationID)
        XCTAssertThrowsError(try parentPure(stored.parentHistory, wrongParentTime,
            stored.evidence, stored.workflowEvidence, stored.timeZoneEvidence))
        let wrongCurrentSlot = try parentCheckpoint(fixture,
            payload: parentPayload(fixture, begin: currentParentPayload.field.begin,
                slot: pendingSlot(id: fixture.childDraftID, step: fixture.step),
                outcome: currentParentPayload.field.outcome),
            revision: stored.parentCheckpoint.draftRevision, updatedAt: stored.parentCheckpoint.updatedAt,
            mutationID: stored.parentCheckpoint.mutationID)
        XCTAssertThrowsError(try parentPure(stored.parentHistory, wrongCurrentSlot,
            stored.evidence, stored.workflowEvidence, stored.timeZoneEvidence))
        for index in stored.parentHistory.indices {
            var missing = stored.parentHistory
            missing.remove(at: index)
            XCTAssertThrowsError(try parentPure(missing, stored.parentCheckpoint,
                stored.evidence, stored.workflowEvidence, stored.timeZoneEvidence), "missing parent revision \(index + 1)")
        }
        XCTAssertThrowsError(try parentPure(stored.parentHistory + [stored.parentHistory[0]],
            stored.parentCheckpoint, stored.evidence, stored.workflowEvidence, stored.timeZoneEvidence))
        XCTAssertThrowsError(try parentPure(stored.parentHistory + [stored.history[0]],
            stored.parentCheckpoint, stored.evidence, stored.workflowEvidence, stored.timeZoneEvidence))
        XCTAssertThrowsError(try parentPure(stored.parentHistory, stored.checkpoint,
            stored.evidence, stored.workflowEvidence, stored.timeZoneEvidence))
        XCTAssertThrowsError(try parentPure(stored.parentHistory, stored.parentCheckpoint,
            stored.evidence, fixture.parentFixture.workflowEvidence, stored.timeZoneEvidence))
        XCTAssertThrowsError(try parentPure(stored.parentHistory, stored.parentCheckpoint,
            stored.evidence, stored.workflowEvidence, nil))
        XCTAssertThrowsError(try parentPure(stored.parentHistory, stored.parentCheckpoint,
            stored.evidence, stored.workflowEvidence, fixture.parentFixture.workflowEvidence))
        XCTAssertThrowsError(try CheckRunnerPhotoParentEvidenceV1(history: stored.parentHistory,
            checkpoint: stored.parentCheckpoint, child: stored.evidence, workflow: stored.workflowEvidence,
            timeZone: fixture.parentFixture.workflowEvidence))

        try observe("explicitClose") { try coordinator?.invalidateAndReleaseWriter() }
        coordinator = nil; session = nil
        session = try observe("openReopened") { try factory.openOrBootstrapCurrent() }
        coordinator = try observe("coordinatorReopened") {
            try StoreSessionCoordinator(validatingSession: try XCTUnwrap(session), clock: clock)
        }
        let reopenedWriter = try XCTUnwrap(coordinator).workspaceWriter
        let reopenedBefore = try observe("reopenedReads") {
            try reopenedWriter.sourceMutationHistorySnapshot()
        }
        XCTAssertEqual(try observe("reopenedReads") {
            try reopenedWriter.checkRunnerPhotoCommitEvidence(workspaceID: stored.checkpoint.workspaceID,
                draftID: stored.checkpoint.draftID)
        }, stored.evidence)
        XCTAssertEqual(try observe("reopenedReads") {
            try reopenedWriter.checkRunnerPhotoParentEvidence(workspaceID: stored.parentCheckpoint.workspaceID,
                parentDraftID: fixture.parentDraftID, childDraftID: fixture.childDraftID)
        }, stored.parentEvidence)
        XCTAssertThrowsError(try reopenedWriter.checkRunnerPhotoCurrentTargetEvidence(
            workspaceID: stored.parentCheckpoint.workspaceID, parentDraftID: fixture.parentDraftID,
            childDraftID: fixture.childDraftID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(try observe("reopenedReads") {
            try reopenedWriter.sourceMutationHistorySnapshot()
        }, reopenedBefore)
        let quarantine = MutationQuarantineRow(workspaceID: stored.checkpoint.workspaceID,
            mutationID: fixture.attempt.terminalBundleMutationID, identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: actual.terminal.receipt.envelopeSHA256,
            conflictingIdentitySHA256: String(repeating: "f", count: 64), detectedAt: Date())
        try XCTUnwrap(session).modelContext.insert(quarantine)
        try observe("quarantineSaveAndRead") { try XCTUnwrap(session).modelContext.save() }
        XCTAssertThrowsError(try reopenedWriter.checkRunnerPhotoCommitEvidence(workspaceID: stored.checkpoint.workspaceID,
            draftID: stored.checkpoint.draftID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try reopenedWriter.checkRunnerPhotoCurrentTargetEvidence(
            workspaceID: stored.parentCheckpoint.workspaceID, parentDraftID: fixture.parentDraftID,
            childDraftID: fixture.childDraftID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        let context = try XCTUnwrap(session).modelContext
        context.delete(quarantine)
        try observe("receiptRestoreSave") { try context.save() }
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
            $0.mutationID == fixture.attempt.terminalBundleMutationID.rawValue
        })
        let originalReceiptData = row.receiptData
        row.receiptData = Data("{}".utf8)
        try observe("receiptCorruptionSaveAndRead") { try context.save() }
        XCTAssertThrowsError(try reopenedWriter.checkRunnerPhotoCommitEvidence(workspaceID: stored.checkpoint.workspaceID,
            draftID: stored.checkpoint.draftID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(row.receiptData, Data("{}".utf8))
        row.receiptData = originalReceiptData
        try observe("receiptRestoreSave") { try context.save() }
        let parentQuarantine = MutationQuarantineRow(workspaceID: stored.parentCheckpoint.workspaceID,
            mutationID: stored.parentPendingCheckpoint.mutationID, identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: stored.parentEvidence.pending.receipt.envelopeSHA256,
            conflictingIdentitySHA256: String(repeating: "e", count: 64), detectedAt: Date())
        context.insert(parentQuarantine)
        try observe("quarantineSaveAndRead") { try context.save() }
        XCTAssertThrowsError(try reopenedWriter.checkRunnerPhotoParentEvidence(
            workspaceID: stored.parentCheckpoint.workspaceID, parentDraftID: fixture.parentDraftID,
            childDraftID: fixture.childDraftID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try reopenedWriter.checkRunnerPhotoCurrentTargetEvidence(
            workspaceID: stored.parentCheckpoint.workspaceID, parentDraftID: fixture.parentDraftID,
            childDraftID: fixture.childDraftID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        context.delete(parentQuarantine)
        try observe("receiptRestoreSave") { try context.save() }
        let parentRow = try XCTUnwrap(context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
            $0.mutationID == stored.parentPendingCheckpoint.mutationID.rawValue
        })
        let originalParentReceiptData = parentRow.receiptData
        parentRow.receiptData = Data("{}".utf8)
        try observe("receiptCorruptionSaveAndRead") { try context.save() }
        XCTAssertThrowsError(try reopenedWriter.checkRunnerPhotoParentEvidence(
            workspaceID: stored.parentCheckpoint.workspaceID, parentDraftID: fixture.parentDraftID,
            childDraftID: fixture.childDraftID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(parentRow.receiptData, Data("{}".utf8))
        parentRow.receiptData = originalParentReceiptData
        try observe("receiptRestoreSave") { try context.save() }
        // The test owns this disposable store. Remove only the physical parent
        // and retain every original receipt, then restore the exact value using
        // the existing row constructor after the no-effect corruption check.
        let physicalParent = try XCTUnwrap(context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first {
            $0.draftID == fixture.parentDraftID
        })
        context.delete(physicalParent)
        try observe("physicalMissingSaveAndRead") { try context.save() }
        let missingPhysicalBefore = try observe("physicalMissingSaveAndRead") {
            try reopenedWriter.sourceMutationHistorySnapshot()
        }
        XCTAssertThrowsError(try reopenedWriter.checkRunnerPhotoParentEvidence(
            workspaceID: stored.parentCheckpoint.workspaceID, parentDraftID: fixture.parentDraftID,
            childDraftID: fixture.childDraftID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try observe("physicalMissingSaveAndRead") {
            try reopenedWriter.sourceMutationHistorySnapshot()
        }, missingPhysicalBefore)
        context.insert(try FieldDraftCheckpointRow(stored.parentCheckpoint))
        try observe("receiptRestoreSave") { try context.save() }
        XCTAssertEqual(try observe("reopenedReads") {
            try reopenedWriter.checkRunnerPhotoParentEvidence(
                workspaceID: stored.parentCheckpoint.workspaceID, parentDraftID: fixture.parentDraftID,
                childDraftID: fixture.childDraftID)
        }, stored.parentEvidence)
        XCTAssertEqual(try observe("reopenedReads") {
            try reopenedWriter.sourceMutationHistorySnapshot()
        }, reopenedBefore)
    }

    func testPhotoCommitReconstructionRejectsIncompletePhasesAndNonCommittingStates() throws {
        let fixture = try photoFixture()
        for phase in [CheckRunnerPhotoDurablePhaseV1.awaitingRawStage(fixture.intent),
                      .rawReady(fixture.raw), .pairReady(fixture.pair)] {
            let payload = try photoPayload(fixture, phase: phase)
            let checkpoint = try reconstructionCheckpoint(codecPhotoCheckpoint(payload), state: .committing)
            XCTAssertThrowsError(try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: checkpoint))
        }
        let payload = try photoPayload(fixture, phase: .preparedCommit(fixture.pair, fixture.attempt))
        let committing = try codecPhotoCheckpoint(payload)
        for state in FieldDraftStateV1.allCases where state != .committing {
            let checkpoint = try reconstructionCheckpoint(committing, state: state)
            try checkpoint.validate(authority: CheckRunnerDraftPurposeAuthorityV1())
            XCTAssertThrowsError(try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: checkpoint), state.rawValue)
        }
    }

    func testPhotoCommitReconstructionRejectsRehashedEnvelopeAndUnusableTerminalInputs() throws {
        let fixture = try photoFixture()
        let payload = try photoPayload(fixture, phase: .preparedCommit(fixture.pair, fixture.attempt))
        let checkpoint = try codecPhotoCheckpoint(payload)
        let candidates = try [
            codecRehashedCheckpoint(checkpoint, draftID: largeID(98_001)),
            codecRehashedCheckpoint(checkpoint, baseCanonicalRevision: checkpoint.baseCanonicalRevision + 1),
            codecRehashedCheckpoint(checkpoint, stageIDs: []),
            reconstructionCheckpoint(checkpoint, revision: UInt64.max),
            reconstructionCheckpoint(checkpoint, updatedAt: fixture.attempt.terminalCheckpointUpdatedAt.addingTimeInterval(0.001)),
            reconstructionCheckpoint(checkpoint, mutationID: fixture.attempt.terminalBundleMutationID),
        ]
        for candidate in candidates {
            try candidate.validate(authority: CheckRunnerDraftPurposeAuthorityV1())
            XCTAssertThrowsError(try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: candidate))
        }
        let lastUsable = try reconstructionCheckpoint(checkpoint, revision: UInt64.max - 1,
            updatedAt: fixture.attempt.terminalCheckpointUpdatedAt)
        XCTAssertEqual(try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: lastUsable).draftCommit.plan.draftRevision, UInt64.max - 1)
    }

    func testCommitReconstructionDerivesHashesFromTheEnclosingCheckpointWithoutRewritingPayload() throws {
        let parentPayload = try reconstructionParentPayload(seed: 99_000)
        let parentCheckpoint = try reconstructionParentCheckpoint(parentPayload)
        let parent = try reconstructParent(parentCheckpoint)
        let parentOther = try reconstructParent(reconstructionCheckpoint(parentCheckpoint, revision: parentCheckpoint.draftRevision + 1))
        let fixture = try photoFixture()
        let photoValue = try photoPayload(fixture, phase: .preparedCommit(fixture.pair, fixture.attempt))
        let photoCheckpoint = try codecPhotoCheckpoint(photoValue)
        let child = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: photoCheckpoint).draftCommit
        let childOther = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(
            from: reconstructionCheckpoint(photoCheckpoint, revision: photoCheckpoint.draftRevision + 1)).draftCommit
        for (value, other) in [(parent, parentOther), (child, childOther)] {
            XCTAssertEqual(value.checkpoint.payloadData, other.checkpoint.payloadData)
            XCTAssertEqual(value.plan.payloadSHA256, value.checkpoint.payloadSHA256)
            XCTAssertEqual(value.plan.baseCanonicalRevision, value.checkpoint.baseCanonicalRevision)
            XCTAssertEqual(value.plan.draftRevision, value.checkpoint.draftRevision)
            XCTAssertEqual(value.plan.planID, other.plan.planID)
            XCTAssertEqual(value.plan.mutationID, other.plan.mutationID)
            XCTAssertEqual(value.sagas.map(\.sagaID), other.sagas.map(\.sagaID))
            XCTAssertEqual(value.sagas.map(\.updatedAt), other.sagas.map(\.updatedAt))
            XCTAssertNotEqual(value.plan.planSHA256, other.plan.planSHA256)
            for (first, second) in zip(value.sagas, other.sagas) { XCTAssertNotEqual(first.sagaSHA256, second.sagaSHA256) }
        }
        XCTAssertNotEqual(parent.plan.baseCanonicalRevision, parent.plan.expectedTargetRevision)
        XCTAssertEqual(parent.plan.expectedTargetRevision, 7)
        XCTAssertEqual(try CheckRunnerItemDraftCodecV1.encode(parentPayload), parent.checkpoint.payloadData)
        XCTAssertEqual(try CheckRunnerPhotoDraftCodecV1.encode(photoValue), child.checkpoint.payloadData)
    }

    private func reconstructionParentPayload(recheck: Bool = false,
        selection: CheckOutcomeSelection? = nil, seed: Int) throws -> CheckRunnerItemDraftPayloadV1 {
        let selected = selection ?? (recheck ? .resolved(note: nil) : .noVisibleIssue)
        let fixture = try parentFixture(recheck: recheck, includesTimeZone: recheck)
        let count: Int
        if case .couldNotVerify = selected { count = 0 } else { count = 2 }
        let field = try preparedField(fixture: fixture, outcome: editableOutcome(selected), mediaCount: count, seed: seed + 1_000)
        let attempt = try finalizationAttempt(fixture: fixture, field: field, selection: selected, seed: seed)
        return try .init(prepared: fixture.source, field: field, attempt: attempt)
    }

    private func reconstructionParentCheckpoint(_ payload: CheckRunnerItemDraftPayloadV1) throws -> FieldDraftCheckpointV1 {
        let attempt = try XCTUnwrap(payload.finalizationAttempt)
        return try reconstructionCheckpoint(codecParentCheckpoint(payload), state: .committing, revision: 4,
            updatedAt: attempt.preparedSagaUpdatedAt)
    }

    private func reconstructParent(_ checkpoint: FieldDraftCheckpointV1) throws -> CheckRunnerDraftCommitReconstructionV1 {
        try CheckRunnerItemDraftCodecV1.reconstructFinalizationCommit(from: checkpoint,
            signPack: pack, activeLifecycleProfile: { try self.profile })
    }

    private func reconstructionCheckpoint(_ value: FieldDraftCheckpointV1, state: FieldDraftStateV1? = nil,
        revision: UInt64? = nil, updatedAt: Date? = nil, mutationID: MutationIDV1? = nil) throws -> FieldDraftCheckpointV1 {
        let state = state ?? value.state
        let terminal = state == .committed || state == .discarded
        return try .init(draftID: value.draftID, workspaceID: value.workspaceID, scope: value.scope,
            purpose: value.purpose, codec: value.codec, baseCanonicalRevision: value.baseCanonicalRevision,
            draftRevision: revision ?? value.draftRevision, payloadData: value.payloadData,
            stageIDs: value.stageIDs, resumeAnchor: value.resumeAnchor, state: state,
            lastDurableMutationID: terminal ? value.mutationID : value.lastDurableMutationID,
            lastReceiptSHA256: terminal ? String(repeating: "7", count: 64) : value.lastReceiptSHA256,
            updatedAt: updatedAt ?? value.updatedAt, mutationID: mutationID ?? value.mutationID)
    }

    private func codecParentCheckpoint(_ payload: CheckRunnerItemDraftPayloadV1) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: largeID(80_000), workspaceID: payload.source.roundAtEntry.workspaceID,
            scope: CheckRunnerItemDraftCodecV1.scope(source: payload.source), purpose: .inspectionReview,
            codec: CheckRunnerItemDraftCodecV1.release(), baseCanonicalRevision: payload.source.roundAtEntry.revision,
            draftRevision: 1, payloadData: CheckRunnerItemDraftCodecV1.encode(payload), stageIDs: [],
            resumeAnchor: CheckRunnerItemDraftCodecV1.resumeAnchor(payload: payload), state: .active,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_250), mutationID: .init(rawValue: largeID(80_001)))
    }

    private func codecPhotoCheckpoint(_ payload: CheckRunnerPhotoDraftPayloadV1) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: payload.childDraftID, workspaceID: payload.workspaceID,
            scope: CheckRunnerPhotoDraftCodecV1.scope(payload: payload), purpose: .inspectionReview,
            codec: CheckRunnerPhotoDraftCodecV1.release(), baseCanonicalRevision: payload.sourceBinding.roundAtEntry.revision,
            draftRevision: 1, payloadData: CheckRunnerPhotoDraftCodecV1.encode(payload), stageIDs: payload.phase.declaredStageIDs,
            resumeAnchor: CheckRunnerPhotoDraftCodecV1.resumeAnchor(payload: payload),
            state: payload.phase.attempt == nil ? .active : .committing,
            updatedAt: payload.phase.attempt?.preparedUpdatedAt ?? payload.phase.intent.stageCreatedAt,
            mutationID: .init(rawValue: largeID(80_002)))
    }

    private func codecRehashedCheckpoint(_ value: FieldDraftCheckpointV1, draftID: UUID? = nil,
        workspaceID: WorkspaceID? = nil, scope: DraftScopeKeyV1? = nil, codec: DraftPayloadCodecReleaseV1? = nil,
        baseCanonicalRevision: UInt64? = nil, stageIDs: [UUID]? = nil,
        resumeAnchor: DraftResumeAnchorV1? = nil, state: FieldDraftStateV1? = nil) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: draftID ?? value.draftID, workspaceID: workspaceID ?? value.workspaceID,
            scope: scope ?? value.scope, purpose: value.purpose, codec: codec ?? value.codec,
            baseCanonicalRevision: baseCanonicalRevision ?? value.baseCanonicalRevision,
            draftRevision: value.draftRevision, payloadData: value.payloadData, stageIDs: stageIDs ?? value.stageIDs,
            resumeAnchor: resumeAnchor ?? value.resumeAnchor, state: state ?? value.state,
            lastDurableMutationID: value.lastDurableMutationID, lastReceiptSHA256: value.lastReceiptSHA256,
            updatedAt: value.updatedAt, mutationID: value.mutationID)
    }

    private struct PhotoFixture {
        let parentFixture: ParentFixture
        let parent: CheckRunnerItemDraftPayloadV1
        let parentDraftID: UUID
        let childDraftID: UUID
        let step: WorkflowDraftStep
        let origin: OriginalContentOriginV1
        let intent: CheckRunnerPhotoRawStageIntentV1
        let raw: CheckRunnerPhotoRawReadyV1
        let pair: CheckRunnerPhotoPairReadyV1
        let attempt: CheckRunnerPhotoCommitAttemptV1
    }

    private func photoFixture(recheck: Bool = false, step: WorkflowDraftStep = .wide,
                              origin: OriginalContentOriginV1 = .humanCapture) throws -> PhotoFixture {
        let parent = try parentFixture(recheck: recheck, includesTimeZone: recheck)
        let seed = 50_000 + (recheck ? 100 : 0) + (step == .close ? 20 : 0) + (origin == .localImport ? 40 : 0)
        let parentID = largeID(seed), childID = largeID(seed + 1), stageID = largeID(seed + 2)
        let evidenceID = largeID(seed + 3), workspaceID = parent.source.roundAtEntry.workspaceID
        let slot = pendingSlot(id: childID, step: step)
        let field = try CheckRunnerItemFieldStateV1(preflight: .init(),
            begin: .bound(attempt: parent.attempt, workflowReceiptReference: parent.workflowReference,
                timeZoneReceiptReference: parent.timeZoneReference), outcome: .init(),
            wideContext: step == .wide ? slot : nil, closeDetail: step == .close ? slot : nil, semanticAnchor: .review)
        let parentPayload = try CheckRunnerItemDraftPayloadV1(editing: parent.source, field: field)
        let intent = try CheckRunnerPhotoRawStageIntentV1(stageID: stageID,
            stageMutationID: .init(rawValue: largeID(seed + 4)), stageCreatedAt: Date(timeIntervalSince1970: 1_800_000_201),
            expectedSourceByteCount: 512, provenanceID: "photo-provenance-\(seed)", evidenceID: evidenceID,
            evidenceCreatedAt: Date(timeIntervalSince1970: 1_800_000_200))
        let inspection = try CheckRunnerPhotoSourceInspectionV1(
            facts: .init(sourceTypeIdentifier: "public.jpeg", pixelWidth: 20, pixelHeight: 10, byteCount: 512),
            sourceSHA256: .init(algorithm: .sha256, hexadecimalValue: String(repeating: "b", count: 64)),
            workspaceID: workspaceID, provenanceID: intent.provenanceID)
        let ready = try AttachmentStagingItemV1(stageID: stageID, draftID: childID, workspaceID: workspaceID,
            attachmentKind: .photo, scratchLeaseID: stageID, expectedByteCount: 512, actualByteCount: 512,
            contentDigest: inspection.sourceSHA256, retryClass: .none, state: .readyLocal,
            protectionState: .available, revision: 1, mutationID: intent.stageMutationID)
        let provenance = try ContentOriginalProvenanceV1(provenanceID: intent.provenanceID,
            workspaceID: workspaceID.rawValue.uuidString.lowercased(), contentID: inspection.rawContentID,
            contentDigest: inspection.sourceSHA256, origin: origin,
            recordedAt: CheckRunnerPhotoRawReadyV1.formatOriginalRecordedAt(intent.stageCreatedAt))
        let raw = try CheckRunnerPhotoRawReadyV1(intent: intent, inspection: inspection, readyItem: ready,
            stagePublicationMutationID: intent.stageMutationID, originalProvenance: provenance)
        let directory = "evidence/\(evidenceID.uuidString.lowercased())"
        let normalized = try CheckRunnerPhotoNormalizedPairV1(evidenceID: evidenceID,
            originalRelativePath: "\(directory)/original.jpg", originalByteCount: 128,
            originalSHA256: String(repeating: "c", count: 64), originalPixelWidth: 20, originalPixelHeight: 10,
            thumbnailRelativePath: "\(directory)/thumbnail.jpg", thumbnailByteCount: 64,
            thumbnailSHA256: String(repeating: "e", count: 64), thumbnailPixelWidth: 10, thumbnailPixelHeight: 5,
            sourceBinding: .init(contentID: inspection.rawContentID, digest: inspection.sourceSHA256),
            sanitizedDerivative: CheckRunnerPhotoSourceMetadataProfileV1.sanitizedDerivative(),
            thumbnailDerivative: CheckRunnerPhotoSourceMetadataProfileV1.thumbnailDerivative(pixelWidth: 10, pixelHeight: 5))
        let pair = try CheckRunnerPhotoPairReadyV1(raw: raw, normalizedPair: normalized,
            pairPublicationMarkerSHA256: CheckRunnerPhotoPairReadyV1.markerSHA256(childDraftID: childID,
                parentDraftID: parentID, raw: raw, normalizedPair: normalized))
        let attempt = try CheckRunnerPhotoCommitAttemptV1(planID: largeID(seed + 10), expectedWorkflowRecordRevision: 1,
            targetMutationID: .init(rawValue: evidenceID), outputKeys: [
                WorkspaceEntityIdentityV1(kind: .workflowRecord, id: parent.attempt.recordCommand.recordID).stableKey,
                WorkspaceEntityIdentityV1(kind: .evidenceFile, id: evidenceID).stableKey].sorted(),
            reservationMutationID: .init(rawValue: largeID(seed + 11)), reservationReviewAfter: Date(timeIntervalSince1970: 1_800_000_300),
            preparedSagaID: largeID(seed + 12), preparedSagaMutationID: .init(rawValue: largeID(seed + 13)),
            preparedUpdatedAt: Date(timeIntervalSince1970: 1_800_000_203),
            contentPromotedSagaID: largeID(seed + 14), contentPromotedSagaMutationID: .init(rawValue: largeID(seed + 15)),
            contentPromotedUpdatedAt: Date(timeIntervalSince1970: 1_800_000_205),
            targetCommittedSagaID: largeID(seed + 16), targetCommittedSagaMutationID: .init(rawValue: largeID(seed + 17)),
            targetCommittedUpdatedAt: Date(timeIntervalSince1970: 1_800_000_206),
            draftRetirePendingSagaID: largeID(seed + 18), draftRetirePendingSagaMutationID: .init(rawValue: largeID(seed + 19)),
            draftRetirePendingUpdatedAt: Date(timeIntervalSince1970: 1_800_000_207),
            draftRetiredSagaID: largeID(seed + 20), draftRetiredUpdatedAt: Date(timeIntervalSince1970: 1_800_000_208),
            commitReceiptID: largeID(seed + 21), terminalBundleMutationID: .init(rawValue: largeID(seed + 22)),
            terminalCheckpointUpdatedAt: Date(timeIntervalSince1970: 1_800_000_209), promotionAt: Date(timeIntervalSince1970: 1_800_000_204))
        return PhotoFixture(parentFixture: parent, parent: parentPayload, parentDraftID: parentID,
            childDraftID: childID, step: step, origin: origin, intent: intent, raw: raw, pair: pair, attempt: attempt)
    }

    private func photoPayload(_ fixture: PhotoFixture, phase: CheckRunnerPhotoDurablePhaseV1) throws -> CheckRunnerPhotoDraftPayloadV1 {
        try CheckRunnerPhotoDraftPayloadV1(workspaceID: fixture.parent.source.roundAtEntry.workspaceID,
            childDraftID: fixture.childDraftID, parentDraftID: fixture.parentDraftID,
            recordID: fixture.parentFixture.attempt.recordCommand.recordID, assetID: fixture.parent.source.assetID,
            sourceBinding: fixture.parent.source, workflowStage: fixture.parent.source.requestedEntry.stage,
            captureStep: fixture.step, purposeKey: fixture.step == .wide ? "wide_context" : "close_detail",
            origin: fixture.origin, phase: phase)
    }

    private struct StoredPhotoCommit {
        let history: [FieldDraftCommittedEvidenceV1]
        let checkpoint: FieldDraftCheckpointV1
        let sagas: [DraftCommitSagaV1]
        let reservation: DraftContentReservationV1
        let stage: AttachmentStagingItemV1
        let receipt: DraftCommitReceiptV1
        let target: CheckRunnerPhotoCommittedEvidenceV1
        let evidence: CheckRunnerPhotoCommitEvidenceV1
        let parentHistory: [FieldDraftCommittedEvidenceV1]
        let parentPendingCheckpoint: FieldDraftCheckpointV1
        let parentCheckpoint: FieldDraftCheckpointV1
        let workflowEvidence: CheckRunnerBeginCommittedEvidenceV1
        let timeZoneEvidence: CheckRunnerBeginCommittedEvidenceV1
        let parentEvidence: CheckRunnerPhotoParentEvidenceV1
        let missingSelectedChildID: UUID
        let partialParentDraftID: UUID
    }

    @MainActor
    private func persistPhotoCommit(_ fixture: PhotoFixture,
                                    coordinator: StoreSessionCoordinator) throws -> StoredPhotoCommit {
        let writer = coordinator.workspaceWriter
        let workspaceID = fixture.parent.source.roundAtEntry.workspaceID
        let firstMutation = try MutationIDV1(rawValue: largeID(71_000))
        let selection = fixture.parent.source.itemAtEntry.selection
        _ = try writer.execute(.createFirstSign(.init(siteID: selection.siteID,
            newSite: .init(id: selection.siteID, label: "Photo evidence site", address: "10 Main",
                timeZoneID: nil),
            assetID: fixture.parent.source.assetID, assetLabel: selection.labelAtSelection,
            packID: fixture.parent.source.legacyPackageIdentity.packageID,
            packSchemaVersion: fixture.parent.source.legacyPackageIdentity.schemaVersion,
            packContentVersion: fixture.parent.source.legacyPackageIdentity.contentVersion,
            createdAt: fixture.parentFixture.attempt.recordCommand.startedAt.addingTimeInterval(-1),
            initialPlacementMutationID: firstMutation, initialPlacementEventID: largeID(71_010),
            initialPhysicalEpisodeID: try .init(rawValue: largeID(71_011)))), mutationID: firstMutation)
        let current = try writer.currentRevision()
        let known = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        let siteIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: selection.siteID)
        let recordTargets = try [
            WorkspaceEntityIdentityV1(kind: .workflowRecord,
                id: fixture.parentFixture.attempt.recordCommand.recordID),
            WorkspaceEntityIdentityV1(kind: .asset, id: fixture.parentFixture.attempt.recordCommand.assetID),
        ].sorted { $0.stableKey < $1.stableKey }
        let expectedRecordRevisions = recordTargets.map {
            WorkspaceEntityRevisionV1(identity: $0, revision: known[$0, default: 0])
        }
        let zoneMutationID = try MutationIDV1(rawValue: largeID(72_000))
        let zoneCommand = SiteTimeZoneMutationV1(siteID: selection.siteID,
            timeZoneID: fixture.parentFixture.attempt.resolvedSiteTimeZoneID,
            confirmedAt: fixture.parentFixture.attempt.recordCommand.startedAt)
        let timeZoneAttempt = try CheckRunnerBeginTimeZoneAttemptV1(command: zoneCommand,
            mutationID: zoneMutationID, expectedSiteRevision: known[siteIdentity, default: 0],
            committedAt: clock.millisecondValue)
        let actualAttempt = try CheckRunnerFrozenBeginAttemptV1(source: fixture.parent.source,
            sourceWorkspaceID: workspaceID, recordCommand: fixture.parentFixture.attempt.recordCommand,
            recordMutationID: fixture.parentFixture.attempt.recordMutationID,
            recordExpectedEntityRevisions: expectedRecordRevisions,
            recordCommittedAt: clock.millisecondValue, timeZone: timeZoneAttempt,
            siteID: fixture.parentFixture.attempt.siteID,
            resolvedSiteTimeZoneID: fixture.parentFixture.attempt.resolvedSiteTimeZoneID)
        let adapter = try writer.makeFieldDraftLifecycleAdapter(modelContext: coordinator.modelContext)

        let parentNotBegun = try parentCheckpoint(fixture,
            payload: parentPayload(fixture, begin: .notBegun, slot: nil), revision: 1,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_190), mutationID: .init(rawValue: largeID(72_001)))
        _ = try adapter.compareAndSwap(checkpoint: parentNotBegun, expectedDraftRevision: 0,
            expectedBaseRevision: parentNotBegun.baseCanonicalRevision)
        let parentPrepared = try parentCheckpoint(fixture,
            payload: parentPayload(fixture, begin: .prepared(attempt: actualAttempt), slot: nil), revision: 2,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_195), mutationID: .init(rawValue: largeID(72_002)))
        _ = try adapter.compareAndSwap(checkpoint: parentPrepared, expectedDraftRevision: 1,
            expectedBaseRevision: parentPrepared.baseCanonicalRevision)
        _ = try writer.execute(.updateSiteTimeZone(zoneCommand), mutationID: zoneMutationID)
        let timeZoneEvidence = try XCTUnwrap(writer.checkRunnerBeginEvidence(workspaceID: workspaceID,
            mutationID: zoneMutationID))
        XCTAssertEqual(timeZoneEvidence.envelope.expectedRevision.entityRevisions,
            [WorkspaceEntityRevisionV1(identity: siteIdentity, revision: timeZoneAttempt.expectedSiteRevision)])
        XCTAssertEqual(timeZoneEvidence.receipt.committedAt, actualAttempt.timeZone?.committedAt)
        _ = try writer.execute(.createCheckDraft(fixture.parentFixture.attempt.recordCommand),
            mutationID: fixture.parentFixture.attempt.recordMutationID)
        let workflowEvidence = try XCTUnwrap(writer.checkRunnerBeginEvidence(workspaceID: workspaceID,
            mutationID: fixture.parentFixture.attempt.recordMutationID))
        XCTAssertEqual(workflowEvidence.envelope.expectedRevision.entityRevisions, expectedRecordRevisions)
        XCTAssertEqual(workflowEvidence.receipt.committedAt, actualAttempt.recordCommittedAt)
        let workflowReference = try CheckRunnerBeginReceiptReferenceV1(evidence: workflowEvidence)
        let timeZoneReference = try CheckRunnerBeginReceiptReferenceV1(evidence: timeZoneEvidence)
        let parentBound = try parentCheckpoint(fixture,
            payload: parentPayload(fixture, begin: .bound(attempt: actualAttempt,
                workflowReceiptReference: workflowReference, timeZoneReceiptReference: timeZoneReference), slot: nil), revision: 3,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_198), mutationID: .init(rawValue: largeID(72_003)))
        _ = try adapter.compareAndSwap(checkpoint: parentBound, expectedDraftRevision: 2,
            expectedBaseRevision: parentBound.baseCanonicalRevision)
        let missingSelectedChildID = largeID(72_100)
        let missingSelectedSlot = pendingSlot(id: missingSelectedChildID,
            step: fixture.step == .wide ? .close : .wide)
        let parentPending = try parentCheckpoint(fixture,
            payload: parentPayload(fixture, begin: .bound(attempt: actualAttempt,
                workflowReceiptReference: workflowReference, timeZoneReceiptReference: timeZoneReference),
                slot: pendingSlot(id: fixture.childDraftID, step: fixture.step),
                otherSlot: missingSelectedSlot,
                outcome: .init(selection: nil, couldNotVerifyNote: "raw pending note", recheckNote: "raw recheck note")),
            revision: 4, updatedAt: Date(timeIntervalSince1970: 1_800_000_199),
            mutationID: .init(rawValue: largeID(72_004)))
        _ = try adapter.compareAndSwap(checkpoint: parentPending, expectedDraftRevision: 3,
            expectedBaseRevision: parentPending.baseCanonicalRevision)

        let awaiting = try photoCheckpoint(fixture, phase: .awaitingRawStage(fixture.intent), revision: 1,
            state: .active, updatedAt: fixture.intent.stageCreatedAt, mutationID: .init(rawValue: largeID(71_001)))
        _ = try adapter.compareAndSwap(checkpoint: awaiting, expectedDraftRevision: 0,
            expectedBaseRevision: awaiting.baseCanonicalRevision)
        let raw = try photoCheckpoint(fixture, phase: .rawReady(fixture.raw), revision: 2, state: .active,
            updatedAt: fixture.intent.stageCreatedAt, mutationID: fixture.raw.stagePublicationMutationID)
        _ = try adapter.publish(readyStage: .init(expectedCheckpoint: awaiting,
            readyItem: fixture.raw.readyItem, successorCheckpoint: raw))
        let pair = try photoCheckpoint(fixture, phase: .pairReady(fixture.pair), revision: 3, state: .active,
            updatedAt: fixture.intent.stageCreatedAt, mutationID: .init(rawValue: largeID(71_003)))
        _ = try adapter.compareAndSwap(checkpoint: pair, expectedDraftRevision: 2,
            expectedBaseRevision: pair.baseCanonicalRevision)
        let committing = try photoCheckpoint(fixture, phase: .preparedCommit(fixture.pair, fixture.attempt),
            revision: 4, state: .committing, updatedAt: fixture.attempt.preparedUpdatedAt,
            mutationID: .init(rawValue: largeID(71_004)))
        _ = try adapter.compareAndSwap(checkpoint: committing, expectedDraftRevision: 3,
            expectedBaseRevision: committing.baseCanonicalRevision)

        let reconstruction = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: committing)
        let commit = reconstruction.draftCommit
        _ = try adapter.append(saga: commit.sagas[0], expectedRevision: 0)
        let reference = try ContentReferenceV1(workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: fixture.raw.inspection.rawContentID, byteLength: fixture.raw.inspection.sourceByteCount,
            mediaType: fixture.raw.inspection.sourceMediaType,
            digests: .init([fixture.raw.inspection.sourceSHA256]), byteRole: .immutableOriginal,
            createdAt: CheckRunnerPhotoRawReadyV1.formatOriginalRecordedAt(fixture.attempt.promotionAt))
        let stage = try AttachmentStagingItemV1(stageID: fixture.raw.readyItem.stageID,
            draftID: fixture.raw.readyItem.draftID, workspaceID: fixture.raw.readyItem.workspaceID,
            attachmentKind: fixture.raw.readyItem.attachmentKind,
            scratchLeaseID: fixture.raw.readyItem.scratchLeaseID,
            expectedByteCount: fixture.raw.readyItem.expectedByteCount,
            actualByteCount: fixture.raw.readyItem.actualByteCount,
            contentDigest: fixture.raw.readyItem.contentDigest, contentReference: reference,
            processingJobID: fixture.raw.readyItem.processingJobID, retryClass: fixture.raw.readyItem.retryClass,
            state: .committed, protectionState: fixture.raw.readyItem.protectionState,
            revision: fixture.raw.readyItem.revision + 1,
            mutationID: .init(rawValue: DraftAttachmentStagingAdapterV1.deterministicUUID(
                "stage-mutation\u{1f}\(fixture.intent.stageID.uuidString.lowercased())\u{1f}2\u{1f}COMMITTED\u{1f}\(fixture.raw.inspection.sourceSHA256.hexadecimalValue)")))
        _ = try adapter.append(stagingItem: stage, expectedRevision: fixture.raw.readyItem.revision)
        let locator = try ContentLocatorV1(locatorID: "photo-child-raw-v1",
            workspaceID: workspaceID.rawValue.uuidString.lowercased(), contentID: fixture.raw.inspection.rawContentID,
            locatorRevision: 0, contentDigest: fixture.raw.inspection.sourceSHA256,
            expectedByteLength: fixture.raw.inspection.sourceByteCount)
        let reservation = try DraftContentReservationV1(reservationID:
            DraftAttachmentStagingAdapterV1.deterministicUUID(
                "reservation\u{1f}\(commit.plan.planSHA256)\u{1f}\(fixture.intent.stageID.uuidString.lowercased())"),
            workspaceID: workspaceID, draftID: fixture.childDraftID, stageID: fixture.intent.stageID,
            commitPlanSHA256: commit.plan.planSHA256, mutationID: fixture.attempt.reservationMutationID,
            contentDigest: fixture.raw.inspection.sourceSHA256, locator: locator,
            createdAt: fixture.attempt.promotionAt, reviewAfter: fixture.attempt.reservationReviewAfter,
            reconciliationState: .reserved, revision: 1)
        _ = try adapter.append(reservation: reservation, expectedRevision: 0)
        _ = try adapter.append(saga: commit.sagas[1], expectedRevision: 1)
        _ = try writer.execute(.acceptCheckEvidence(reconstruction.targetCommand),
            mutationID: commit.plan.mutationID)
        let target = try XCTUnwrap(writer.checkRunnerPhotoEvidence(workspaceID: workspaceID,
            mutationID: commit.plan.mutationID))
        _ = try adapter.append(saga: commit.sagas[2], expectedRevision: 2)
        _ = try adapter.append(saga: commit.sagas[3], expectedRevision: 3)
        let receipt = try DraftCommitReceiptV1(receiptID: commit.commitReceiptID, workspaceID: workspaceID,
            draftID: fixture.childDraftID, sagaID: commit.retired.sagaID,
            commitPlanSHA256: commit.plan.planSHA256, sagaEventSHA256Chain: commit.sagas.map(\.sagaSHA256),
            targetMutationID: commit.plan.mutationID, targetReceiptSHA256: target.receipt.resultSHA256,
            consumedStageToContentID: [fixture.intent.stageID.uuidString: locator.contentID],
            committedAt: target.receipt.committedAt, mutationID: commit.rowMutationIDs.terminalBundleMutationID)
        let terminal = try FieldDraftCheckpointV1(draftID: committing.draftID, workspaceID: workspaceID,
            scope: committing.scope, purpose: committing.purpose, codec: committing.codec,
            baseCanonicalRevision: committing.baseCanonicalRevision, draftRevision: 5,
            payloadData: committing.payloadData, stageIDs: committing.stageIDs, resumeAnchor: committing.resumeAnchor,
            state: .committed, lastDurableMutationID: commit.rowMutationIDs.terminalBundleMutationID,
            lastReceiptSHA256: receipt.receiptSHA256, updatedAt: commit.terminalCheckpointUpdatedAt,
            mutationID: commit.rowMutationIDs.terminalBundleMutationID)
        _ = try adapter.apply(commitTerminalBundle: .init(retiredSaga: commit.retired,
            committedCheckpoint: terminal, receipt: receipt), expectedDraftRevision: 4, expectedSagaRevision: 4)
        let committedSlot = CheckRunnerPhotoSlotV1.committed(childDraftID: fixture.childDraftID,
            captureStep: fixture.step, purposeKey: fixture.step == .wide ? "wide_context" : "close_detail",
            committedChildDraftRevision: terminal.draftRevision,
            committedChildCheckpointSHA256: terminal.checkpointSHA256,
            childCommitReceiptID: receipt.receiptID, childCommitReceiptSHA256: receipt.receiptSHA256,
            evidenceID: target.command.evidenceID, targetMutationID: target.receipt.mutationID,
            targetReceiptSHA256: target.receipt.resultSHA256)
        let parentCommitted = try parentCheckpoint(fixture,
            payload: parentPayload(fixture, begin: .bound(attempt: actualAttempt,
                workflowReceiptReference: workflowReference, timeZoneReceiptReference: timeZoneReference),
                slot: committedSlot,
                otherSlot: missingSelectedSlot,
                outcome: .init(selection: nil, couldNotVerifyNote: "raw committed note", recheckNote: "raw recheck note")),
            revision: 5, updatedAt: fixture.attempt.terminalCheckpointUpdatedAt,
            mutationID: .init(rawValue: largeID(72_005)))
        _ = try adapter.compareAndSwap(checkpoint: parentCommitted, expectedDraftRevision: 4,
            expectedBaseRevision: parentCommitted.baseCanonicalRevision)
        let parentRetry = try parentCheckpoint(fixture,
            payload: parentPayload(fixture, begin: .bound(attempt: actualAttempt,
                workflowReceiptReference: workflowReference, timeZoneReceiptReference: timeZoneReference), slot: committedSlot,
                otherSlot: missingSelectedSlot,
                outcome: .init(selection: nil, couldNotVerifyNote: "raw retry note", recheckNote: "raw recheck note")),
            revision: 6, updatedAt: fixture.attempt.terminalCheckpointUpdatedAt,
            mutationID: .init(rawValue: largeID(72_006)))
        _ = try adapter.compareAndSwap(checkpoint: parentRetry, expectedDraftRevision: 5,
            expectedBaseRevision: parentRetry.baseCanonicalRevision)
        let partialParentDraftID = largeID(72_200)
        let partialParent = try parentCheckpoint(fixture,
            payload: parentPayload(fixture, begin: .notBegun, slot: nil), revision: 1,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_210), mutationID: .init(rawValue: largeID(72_201)),
            draftID: partialParentDraftID)
        _ = try adapter.compareAndSwap(checkpoint: partialParent, expectedDraftRevision: 0,
            expectedBaseRevision: partialParent.baseCanonicalRevision)
        let mutationIDs = [awaiting.mutationID, raw.mutationID, pair.mutationID, committing.mutationID,
            commit.sagas[0].mutationID, stage.mutationID, reservation.mutationID, commit.sagas[1].mutationID,
            commit.sagas[2].mutationID, commit.sagas[3].mutationID, commit.rowMutationIDs.terminalBundleMutationID]
        let history = try mutationIDs.map { try XCTUnwrap(writer.fieldDraftEvidence(mutationID: $0)) }
        let evidence = try XCTUnwrap(writer.checkRunnerPhotoCommitEvidence(workspaceID: workspaceID,
            draftID: fixture.childDraftID))
        let parentMutationIDs = [parentNotBegun.mutationID, parentPrepared.mutationID, parentBound.mutationID,
            parentPending.mutationID, parentCommitted.mutationID, parentRetry.mutationID]
        let parentHistory = try parentMutationIDs.map { try XCTUnwrap(writer.fieldDraftEvidence(mutationID: $0)) }
        let parentEvidence = try XCTUnwrap(writer.checkRunnerPhotoParentEvidence(workspaceID: workspaceID,
            parentDraftID: fixture.parentDraftID, childDraftID: fixture.childDraftID))
        return StoredPhotoCommit(history: history, checkpoint: terminal, sagas: commit.sagas,
            reservation: reservation, stage: stage, receipt: receipt, target: target, evidence: evidence,
            parentHistory: parentHistory, parentPendingCheckpoint: parentPending, parentCheckpoint: parentRetry,
            workflowEvidence: workflowEvidence, timeZoneEvidence: timeZoneEvidence, parentEvidence: parentEvidence,
            missingSelectedChildID: missingSelectedChildID, partialParentDraftID: partialParentDraftID)
    }

    private func parentPayload(_ fixture: PhotoFixture, begin: CheckRunnerBeginStateV1,
                               slot: CheckRunnerPhotoSlotV1?,
                               otherSlot: CheckRunnerPhotoSlotV1? = nil,
                               outcome: CheckRunnerEditableOutcomeV1 = .init()) throws -> CheckRunnerItemDraftPayloadV1 {
        let original = fixture.parent.field
        let field = try CheckRunnerItemFieldStateV1(preflight: original.preflight, begin: begin, outcome: outcome,
            wideContext: fixture.step == .wide ? slot : otherSlot,
            closeDetail: fixture.step == .close ? slot : otherSlot, semanticAnchor: original.semanticAnchor)
        return try .init(editing: fixture.parent.source, field: field)
    }

    private func parentCheckpoint(_ fixture: PhotoFixture, payload: CheckRunnerItemDraftPayloadV1,
                                  revision: UInt64, updatedAt: Date,
                                  mutationID: MutationIDV1, draftID: UUID? = nil) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: draftID ?? fixture.parentDraftID, workspaceID: payload.source.roundAtEntry.workspaceID,
            scope: CheckRunnerItemDraftCodecV1.scope(source: payload.source), purpose: .inspectionReview,
            codec: CheckRunnerItemDraftCodecV1.release(), baseCanonicalRevision: payload.source.roundAtEntry.revision,
            draftRevision: revision, payloadData: CheckRunnerItemDraftCodecV1.encode(payload), stageIDs: [],
            resumeAnchor: CheckRunnerItemDraftCodecV1.resumeAnchor(payload: payload), state: .active,
            updatedAt: updatedAt, mutationID: mutationID)
    }

    private func photoCheckpoint(_ fixture: PhotoFixture, phase: CheckRunnerPhotoDurablePhaseV1,
                                 revision: UInt64, state: FieldDraftStateV1, updatedAt: Date,
                                 mutationID: MutationIDV1) throws -> FieldDraftCheckpointV1 {
        let payload = try photoPayload(fixture, phase: phase)
        return try FieldDraftCheckpointV1(draftID: fixture.childDraftID,
            workspaceID: fixture.parent.source.roundAtEntry.workspaceID,
            scope: CheckRunnerPhotoDraftCodecV1.scope(payload: payload), purpose: .inspectionReview,
            codec: CheckRunnerPhotoDraftCodecV1.release(),
            baseCanonicalRevision: fixture.parent.source.roundAtEntry.revision, draftRevision: revision,
            payloadData: CheckRunnerPhotoDraftCodecV1.encode(payload), stageIDs: phase.declaredStageIDs,
            resumeAnchor: CheckRunnerPhotoDraftCodecV1.resumeAnchor(payload: payload), state: state,
            updatedAt: updatedAt, mutationID: mutationID)
    }

    private func photoParent(_ fixture: PhotoFixture, slot: CheckRunnerPhotoSlotV1?) throws -> CheckRunnerItemDraftPayloadV1 {
        let original = fixture.parent.field
        return try .init(editing: fixture.parent.source, field: .init(preflight: original.preflight,
            begin: original.begin, outcome: original.outcome,
            wideContext: fixture.step == .wide ? slot : nil, closeDetail: fixture.step == .close ? slot : nil,
            semanticAnchor: original.semanticAnchor))
    }

    private struct ParentFixture {
        let source: CheckRunnerRoundItemSourceV1
        let attempt: CheckRunnerFrozenBeginAttemptV1
        let workflowReference: CheckRunnerBeginReceiptReferenceV1
        let timeZoneReference: CheckRunnerBeginReceiptReferenceV1?
        let workflowEvidence: CheckRunnerBeginCommittedEvidenceV1
    }

    private func parentFixture(recheck: Bool, includesTimeZone: Bool) throws -> ParentFixture {
        let workspaceID = WorkspaceID(rawValue: largeID(recheck ? 100 : 10))
        let assetID = largeID(recheck ? 101 : 11)
        let siteID = largeID(recheck ? 102 : 12)
        let issueID = recheck ? largeID(103) : nil
        let parentRecordID = recheck ? largeID(104) : nil
        let recordID = largeID(recheck ? 105 : 15)
        let source = try parentSource(workspaceID: workspaceID, assetID: assetID,
            siteID: siteID, issueID: issueID, seed: recheck ? 400 : 300)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let committedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let frozen = try TimeContextRule.freeze(observedAtUTC: startedAt,
            confirmedTimeZoneID: "America/New_York")
        let command = CheckDraftMutationV1(recordID: recordID, assetID: assetID,
            issueID: issueID, parentRecordID: parentRecordID,
            stage: recheck ? WorkflowStage.recheck.rawValue : WorkflowStage.check.rawValue,
            draftStepKey: WorkflowDraftStep.wide.rawValue, startedAt: startedAt,
            observedAtUTC: frozen.observedAtUTC, timeZoneID: frozen.timeZoneID,
            utcOffsetMinutes: frozen.utcOffsetMinutes, localDate: frozen.localDate,
            localTime: frozen.localTime, afterDarkAcknowledgementKey: "after_dark",
            afterDarkAcknowledgementCopy: "After-dark conditions acknowledged",
            afterDarkAcknowledgementVersion: "1", afterDarkAcknowledgementAccepted: true,
            safePositionAcknowledgementKey: "safe_authorized_position",
            safePositionAcknowledgementCopy: "Safe position acknowledged",
            safePositionAcknowledgementVersion: "1", safePositionAcknowledgementAccepted: true,
            packID: ShippingIlluminatedSignAdapterV1.packageID, packSchemaVersion: 1,
            packContentVersion: 1, pdfTemplateID: "illuminated-sign-report", pdfTemplateVersion: 1)
        var expected = try [
            WorkspaceEntityRevisionV1(identity: .init(kind: .workflowRecord, id: recordID), revision: 0),
            WorkspaceEntityRevisionV1(identity: .init(kind: .asset, id: assetID), revision: 5),
        ]
        if let issueID {
            expected.append(try .init(identity: .init(kind: .issue, id: issueID), revision: 6))
        }
        if let parentRecordID {
            expected.append(try .init(identity: .init(kind: .workflowRecord, id: parentRecordID), revision: 7))
        }
        expected.sort { $0.identity.stableKey < $1.identity.stableKey }
        let timeZone = includesTimeZone ? try CheckRunnerBeginTimeZoneAttemptV1(
            command: .init(siteID: siteID, timeZoneID: frozen.timeZoneID, confirmedAt: startedAt),
            mutationID: .init(rawValue: largeID(recheck ? 106 : 16)), expectedSiteRevision: 8,
            committedAt: Date(timeIntervalSince1970: 1_800_000_050)) : nil
        let attempt = try CheckRunnerFrozenBeginAttemptV1(source: source,
            sourceWorkspaceID: workspaceID, recordCommand: command,
            recordMutationID: .init(rawValue: recordID), recordExpectedEntityRevisions: expected,
            recordCommittedAt: committedAt, timeZone: timeZone, siteID: siteID,
            resolvedSiteTimeZoneID: frozen.timeZoneID)
        let timeZoneReference: CheckRunnerBeginReceiptReferenceV1?
        if let timeZone {
            timeZoneReference = try beginReference(workspaceID: workspaceID,
                mutationID: timeZone.mutationID, command: .updateSiteTimeZone(timeZone.command),
                target: .init(kind: .site, id: siteID), targetRevisionBefore: timeZone.expectedSiteRevision,
                workspaceRevisionBefore: 40, committedAt: timeZone.committedAt, seed: recheck ? 110 : 20)
                .reference
        } else {
            timeZoneReference = nil
        }
        let workflow = try beginReference(workspaceID: workspaceID,
            mutationID: attempt.recordMutationID, command: .createCheckDraft(command),
            target: .init(kind: .workflowRecord, id: recordID), targetRevisionBefore: 0,
            workspaceRevisionBefore: includesTimeZone ? 41 : 40, committedAt: committedAt,
            seed: recheck ? 120 : 30, exactBeforeRows: expected)
        return ParentFixture(source: source, attempt: attempt,
            workflowReference: workflow.reference, timeZoneReference: timeZoneReference,
            workflowEvidence: workflow.evidence)
    }

    private func parentSource(workspaceID: WorkspaceID, assetID: UUID, siteID: UUID,
        issueID: UUID?, seed: Int) throws -> CheckRunnerRoundItemSourceV1 {
        let binding = try ShippingIlluminatedSignAdapterV1.finalizationInspectionRelease(
            from: pack, stage: issueID == nil ? .check : .recheck)
        let release = try RoundPackageReleaseReferenceV1(packageReleaseID: binding.packageReleaseID,
            packageID: binding.packageID, packageContentVersion: binding.packageContentVersion,
            packageSHA256: binding.packageSHA256, workflowSHA256: binding.workflowSHA256)
        let requirement = try RoundPackageContentRequirementV1(packageRelease: release, requiredContent: [])
        let selection = try RoundAssetSelectionV1(assetID: assetID, siteID: siteID,
            labelAtSelection: "Parent payload fixture asset")
        let original = try RoundItemV1(itemID: largeID(seed + 1), order: 0,
            selection: selection, requirement: requirement)
        let actorReference = try LocalActorReferenceV1(actorReferenceID: largeID(seed + 2),
            workspaceID: workspaceID, displayName: "Parent payload fixture actor")
        let actor = try ActorSnapshotV1(snapshotID: largeID(seed + 3), workspaceID: workspaceID,
            actor: actorReference, responsibility: .recordedBy,
            displayNameAtTime: "Parent payload fixture actor",
            capturedAt: Date(timeIntervalSince1970: 1_799_999_000))
        let entered = try RoundItemV1(itemID: original.itemID, order: original.order,
            selection: original.selection, requirement: original.requirement, disposition: .visited,
            visit: .init(visitedAt: Date(timeIntervalSince1970: 1_799_999_100), recordedBy: actor))
        let sourceCheckpoint = try decodeObject(RepetitiveCaptureSourceCheckpointReferenceV1.self, [
            "draftID": largeID(seed + 4).uuidString, "draftRevision": 1,
            "checkpointSHA256": String(repeating: "1", count: 64),
            "mutationID": largeID(seed + 5).uuidString,
        ])
        let entryCheckpoint = try decodeObject(RepetitiveCaptureSourceCheckpointReferenceV1.self, [
            "draftID": largeID(seed + 6).uuidString, "draftRevision": 2,
            "checkpointSHA256": String(repeating: "2", count: 64),
            "mutationID": largeID(seed + 7).uuidString,
        ])
        let requested = issueID.map { CheckRunnerRequestedEntryV1.recheck(issueID: $0) } ?? .check
        return try decodeObject(CheckRunnerRoundItemSourceV1.self, [
            "sourceCheckpoint": try jsonValue(sourceCheckpoint),
            "entryProgressCheckpoint": try jsonValue(entryCheckpoint),
            "roundAtEntry": try jsonValue(RoundSessionReferenceV1(workspaceID: workspaceID,
                sessionID: largeID(seed + 8), revision: 3,
                sessionSHA256: String(repeating: "3", count: 64))),
            "originalItem": try jsonValue(original), "itemAtEntry": try jsonValue(entered),
            "assetID": assetID.uuidString, "packageRelease": try jsonValue(release),
            "legacyPackageIdentity": try jsonValue(PackageReleaseIdentityV1(package: pack)),
            "requestedEntry": try jsonValue(requested),
        ])
    }

    private func beginReference(workspaceID: WorkspaceID, mutationID: MutationIDV1,
        command: WorkspaceCommandV1, target: WorkspaceEntityIdentityV1,
        targetRevisionBefore: UInt64, workspaceRevisionBefore: UInt64,
        committedAt: Date, seed: Int, exactBeforeRows: [WorkspaceEntityRevisionV1]? = nil) throws
        -> (reference: CheckRunnerBeginReceiptReferenceV1, evidence: CheckRunnerBeginCommittedEvidenceV1) {
        let replicaID = ReplicaID(rawValue: largeID(seed + 1))
        let generationID = largeID(seed + 2)
        let writerID = largeID(seed + 3)
        let unrelated = try WorkspaceEntityIdentityV1(kind: .asset, id: largeID(seed + 4))
        let shapeRows = [
            WorkspaceEntityRevisionV1(identity: target, revision: targetRevisionBefore),
            WorkspaceEntityRevisionV1(identity: unrelated, revision: 19),
        ]
        let beforeRows = exactBeforeRows ?? shapeRows
        let before = try WorkspaceExpectedRevisionV1(workspaceID: workspaceID,
            generationID: generationID, writerInstanceID: writerID,
            workspaceRevision: workspaceRevisionBefore, entityRevisions: beforeRows)
        let envelope = try MutationEnvelopeV1(request: .init(mutationID: mutationID,
            expectedRevision: before, command: command),
            identity: .init(workspaceID: workspaceID, replicaID: replicaID),
            sourceKind: .importedHistory, contentDependencyIDs: [])
        let afterRows = beforeRows.map {
            WorkspaceEntityRevisionV1(identity: $0.identity,
                revision: $0.identity == target ? targetRevisionBefore + 1 : $0.revision)
        }
        let after = try MutationPortableExpectedRevisionV1(WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID, generationID: generationID, writerInstanceID: writerID,
            workspaceRevision: workspaceRevisionBefore + 1, entityRevisions: afterRows))
        let postImage: MutationPostImageV1 = target.kind == .workflowRecord
            ? .workflowRecord(id: target.id, revision: targetRevisionBefore + 1,
                semanticSHA256: String(repeating: "e", count: 64))
            : .site(id: target.id, revision: targetRevisionBefore + 1,
                semanticSHA256: String(repeating: "f", count: 64))
        let receipt = try MutationReceiptV1(identity: .init(workspaceID: workspaceID,
            replicaID: replicaID, localSequence: UInt64(seed + 1)), envelope: envelope,
            resultingRevision: after, postImages: [postImage], committedAt: committedAt)
        let evidence = try CheckRunnerBeginCommittedEvidenceV1(envelope: envelope, receipt: receipt)
        return (try .init(evidence: evidence), evidence)
    }

    private func parentField(begin: CheckRunnerBeginStateV1,
        outcome: CheckRunnerEditableOutcomeV1 = .init()) throws -> CheckRunnerItemFieldStateV1 {
        try .init(preflight: .init(), begin: begin, outcome: outcome,
            wideContext: nil, closeDetail: nil, semanticAnchor: .preflight)
    }

    private func editableOutcome(_ selection: CheckOutcomeSelection) -> CheckRunnerEditableOutcomeV1 {
        switch selection {
        case .noVisibleIssue:
            return .init(selection: .noVisibleIssue)
        case let .visibleIssue(key):
            return .init(selection: .visibleIssue(labelKey: key), choice: .visibleIssue)
        case let .couldNotVerify(key, note):
            return .init(selection: .couldNotVerify(reasonKey: key, note: note),
                choice: .couldNotVerify, selectedCouldNotVerifyReasonKey: key,
                couldNotVerifyNote: note ?? "", startsWithCouldNotVerify: true)
        case let .resolved(note):
            return .init(selection: .resolved(note: note), recheckNote: note ?? "")
        case let .issueStillVisible(note):
            return .init(selection: .issueStillVisible(note: note), recheckNote: note ?? "")
        case let .originalResolvedDifferentIssue(key, note):
            return .init(selection: .originalResolvedDifferentIssue(labelKey: key, note: note),
                choice: .differentIssue, recheckNote: note ?? "")
        }
    }

    private func preparedField(fixture: ParentFixture, outcome: CheckRunnerEditableOutcomeV1,
        mediaCount: Int, seed: Int) throws -> CheckRunnerItemFieldStateV1 {
        precondition((0...2).contains(mediaCount))
        let begin = CheckRunnerBeginStateV1.bound(attempt: fixture.attempt,
            workflowReceiptReference: fixture.workflowReference,
            timeZoneReceiptReference: fixture.timeZoneReference)
        return try .init(preflight: .init(timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true, confirmedTimeZoneID: "America/New_York",
            afterDarkAccepted: true, safePositionAccepted: true), begin: begin, outcome: outcome,
            wideContext: mediaCount > 0 ? committedFixtureSlot(child: largeID(seed + 1),
                evidence: largeID(seed + 2), step: .wide, receipt: largeID(seed + 3)) : nil,
            closeDetail: mediaCount > 1 ? committedFixtureSlot(child: largeID(seed + 4),
                evidence: largeID(seed + 5), step: .close, receipt: largeID(seed + 6)) : nil,
            semanticAnchor: .review)
    }

    private func finalizationAttempt(fixture: ParentFixture, field: CheckRunnerItemFieldStateV1,
        selection: CheckOutcomeSelection, seed: Int,
        sourceApp: SourceAppSnapshotV1 = .init(build: "23", version: "1.0")) throws
        -> CheckRunnerFinalizationAttemptInputsV1 {
        let normalized = try CheckRunnerOutcomeSnapshotV1.prepare(editor: field.outcome,
            stage: fixture.source.requestedEntry.stage, signPack: pack,
            activeLifecycleProfile: { try self.profile })
        XCTAssertEqual(normalized.selection, selection)
        let issueID: UUID?
        let newIssueID: UUID?
        switch (fixture.source.requestedEntry, selection) {
        case (.check, .visibleIssue): issueID = largeID(seed + 20); newIssueID = nil
        case let (.recheck(existing), .originalResolvedDifferentIssue):
            issueID = existing; newIssueID = largeID(seed + 20)
        case let (.recheck(existing), _): issueID = existing; newIssueID = nil
        default: issueID = nil; newIssueID = nil
        }
        let identifiers = try CheckRunnerFinalizationIdentifiersV1(.init(
            mutationID: largeID(seed + 1), packetID: largeID(seed + 2),
            stableRootID: largeID(seed + 3), reportID: largeID(seed + 4),
            issueID: issueID, newIssueID: newIssueID))
        let t = Double(1_800_000_000 + seed)
        return try .init(normalizedOutcome: normalized, identifiers: identifiers,
            completedAt: Date(timeIntervalSince1970: t),
            snapshotCreatedAt: Date(timeIntervalSince1970: t + 1), sourceApp: sourceApp,
            expectedWorkflowRecordRevision: 7, fieldDraftPlanID: largeID(seed + 5),
            preparedSagaID: largeID(seed + 6), contentPromotedSagaID: largeID(seed + 7),
            targetCommittedSagaID: largeID(seed + 8), draftRetirePendingSagaID: largeID(seed + 9),
            draftRetiredSagaID: largeID(seed + 10),
            preparedSagaMutationID: .init(rawValue: largeID(seed + 11)),
            contentPromotedSagaMutationID: .init(rawValue: largeID(seed + 12)),
            targetCommittedSagaMutationID: .init(rawValue: largeID(seed + 13)),
            draftRetirePendingSagaMutationID: .init(rawValue: largeID(seed + 14)),
            terminalBundleMutationID: .init(rawValue: largeID(seed + 15)),
            commitReceiptID: largeID(seed + 16),
            preparedSagaUpdatedAt: Date(timeIntervalSince1970: t + 10),
            contentPromotedSagaUpdatedAt: Date(timeIntervalSince1970: t + 11),
            targetCommittedSagaUpdatedAt: Date(timeIntervalSince1970: t + 12),
            draftRetirePendingSagaUpdatedAt: Date(timeIntervalSince1970: t + 13),
            draftRetiredSagaUpdatedAt: Date(timeIntervalSince1970: t + 14),
            terminalCheckpointUpdatedAt: Date(timeIntervalSince1970: t + 15))
    }

    private func pendingSlot(id: UUID, step: WorkflowDraftStep, purpose: String? = nil) -> CheckRunnerPhotoSlotV1 {
        .pending(childDraftID: id, captureStep: step,
            purposeKey: purpose ?? (step == .wide ? "wide_context" : "close_detail"))
    }

    private func committedSlot(child: UUID, evidence: UUID, step: WorkflowDraftStep,
        revision: UInt64 = 1, digest: String = String(repeating: "a", count: 64),
        target: UUID? = nil) throws -> CheckRunnerPhotoSlotV1 {
        .committed(childDraftID: child, captureStep: step,
            purposeKey: step == .wide ? "wide_context" : "close_detail",
            committedChildDraftRevision: revision, committedChildCheckpointSHA256: digest,
            childCommitReceiptID: id(90), childCommitReceiptSHA256: String(repeating: "b", count: 64),
            evidenceID: evidence, targetMutationID: try MutationIDV1(rawValue: target ?? evidence),
            targetReceiptSHA256: String(repeating: "c", count: 64))
    }

    private func committedFixtureSlot(child: UUID, evidence: UUID, step: WorkflowDraftStep,
        receipt: UUID) throws -> CheckRunnerPhotoSlotV1 {
        .committed(childDraftID: child, captureStep: step,
            purposeKey: step == .wide ? "wide_context" : "close_detail",
            committedChildDraftRevision: 1,
            committedChildCheckpointSHA256: String(repeating: "a", count: 64),
            childCommitReceiptID: receipt,
            childCommitReceiptSHA256: String(repeating: "b", count: 64),
            evidenceID: evidence, targetMutationID: try MutationIDV1(rawValue: evidence),
            targetReceiptSHA256: String(repeating: "c", count: 64))
    }

    private func id(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }

    private func largeID(_ value: Int) -> UUID {
        let high = UInt64(value) >> 8
        let low = UInt8(truncatingIfNeeded: value)
        return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, UInt8(truncatingIfNeeded: high),
            0, 0, 0, 0, 0, 0, 0, low))
    }

    private func jsonValue<Value: Encodable>(_ value: Value) throws -> Any {
        try JSONSerialization.jsonObject(with: FieldDraftCanonicalCodecV1.encode(value))
    }

    private func jsonObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        try XCTUnwrap(try jsonValue(value) as? [String: Any])
    }

    private func decodeObject<Value: Codable>(_ type: Value.Type,
        _ object: [String: Any]) throws -> Value {
        // Dictionary transport is for semantic fixture mutations. Only the
        // incumbent encoder supplies bytes for the strict canonical decoder.
        let value = try payloadJSONDecoder().decode(type, from: canonical(object))
        return try FieldDraftCanonicalCodecV1.decode(type, from: FieldDraftCanonicalCodecV1.encode(value))
    }

    private func payloadJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private func setJSON(_ object: inout [String: Any], path: [String], value: Any) throws {
        precondition(!path.isEmpty)
        if path.count == 1 { object[path[0]] = value; return }
        var child = try XCTUnwrap(object[path[0]] as? [String: Any], "fixture JSON path is not an object: \(path)")
        try setJSON(&child, path: Array(path.dropFirst()), value: value)
        object[path[0]] = child
    }

    private func removeJSON(_ object: inout [String: Any], path: [String]) throws {
        precondition(!path.isEmpty)
        if path.count == 1 { object.removeValue(forKey: path[0]); return }
        var child = try XCTUnwrap(object[path[0]] as? [String: Any], "fixture JSON path is not an object: \(path)")
        try removeJSON(&child, path: Array(path.dropFirst()))
        object[path[0]] = child
    }

    private func getJSON(_ object: [String: Any], path: [String]) throws -> Any {
        guard let first = path.first, let value = object[first] else { throw FieldDraftFailureV1.invalidValue }
        if path.count == 1 { return value }
        return try getJSON(try XCTUnwrap(value as? [String: Any]), path: Array(path.dropFirst()))
    }

    private func canonical(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}

private extension CheckOutcomeSelection {
    var note: String? {
        switch self {
        case let .couldNotVerify(_, note), let .resolved(note), let .issueStillVisible(note),
             let .originalResolvedDifferentIssue(_, note): note
        case .noVisibleIssue, .visibleIssue: nil
        }
    }
}
