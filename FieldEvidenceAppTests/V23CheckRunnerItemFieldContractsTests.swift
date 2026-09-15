import Foundation
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
            (["field", "begin", "workflowReceiptReference", "mutationID", "rawValue"], largeID(901).uuidString),
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
            setJSON(&hostile, path: path, value: replacement)
            XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile)), "\(path)")
        }
        for path in [
            ["field", "begin", "workflowReceiptReference", "commandBodySHA256"],
            ["field", "begin", "workflowReceiptReference"],
            ["field", "begin", "attempt"],
        ] {
            var hostile = valid
            removeJSON(&hostile, path: path)
            XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile)), "\(path)")
        }
        var unknown = valid
        setJSON(&unknown, path: ["field", "begin", "workflowReceiptReference", "future"], value: true)
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
            var hostile = object; setJSON(&hostile, path: path, value: value)
            XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile)))
        }
        var missing = object; missing.removeValue(forKey: "field")
        XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(missing)))
        var nestedMissing = object
        removeJSON(&nestedMissing, path: ["field", "preflight", "timeZoneID"])
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
            ["field", "begin", "attempt", "recordMutationID", "rawValue"],
            ["field", "begin", "attempt", "timeZone", "mutationID", "rawValue"],
            ["finalizationAttempt", "identifiers", "mutationID"],
            ["finalizationAttempt", "identifiers", "packetID"],
            ["finalizationAttempt", "fieldDraftPlanID"],
            ["finalizationAttempt", "preparedSagaMutationID", "rawValue"],
            ["field", "wideContext", "childDraftID"],
            ["field", "wideContext", "evidenceID"],
        ]
        for path in zeroPaths {
            var hostile = valid; setJSON(&hostile, path: path, value: zero)
            XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile)), "\(path)")
        }
        let aliasPairs: [([String], [String])] = [
            (["finalizationAttempt", "identifiers", "packetID"], ["finalizationAttempt", "identifiers", "mutationID"]),
            (["finalizationAttempt", "identifiers", "mutationID"], ["finalizationAttempt", "preparedSagaID"]),
            (["finalizationAttempt", "targetCommittedSagaID"], ["finalizationAttempt", "preparedSagaID"]),
            (["finalizationAttempt", "commitReceiptID"], ["field", "begin", "attempt", "recordCommand", "recordID"]),
            (["finalizationAttempt", "preparedSagaMutationID", "rawValue"],
                ["field", "begin", "attempt", "timeZone", "mutationID", "rawValue"]),
            (["finalizationAttempt", "preparedSagaID"], ["finalizationAttempt", "identifiers", "issueID"]),
            (["finalizationAttempt", "identifiers", "issueID"], ["finalizationAttempt", "identifiers", "reportID"]),
        ]
        for (target, source) in aliasPairs {
            var hostile = valid; setJSON(&hostile, path: target, value: try getJSON(hostile, path: source))
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
            setJSON(&hostile, path: path, value: earlier - 1)
            XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile)), "\(path)")
        }
        var fractional = valid
        let terminal = try XCTUnwrap(try getJSON(fractional,
            path: ["finalizationAttempt", "terminalCheckpointUpdatedAt"]) as? Double)
        setJSON(&fractional, path: ["finalizationAttempt", "terminalCheckpointUpdatedAt"],
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
        setJSON(&reversedBeginEffects, path: ["field", "begin", "attempt", "timeZone", "committedAt"],
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
        setJSON(&pendingAlias, path: ["field", "closeDetail", "childDraftID"],
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
            var hostile = valid; setJSON(&hostile, path: path, value: value)
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
            var hostile = valid; setJSON(&hostile, path: path, value: true)
            XCTAssertThrowsError(try CheckRunnerItemDraftPayloadV1.decode(canonical(hostile)), "\(path)")
        }
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
        try FieldDraftCanonicalCodecV1.decode(type, from: canonical(object))
    }

    private func payloadJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private func setJSON(_ object: inout [String: Any], path: [String], value: Any) {
        precondition(!path.isEmpty)
        if path.count == 1 { object[path[0]] = value; return }
        var child = object[path[0]] as! [String: Any]
        setJSON(&child, path: Array(path.dropFirst()), value: value)
        object[path[0]] = child
    }

    private func removeJSON(_ object: inout [String: Any], path: [String]) {
        precondition(!path.isEmpty)
        if path.count == 1 { object.removeValue(forKey: path[0]); return }
        var child = object[path[0]] as! [String: Any]
        removeJSON(&child, path: Array(path.dropFirst()))
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
