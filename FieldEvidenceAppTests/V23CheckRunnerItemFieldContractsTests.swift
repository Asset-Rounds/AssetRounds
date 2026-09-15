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

    private func id(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
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
