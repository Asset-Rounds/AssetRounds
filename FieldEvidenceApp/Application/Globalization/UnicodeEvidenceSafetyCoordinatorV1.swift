import Foundation

/// Audits the existing writer and replay codecs without producing a second
/// representation of workspace data. The structural checks retain the C05
/// guarantees; byte checks additionally distinguish canonically equivalent
/// Unicode spellings. Existing envelope, receipt, backup and restore decoders
/// already compare their canonical bytes at the corresponding boundaries.
enum UnicodeEvidenceSafetyCoordinatorV1 {
    static func validateWriterCommand(_ command: WorkspaceCommandV1) throws {
        do {
            let source = try WorkspaceMutationCanonicalV1.data(command)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let decoded = try decoder.decode(WorkspaceCommandV1.self, from: source)
            guard decoded == command else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            try UnicodeEvidenceSafetyV1.requireExactBytes(
                before: source,
                after: WorkspaceMutationCanonicalV1.data(decoded)
            )
        } catch let failure as WorkspaceMutationFailureV1 {
            throw failure
        } catch {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    static func validateJournalBatch(
        _ batch: ChangeBatchV1,
        limits: ChangeJournalLimitsV1
    ) throws {
        do {
            try batch.validate(limits: limits)
            let source = try batch.canonicalData(limits: limits)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let decoded = try decoder.decode(ChangeBatchV1.self, from: source)
            guard decoded == batch else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
            try UnicodeEvidenceSafetyV1.requireExactBytes(
                before: source,
                after: decoded.canonicalData(limits: limits)
            )
        } catch let failure as ChangeJournalFailureV1 {
            throw failure
        } catch {
            throw ChangeJournalFailureV1.tamperedBatch
        }
    }
}
