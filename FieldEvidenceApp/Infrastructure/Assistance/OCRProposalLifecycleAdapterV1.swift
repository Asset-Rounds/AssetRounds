import Foundation

/// Injected platform seam. Implementations must be on-device, use no network,
/// and return fully materialized evidence before crossing this boundary.
struct InjectedOnDeviceOCRProposalAdapterV1: OCRProposalExtractingV1 {
    typealias Operation = @Sendable (OCRExtractionRequestV1) async throws -> [OCRProposalEvidenceV1]
    private let operation: Operation
    init(operation: @escaping Operation) { self.operation = operation }
    func extract(_ request: OCRExtractionRequestV1) async throws -> [OCRProposalEvidenceV1] {
        try request.validate()
        let values = try await operation(request)
        guard values.count <= 128, values.allSatisfy({ $0.request == request }) else {
            throw OCRProposalFailureV1.invalidValue
        }
        try values.forEach { try $0.validate() }
        guard values.allSatisfy({ $0.processedOnDevice && !$0.networkAccessUsed }) else {
            throw OCRProposalFailureV1.cloudProviderForbidden
        }
        return values
    }
}

enum OCRProposalLifecycleBoundaryV1 {
    static let persistenceMode = "EPHEMERAL_PROPOSAL_EXISTING_ACCEPTANCE_RECEIPT"
    static let activeSchemaVersion = 53
    static let activeModelCount = 168
    static let addedRowCount = 0
    static let scratchDeletionIsIdempotent = true
    static let latestFallbackAllowed = false
    static let shippingActivationEnabled = false
}

@MainActor final class AssistanceOCRProposalScratchLifecycleV1: OCRProposalScratchLifecycleV1 {
    typealias Prepare = @MainActor (OCRExtractionRequestV1) async throws -> Void
    private let prepareOperation: Prepare
    private let assistanceScratch: any AssistanceScratchDiscardingV1
    init(assistanceScratch:any AssistanceScratchDiscardingV1,
         prepare:@escaping Prepare){self.assistanceScratch=assistanceScratch;prepareOperation=prepare}
    func prepare(_ request:OCRExtractionRequestV1)async throws{try request.validate();try await prepareOperation(request)}
    func discardAfterFailedExtraction(_ request:OCRExtractionRequestV1)async throws{
        try request.validate()
        guard request.source.kind == .leasedScratch else{return}
        try await assistanceScratch.finishAssistanceScratch(proposalID:request.requestID,
            source:request.source,disposition:.failed,immutableContentReceiptDigest:nil)
    }
}
