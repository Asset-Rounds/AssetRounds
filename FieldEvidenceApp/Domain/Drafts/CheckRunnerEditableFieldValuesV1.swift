import Foundation

// Editable values preserve input, including values that cannot yet be submitted.
// The enclosing draft codec owns its payload bound and publication authority.
struct CheckRunnerEditablePreflightV1: Codable, Equatable, Sendable {
    var timeZoneID: String
    var isTimeZoneConfirmed: Bool
    var confirmedTimeZoneID: String?
    var afterDarkAccepted: Bool
    var safePositionAccepted: Bool

    init(
        timeZoneID: String = "",
        isTimeZoneConfirmed: Bool = false,
        confirmedTimeZoneID: String? = nil,
        afterDarkAccepted: Bool = false,
        safePositionAccepted: Bool = false
    ) {
        self.timeZoneID = timeZoneID
        self.isTimeZoneConfirmed = isTimeZoneConfirmed
        self.confirmedTimeZoneID = confirmedTimeZoneID
        self.afterDarkAccepted = afterDarkAccepted
        self.safePositionAccepted = safePositionAccepted
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        checkRunnerEditableBytesEqualV1(lhs.timeZoneID, rhs.timeZoneID)
            && lhs.isTimeZoneConfirmed == rhs.isTimeZoneConfirmed
            && checkRunnerEditableBytesEqualV1(lhs.confirmedTimeZoneID, rhs.confirmedTimeZoneID)
            && lhs.afterDarkAccepted == rhs.afterDarkAccepted
            && lhs.safePositionAccepted == rhs.safePositionAccepted
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case timeZoneID, isTimeZoneConfirmed, confirmedTimeZoneID
        case afterDarkAccepted, safePositionAccepted
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timeZoneID = try c.decode(String.self, forKey: .timeZoneID)
        isTimeZoneConfirmed = try c.decode(Bool.self, forKey: .isTimeZoneConfirmed)
        confirmedTimeZoneID = try c.decodeIfPresent(String.self, forKey: .confirmedTimeZoneID)
        afterDarkAccepted = try c.decode(Bool.self, forKey: .afterDarkAccepted)
        safePositionAccepted = try c.decode(Bool.self, forKey: .safePositionAccepted)
    }
}

enum CheckRunnerEditableSelectionV1: Codable, Equatable, Sendable {
    case noVisibleIssue
    case visibleIssue(labelKey: String)
    case couldNotVerify(reasonKey: String, note: String?)
    case resolved(note: String?)
    case issueStillVisible(note: String?)
    case originalResolvedDifferentIssue(labelKey: String, note: String?)

    init(_ selection: CheckOutcomeSelection) {
        switch selection {
        case .noVisibleIssue: self = .noVisibleIssue
        case let .visibleIssue(key): self = .visibleIssue(labelKey: key)
        case let .couldNotVerify(key, note): self = .couldNotVerify(reasonKey: key, note: note)
        case let .resolved(note): self = .resolved(note: note)
        case let .issueStillVisible(note): self = .issueStillVisible(note: note)
        case let .originalResolvedDifferentIssue(key, note):
            self = .originalResolvedDifferentIssue(labelKey: key, note: note)
        }
    }

    var liveSelection: CheckOutcomeSelection {
        switch self {
        case .noVisibleIssue: .noVisibleIssue
        case let .visibleIssue(key): .visibleIssue(labelKey: key)
        case let .couldNotVerify(key, note): .couldNotVerify(reasonKey: key, note: note)
        case let .resolved(note): .resolved(note: note)
        case let .issueStillVisible(note): .issueStillVisible(note: note)
        case let .originalResolvedDifferentIssue(key, note):
            .originalResolvedDifferentIssue(labelKey: key, note: note)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.noVisibleIssue, .noVisibleIssue): true
        case let (.visibleIssue(a), .visibleIssue(b)):
            checkRunnerEditableBytesEqualV1(a, b)
        case let (.couldNotVerify(a, an), .couldNotVerify(b, bn)),
             let (.originalResolvedDifferentIssue(a, an), .originalResolvedDifferentIssue(b, bn)):
            checkRunnerEditableBytesEqualV1(a, b) && checkRunnerEditableBytesEqualV1(an, bn)
        case let (.resolved(a), .resolved(b)), let (.issueStillVisible(a), .issueStillVisible(b)):
            checkRunnerEditableBytesEqualV1(a, b)
        default: false
        }
    }

    private enum CodingKeys: String, CodingKey { case tag, labelKey, reasonKey, note }
    private enum Tag: String, Codable {
        case noVisibleIssue = "NO_VISIBLE_ISSUE"
        case visibleIssue = "VISIBLE_ISSUE"
        case couldNotVerify = "COULD_NOT_VERIFY"
        case resolved = "RESOLVED"
        case issueStillVisible = "ISSUE_STILL_VISIBLE"
        case originalResolvedDifferentIssue = "ORIGINAL_RESOLVED_DIFFERENT_ISSUE"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(Tag.self, forKey: .tag)
        let allowed: Set<String>
        switch tag {
        case .noVisibleIssue: allowed = ["tag"]
        case .visibleIssue: allowed = ["tag", "labelKey"]
        case .couldNotVerify: allowed = ["tag", "reasonKey", "note"]
        case .resolved, .issueStillVisible: allowed = ["tag", "note"]
        case .originalResolvedDifferentIssue: allowed = ["tag", "labelKey", "note"]
        }
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: allowed)
        switch tag {
        case .noVisibleIssue: self = .noVisibleIssue
        case .visibleIssue:
            self = .visibleIssue(labelKey: try c.decode(String.self, forKey: .labelKey))
        case .couldNotVerify:
            self = .couldNotVerify(
                reasonKey: try c.decode(String.self, forKey: .reasonKey),
                note: try c.decodeIfPresent(String.self, forKey: .note)
            )
        case .resolved:
            self = .resolved(note: try c.decodeIfPresent(String.self, forKey: .note))
        case .issueStillVisible:
            self = .issueStillVisible(note: try c.decodeIfPresent(String.self, forKey: .note))
        case .originalResolvedDifferentIssue:
            self = .originalResolvedDifferentIssue(
                labelKey: try c.decode(String.self, forKey: .labelKey),
                note: try c.decodeIfPresent(String.self, forKey: .note)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noVisibleIssue:
            try c.encode(Tag.noVisibleIssue, forKey: .tag)
        case let .visibleIssue(key):
            try c.encode(Tag.visibleIssue, forKey: .tag)
            try c.encode(key, forKey: .labelKey)
        case let .couldNotVerify(key, note):
            try c.encode(Tag.couldNotVerify, forKey: .tag)
            try c.encode(key, forKey: .reasonKey)
            try c.encodeIfPresent(note, forKey: .note)
        case let .resolved(note):
            try c.encode(Tag.resolved, forKey: .tag)
            try c.encodeIfPresent(note, forKey: .note)
        case let .issueStillVisible(note):
            try c.encode(Tag.issueStillVisible, forKey: .tag)
            try c.encodeIfPresent(note, forKey: .note)
        case let .originalResolvedDifferentIssue(key, note):
            try c.encode(Tag.originalResolvedDifferentIssue, forKey: .tag)
            try c.encode(key, forKey: .labelKey)
            try c.encodeIfPresent(note, forKey: .note)
        }
    }
}

enum CheckRunnerEditableOutcomeChoiceV1: String, Codable, Equatable, Sendable {
    case none = "NONE"
    case visibleIssue = "VISIBLE_ISSUE"
    case differentIssue = "DIFFERENT_ISSUE"
    case couldNotVerify = "COULD_NOT_VERIFY"
}

struct CheckRunnerEditableOutcomeV1: Codable, Equatable, Sendable {
    var selection: CheckRunnerEditableSelectionV1?
    var choice: CheckRunnerEditableOutcomeChoiceV1
    var selectedCouldNotVerifyReasonKey: String?
    var couldNotVerifyNote: String
    var recheckNote: String
    let startsWithCouldNotVerify: Bool

    init(
        selection: CheckRunnerEditableSelectionV1? = nil,
        choice: CheckRunnerEditableOutcomeChoiceV1 = .none,
        selectedCouldNotVerifyReasonKey: String? = nil,
        couldNotVerifyNote: String = "",
        recheckNote: String = "",
        startsWithCouldNotVerify: Bool = false
    ) {
        self.selection = selection
        self.choice = choice
        self.selectedCouldNotVerifyReasonKey = selectedCouldNotVerifyReasonKey
        self.couldNotVerifyNote = couldNotVerifyNote
        self.recheckNote = recheckNote
        self.startsWithCouldNotVerify = startsWithCouldNotVerify
    }

    static func initial(startsWithCouldNotVerify: Bool) -> Self {
        .init(
            choice: startsWithCouldNotVerify ? .couldNotVerify : .none,
            startsWithCouldNotVerify: startsWithCouldNotVerify
        )
    }

    mutating func selectNoVisibleIssue() {
        selection = .noVisibleIssue
        choice = .none
    }

    mutating func selectResolved() {
        selection = .resolved(note: projectedNote(recheckNote))
        choice = .none
    }

    mutating func selectIssueStillVisible() {
        selection = .issueStillVisible(note: projectedNote(recheckNote))
        choice = .none
    }

    mutating func chooseVisibleIssue() {
        selection = nil
        choice = .visibleIssue
    }

    mutating func chooseDifferentIssue() {
        selection = nil
        choice = .differentIssue
    }

    mutating func chooseCouldNotVerify() {
        selection = nil
        choice = .couldNotVerify
    }

    mutating func selectIssue(labelKey: String) {
        if choice == .differentIssue {
            selection = .originalResolvedDifferentIssue(labelKey: labelKey, note: projectedNote(recheckNote))
        } else {
            selection = .visibleIssue(labelKey: labelKey)
            choice = .visibleIssue
        }
    }

    mutating func selectCouldNotVerifyReason(key: String) {
        selectedCouldNotVerifyReasonKey = key
        selection = .couldNotVerify(reasonKey: key, note: projectedNote(couldNotVerifyNote))
    }

    mutating func updateRecheckSelection() {
        switch selection {
        case .resolved:
            selection = .resolved(note: projectedNote(recheckNote))
        case .issueStillVisible:
            selection = .issueStillVisible(note: projectedNote(recheckNote))
        case let .originalResolvedDifferentIssue(labelKey, _):
            selection = .originalResolvedDifferentIssue(labelKey: labelKey, note: projectedNote(recheckNote))
        default:
            break
        }
    }

    mutating func updateCouldNotVerifySelection() {
        guard let key = selectedCouldNotVerifyReasonKey else { return }
        selection = .couldNotVerify(reasonKey: key, note: projectedNote(couldNotVerifyNote))
    }

    private func projectedNote(_ raw: String) -> String? {
        switch CheckRunnerOutcomeResolverV1.projectEditableNote(raw) {
        case .none: nil
        case let .value(value): value
        case .invalid: raw
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selection == rhs.selection && lhs.choice == rhs.choice
            && checkRunnerEditableBytesEqualV1(lhs.selectedCouldNotVerifyReasonKey, rhs.selectedCouldNotVerifyReasonKey)
            && checkRunnerEditableBytesEqualV1(lhs.couldNotVerifyNote, rhs.couldNotVerifyNote)
            && checkRunnerEditableBytesEqualV1(lhs.recheckNote, rhs.recheckNote)
            && lhs.startsWithCouldNotVerify == rhs.startsWithCouldNotVerify
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case selection, choice, selectedCouldNotVerifyReasonKey
        case couldNotVerifyNote, recheckNote, startsWithCouldNotVerify
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selection = try c.decodeIfPresent(CheckRunnerEditableSelectionV1.self, forKey: .selection)
        choice = try c.decode(CheckRunnerEditableOutcomeChoiceV1.self, forKey: .choice)
        selectedCouldNotVerifyReasonKey = try c.decodeIfPresent(String.self, forKey: .selectedCouldNotVerifyReasonKey)
        couldNotVerifyNote = try c.decode(String.self, forKey: .couldNotVerifyNote)
        recheckNote = try c.decode(String.self, forKey: .recheckNote)
        startsWithCouldNotVerify = try c.decode(Bool.self, forKey: .startsWithCouldNotVerify)
    }
}

private func checkRunnerEditableBytesEqualV1(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.elementsEqual(rhs.utf8)
}

private func checkRunnerEditableBytesEqualV1(_ lhs: String?, _ rhs: String?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): true
    case let (lhs?, rhs?): checkRunnerEditableBytesEqualV1(lhs, rhs)
    default: false
    }
}
