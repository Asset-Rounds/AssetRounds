import Foundation

enum WorkflowRevisionKind: String, CaseIterable, Codable, Sendable {
    case original
    case clericalCorrection = "clerical_correction"
}

enum WorkflowStage: String, CaseIterable, Codable, Sendable {
    case check
    case work
    case recheck
}

enum WorkflowState: String, CaseIterable, Codable, Sendable {
    case draft
    case completed
}

enum WorkflowDraftStep: String, CaseIterable, Codable, Sendable {
    case wide
    case close
    case outcome
    case review
}

enum IssueStatus: String, CaseIterable, Codable, Sendable {
    case open
    case recheckDue = "recheck_due"
    case resolved
}

enum ReportPDFState: String, CaseIterable, Codable, Sendable {
    case pending
    case ready
    case failed
}
