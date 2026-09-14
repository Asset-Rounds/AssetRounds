import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23CheckRunnerEditableFieldValuesTests: XCTestCase {
    func testAllSelectionCasesHaveLiveInverseAndExactCanonicalBytes() throws {
        let cases: [(CheckRunnerEditableSelectionV1, CheckOutcomeSelection, String)] = [
            (.noVisibleIssue, .noVisibleIssue, #"{"tag":"NO_VISIBLE_ISSUE"}"#),
            (.visibleIssue(labelKey: "issue_a"), .visibleIssue(labelKey: "issue_a"), #"{"labelKey":"issue_a","tag":"VISIBLE_ISSUE"}"#),
            (.couldNotVerify(reasonKey: "weather", note: " note "), .couldNotVerify(reasonKey: "weather", note: " note "), #"{"note":" note ","reasonKey":"weather","tag":"COULD_NOT_VERIFY"}"#),
            (.resolved(note: nil), .resolved(note: nil), #"{"tag":"RESOLVED"}"#),
            (.issueStillVisible(note: ""), .issueStillVisible(note: ""), #"{"note":"","tag":"ISSUE_STILL_VISIBLE"}"#),
            (.originalResolvedDifferentIssue(labelKey: "other", note: "why"), .originalResolvedDifferentIssue(labelKey: "other", note: "why"), #"{"labelKey":"other","note":"why","tag":"ORIGINAL_RESOLVED_DIFFERENT_ISSUE"}"#)
        ]

        for (stored, live, literal) in cases {
            XCTAssertTrue(sameSelectionBytes(stored.liveSelection, live))
            XCTAssertEqual(CheckRunnerEditableSelectionV1(stored.liveSelection), stored)
            let bytes = try FieldDraftCanonicalCodecV1.encode(stored)
            XCTAssertEqual(bytes, Data(literal.utf8), literal)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.decode(CheckRunnerEditableSelectionV1.self, from: bytes), stored)
        }
        XCTAssertNotEqual(CheckRunnerEditableSelectionV1.resolved(note: nil), .resolved(note: ""))
        XCTAssertNotEqual(
            try FieldDraftCanonicalCodecV1.encode(CheckRunnerEditableSelectionV1.resolved(note: nil)),
            try FieldDraftCanonicalCodecV1.encode(CheckRunnerEditableSelectionV1.resolved(note: ""))
        )
    }

    func testClosedDecodingRejectsUnknownAssociatedMissingTagChoiceAndTypes() {
        let invalidSelections = [
            #"{"tag":"NO_VISIBLE_ISSUE","unknown":1}"#,
            #"{"tag":"NO_VISIBLE_ISSUE","note":"wrong association"}"#,
            #"{"tag":"VISIBLE_ISSUE"}"#,
            #"{"tag":"VISIBLE_ISSUE","reasonKey":"wrong association"}"#,
            #"{"tag":"COULD_NOT_VERIFY","reasonKey":"r","labelKey":"wrong association"}"#,
            #"{"tag":"ORIGINAL_RESOLVED_DIFFERENT_ISSUE","note":"missing label"}"#,
            #"{"tag":"UNKNOWN"}"#,
            #"{"tag":7}"#,
            #"{"tag":"VISIBLE_ISSUE","labelKey":false}"#,
            #"[]"#
        ]
        for json in invalidSelections {
            XCTAssertThrowsError(try JSONDecoder().decode(CheckRunnerEditableSelectionV1.self, from: Data(json.utf8)), json)
        }

        let invalidOutcomes = [
            #"{"choice":"NONE","couldNotVerifyNote":"","recheckNote":"","startsWithCouldNotVerify":false,"unknown":1}"#,
            #"{"couldNotVerifyNote":"","recheckNote":"","startsWithCouldNotVerify":false}"#,
            #"{"choice":"UNKNOWN","couldNotVerifyNote":"","recheckNote":"","startsWithCouldNotVerify":false}"#,
            #"{"choice":"NONE","couldNotVerifyNote":false,"recheckNote":"","startsWithCouldNotVerify":false}"#,
            #"{"choice":"NONE","couldNotVerifyNote":"","recheckNote":"","startsWithCouldNotVerify":"false"}"#,
            #"{"choice":"NONE","couldNotVerifyNote":"","recheckNote":"","selection":{"tag":"RESOLVED","labelKey":"wrong"},"startsWithCouldNotVerify":false}"#
        ]
        for json in invalidOutcomes {
            XCTAssertThrowsError(try JSONDecoder().decode(CheckRunnerEditableOutcomeV1.self, from: Data(json.utf8)), json)
        }

        let invalidPreflights = [
            #"{"afterDarkAccepted":false,"isTimeZoneConfirmed":false,"safePositionAccepted":false,"timeZoneID":"","unknown":1}"#,
            #"{"afterDarkAccepted":false,"safePositionAccepted":false,"timeZoneID":""}"#,
            #"{"afterDarkAccepted":false,"isTimeZoneConfirmed":false,"safePositionAccepted":false,"timeZoneID":7}"#,
            #"{"afterDarkAccepted":false,"confirmedTimeZoneID":false,"isTimeZoneConfirmed":false,"safePositionAccepted":false,"timeZoneID":""}"#
        ]
        for json in invalidPreflights {
            XCTAssertThrowsError(try JSONDecoder().decode(CheckRunnerEditablePreflightV1.self, from: Data(json.utf8)), json)
        }
    }

    func testRawEditableStringsRoundTripWithoutBlanketFieldCapsOrNormalization() throws {
        let composed = "caf\u{00E9}"
        let decomposed = "cafe\u{0301}"
        let long513 = String(repeating: "x", count: 513)
        let long1001 = String(repeating: "🧪", count: 1_001)
        let recheckLong = "  " + String(repeating: "r", count: 1_001) + "\n"
        let preflight = CheckRunnerEditablePreflightV1(
            timeZoneID: "  Invalid/Zone \n" + long513,
            isTimeZoneConfirmed: true,
            confirmedTimeZoneID: decomposed,
            afterDarkAccepted: true,
            safePositionAccepted: false
        )
        let outcome = CheckRunnerEditableOutcomeV1(
            selection: .couldNotVerify(reasonKey: composed, note: long1001),
            choice: .couldNotVerify,
            selectedCouldNotVerifyReasonKey: decomposed,
            couldNotVerifyNote: "  " + long1001 + "\n",
            recheckNote: recheckLong,
            startsWithCouldNotVerify: true
        )

        try assertCanonicalRoundTrip(preflight)
        try assertCanonicalRoundTrip(outcome)
        XCTAssertNotEqual(preflight, .init(timeZoneID: preflight.timeZoneID, isTimeZoneConfirmed: true, confirmedTimeZoneID: composed, afterDarkAccepted: true, safePositionAccepted: false))
        XCTAssertFalse(outcome.selectedCouldNotVerifyReasonKey?.utf8.elementsEqual(composed.utf8) ?? true)
        XCTAssertEqual(outcome.couldNotVerifyNote.count, 1_004)
        XCTAssertEqual(outcome.recheckNote.count, 1_004)

        let nilAndEmpty = CheckRunnerEditableOutcomeV1(
            selection: .resolved(note: nil),
            selectedCouldNotVerifyReasonKey: nil,
            couldNotVerifyNote: "",
            recheckNote: "",
            startsWithCouldNotVerify: false
        )
        let bytes = try FieldDraftCanonicalCodecV1.encode(nilAndEmpty)
        XCTAssertEqual(bytes, Data(#"{"choice":"NONE","couldNotVerifyNote":"","recheckNote":"","selection":{"tag":"RESOLVED"},"startsWithCouldNotVerify":false}"#.utf8))
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.decode(CheckRunnerEditableOutcomeV1.self, from: bytes), nilAndEmpty)
    }

    func testPreflightDefaultsAndIncumbentSnapshotInitialValuesRemainExact() throws {
        let defaults = CheckRunnerEditablePreflightV1()
        XCTAssertEqual(defaults, .init(timeZoneID: "", isTimeZoneConfirmed: false, confirmedTimeZoneID: nil, afterDarkAccepted: false, safePositionAccepted: false))
        XCTAssertNotEqual(defaults, .init(timeZoneID: "", isTimeZoneConfirmed: false, confirmedTimeZoneID: "", afterDarkAccepted: false, safePositionAccepted: false))
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(defaults), Data(#"{"afterDarkAccepted":false,"isTimeZoneConfirmed":false,"safePositionAccepted":false,"timeZoneID":""}"#.utf8))

        for snapshotTimeZone in [nil, "America/New_York", " Invalid/ButRetained "] as [String?] {
            let transcribedInitial = CheckRunnerEditablePreflightV1(
                timeZoneID: snapshotTimeZone ?? "",
                isTimeZoneConfirmed: snapshotTimeZone != nil,
                confirmedTimeZoneID: snapshotTimeZone,
                afterDarkAccepted: false,
                safePositionAccepted: false
            )
            try assertCanonicalRoundTrip(transcribedInitial)
            XCTAssertEqual(transcribedInitial.timeZoneID, snapshotTimeZone ?? "")
            XCTAssertEqual(transcribedInitial.isTimeZoneConfirmed, snapshotTimeZone != nil)
            XCTAssertEqual(transcribedInitial.confirmedTimeZoneID, snapshotTimeZone)
        }
    }

    func testIncumbentInitialAndPrimaryCategoryTraceMatchesEditableValue() {
        assertTrace(
            startsWithCouldNotVerify: false,
            events: [
                .selectNoVisibleIssue,
                .chooseVisibleIssue,
                .selectIssue("lamp_out"),
                .setCouldNotVerifyNote("irrelevant while visible"),
                .chooseCouldNotVerify,
                .selectReason("access_blocked"),
                .chooseVisibleIssue,
                .chooseCouldNotVerify
            ],
            expected: [
                .init(.noVisibleIssue, .none, nil, "", "", false),
                .init(nil, .visibleIssue, nil, "", "", false),
                .init(.visibleIssue(labelKey: "lamp_out"), .visibleIssue, nil, "", "", false),
                .init(.visibleIssue(labelKey: "lamp_out"), .visibleIssue, nil, "irrelevant while visible", "", false),
                .init(nil, .couldNotVerify, nil, "irrelevant while visible", "", false),
                .init(.couldNotVerify(reasonKey: "access_blocked", note: "irrelevant while visible"), .couldNotVerify, "access_blocked", "irrelevant while visible", "", false),
                .init(nil, .visibleIssue, "access_blocked", "irrelevant while visible", "", false),
                .init(nil, .couldNotVerify, "access_blocked", "irrelevant while visible", "", false)
            ]
        )

        let initial = CheckRunnerEditableOutcomeV1.initial(startsWithCouldNotVerify: true)
        XCTAssertEqual(initial, .init(
            selection: nil,
            choice: .couldNotVerify,
            selectedCouldNotVerifyReasonKey: nil,
            couldNotVerifyNote: "",
            recheckNote: "",
            startsWithCouldNotVerify: true
        ))
    }

    func testIncumbentCouldNotVerifyCallbacksPreserveHighlightAndRawOverflow() {
        let long1000 = String(repeating: "n", count: 1_000)
        let long1001 = long1000 + "n"
        assertTrace(
            startsWithCouldNotVerify: true,
            events: [
                .setCouldNotVerifyNote("ignored before reason"),
                .selectReason("weather"),
                .setCouldNotVerifyNote(" \n "),
                .setCouldNotVerifyNote(long1000),
                .setCouldNotVerifyNote(long1001),
                .setRecheckNote("separate note")
            ],
            expected: [
                .init(nil, .couldNotVerify, nil, "ignored before reason", "", true),
                .init(.couldNotVerify(reasonKey: "weather", note: "ignored before reason"), .couldNotVerify, "weather", "ignored before reason", "", true),
                .init(.couldNotVerify(reasonKey: "weather", note: nil), .couldNotVerify, "weather", " \n ", "", true),
                .init(.couldNotVerify(reasonKey: "weather", note: long1000), .couldNotVerify, "weather", long1000, "", true),
                .init(.couldNotVerify(reasonKey: "weather", note: long1001), .couldNotVerify, "weather", long1001, "", true),
                .init(.couldNotVerify(reasonKey: "weather", note: long1001), .couldNotVerify, "weather", long1001, "separate note", true)
            ]
        )
    }

    func testEveryIncumbentRecheckNoteCallbackIncludingIrrelevantAndNilSelection() {
        let long1000 = String(repeating: "r", count: 1_000)
        let long1001 = long1000 + "r"
        assertTrace(
            startsWithCouldNotVerify: false,
            events: [
                .setRecheckNote("before selection"),
                .selectResolved,
                .setRecheckNote(" \n"),
                .setRecheckNote(long1000),
                .setRecheckNote(long1001),
                .selectIssueStillVisible,
                .setRecheckNote(" visible "),
                .chooseDifferentIssue,
                .setRecheckNote("ignored while nil"),
                .selectIssue("new_issue"),
                .setRecheckNote(" different "),
                .chooseVisibleIssue,
                .selectIssue("ordinary"),
                .setRecheckNote("irrelevant visible selection")
            ],
            expected: [
                .init(nil, .none, nil, "", "before selection", false),
                .init(.resolved(note: "before selection"), .none, nil, "", "before selection", false),
                .init(.resolved(note: nil), .none, nil, "", " \n", false),
                .init(.resolved(note: long1000), .none, nil, "", long1000, false),
                .init(.resolved(note: long1001), .none, nil, "", long1001, false),
                .init(.issueStillVisible(note: long1001), .none, nil, "", long1001, false),
                .init(.issueStillVisible(note: "visible"), .none, nil, "", " visible ", false),
                .init(nil, .differentIssue, nil, "", " visible ", false),
                .init(nil, .differentIssue, nil, "", "ignored while nil", false),
                .init(.originalResolvedDifferentIssue(labelKey: "new_issue", note: "ignored while nil"), .differentIssue, nil, "", "ignored while nil", false),
                .init(.originalResolvedDifferentIssue(labelKey: "new_issue", note: "different"), .differentIssue, nil, "", " different ", false),
                .init(nil, .visibleIssue, nil, "", " different ", false),
                .init(.visibleIssue(labelKey: "ordinary"), .visibleIssue, nil, "", " different ", false),
                .init(.visibleIssue(labelKey: "ordinary"), .visibleIssue, nil, "", "irrelevant visible selection", false)
            ]
        )
    }

    private enum IncumbentEvent {
        case selectNoVisibleIssue, selectResolved, selectIssueStillVisible
        case chooseVisibleIssue, chooseDifferentIssue, chooseCouldNotVerify
        case selectIssue(String), selectReason(String)
        case setCouldNotVerifyNote(String), setRecheckNote(String)
    }

    private struct ExpectedState {
        let selection: CheckRunnerEditableSelectionV1?
        let choice: CheckRunnerEditableOutcomeChoiceV1
        let reason: String?
        let couldNotVerifyNote: String
        let recheckNote: String
        let startsWithCouldNotVerify: Bool

        init(_ selection: CheckRunnerEditableSelectionV1?, _ choice: CheckRunnerEditableOutcomeChoiceV1, _ reason: String?, _ couldNotVerifyNote: String, _ recheckNote: String, _ startsWithCouldNotVerify: Bool) {
            self.selection = selection
            self.choice = choice
            self.reason = reason
            self.couldNotVerifyNote = couldNotVerifyNote
            self.recheckNote = recheckNote
            self.startsWithCouldNotVerify = startsWithCouldNotVerify
        }
    }

    private func assertTrace(startsWithCouldNotVerify: Bool, events: [IncumbentEvent], expected: [ExpectedState], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(events.count, expected.count, file: file, line: line)
        var value = CheckRunnerEditableOutcomeV1.initial(startsWithCouldNotVerify: startsWithCouldNotVerify)
        for (index, event) in events.enumerated() {
            switch event {
            case .selectNoVisibleIssue: value.selectNoVisibleIssue()
            case .selectResolved: value.selectResolved()
            case .selectIssueStillVisible: value.selectIssueStillVisible()
            case .chooseVisibleIssue: value.chooseVisibleIssue()
            case .chooseDifferentIssue: value.chooseDifferentIssue()
            case .chooseCouldNotVerify: value.chooseCouldNotVerify()
            case let .selectIssue(key): value.selectIssue(labelKey: key)
            case let .selectReason(key): value.selectCouldNotVerifyReason(key: key)
            case let .setCouldNotVerifyNote(note): value.couldNotVerifyNote = note; value.updateCouldNotVerifySelection()
            case let .setRecheckNote(note): value.recheckNote = note; value.updateRecheckSelection()
            }
            let e = expected[index]
            XCTAssertEqual(value.selection, e.selection, "event \(index)", file: file, line: line)
            XCTAssertEqual(value.choice, e.choice, "event \(index)", file: file, line: line)
            XCTAssertEqual(value.selectedCouldNotVerifyReasonKey, e.reason, "event \(index)", file: file, line: line)
            XCTAssertEqual(value.couldNotVerifyNote, e.couldNotVerifyNote, "event \(index)", file: file, line: line)
            XCTAssertEqual(value.recheckNote, e.recheckNote, "event \(index)", file: file, line: line)
            XCTAssertEqual(value.startsWithCouldNotVerify, e.startsWithCouldNotVerify, "event \(index)", file: file, line: line)
        }
    }

    private func assertCanonicalRoundTrip<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let bytes = try FieldDraftCanonicalCodecV1.encode(value)
        let decoded = try FieldDraftCanonicalCodecV1.decode(T.self, from: bytes)
        XCTAssertEqual(decoded, value, file: file, line: line)
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), bytes, file: file, line: line)
    }

    private func sameSelectionBytes(_ lhs: CheckOutcomeSelection, _ rhs: CheckOutcomeSelection) -> Bool {
        switch (lhs, rhs) {
        case (.noVisibleIssue, .noVisibleIssue): true
        case let (.visibleIssue(a), .visibleIssue(b)): a.utf8.elementsEqual(b.utf8)
        case let (.couldNotVerify(a, an), .couldNotVerify(b, bn)), let (.originalResolvedDifferentIssue(a, an), .originalResolvedDifferentIssue(b, bn)):
            a.utf8.elementsEqual(b.utf8) && sameOptionalBytes(an, bn)
        case let (.resolved(a), .resolved(b)), let (.issueStillVisible(a), .issueStillVisible(b)): sameOptionalBytes(a, b)
        default: false
        }
    }

    private func sameOptionalBytes(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): lhs.utf8.elementsEqual(rhs.utf8)
        default: false
        }
    }
}
