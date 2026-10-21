import CryptoKit
import Foundation

/// Backup envelope 5 changes transport only. Canonical checkpoint, mutation,
/// receipt and reversal bytes are opaque and never rewritten by this codec.
enum BackupRawDataWireV1 {
    static let backupSchemaVersion = 5
    static let rawPath = "records-data.bin"
    static let rawMIMEType = "application/octet-stream"

    enum HistoryField: String, CaseIterable, Hashable, Sendable {
        case envelopeData, receiptData, reversalBasisData, semanticReversalData
    }

    enum Slot: Hashable, Sendable {
        case fieldDraft(Int)
        case history(Int, HistoryField)

        init?(codingPath: [CodingKey]) {
            if codingPath.count == 3,
               codingPath[0].stringValue == "fieldDrafts",
               let index = codingPath[1].intValue, index >= 0,
               codingPath[2].stringValue == "canonicalData" {
                self = .fieldDraft(index)
            } else if codingPath.count == 4,
                      codingPath[0].stringValue == "mutationHistory",
                      codingPath[1].stringValue == "receipts",
                      let index = codingPath[2].intValue, index >= 0,
                      let field = HistoryField(rawValue: codingPath[3].stringValue) {
                self = .history(index, field)
            } else {
                return nil
            }
        }
    }

    struct Reference: Decodable, Equatable, Sendable {
        let offset: Int
        let count: Int

        private enum CodingKeys: String, CodingKey { case bytes = "$bytes" }

        init(offset: Int, count: Int) {
            self.offset = offset
            self.count = count
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var values = try container.nestedUnkeyedContainer(forKey: .bytes)
            offset = try values.decode(Int.self)
            count = try values.decode(Int.self)
            guard values.isAtEnd, offset >= 0, count >= 0 else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }

        var token: CanonicalJSONValueV1 {
            .object(["$bytes": .array([.integer(offset), .integer(count)])])
        }
    }

    struct Slots: Equatable, Sendable {
        let references: [Slot: Reference]
        let segments: [Data]
        let byteCount: Int
        let sha256: String

        init(records: V4BackupRecordsV1, maximumByteCount: Int64) throws {
            var references: [Slot: Reference] = [:]
            var segments: [Data] = []
            var byteCount = 0
            func append(_ data: Data, at slot: Slot) throws {
                let next = byteCount.addingReportingOverflow(data.count)
                guard !next.overflow, Int64(next.partialValue) <= min(maximumByteCount,
                    StreamingArchiveLimitsV1.card17.maximumUncompressedEntryByteCount),
                      references.updateValue(.init(offset: byteCount, count: data.count),
                                             forKey: slot) == nil else {
                    throw BackupCanonicalEncodingErrorV1.invalidRecords
                }
                segments.append(data)
                byteCount = next.partialValue
            }
            for (index, record) in records.fieldDrafts.enumerated() {
                try append(record.canonicalData, at: .fieldDraft(index))
            }
            for (index, record) in (records.mutationHistory?.receipts ?? []).enumerated() {
                try append(record.envelopeData, at: .history(index, .envelopeData))
                try append(record.receiptData, at: .history(index, .receiptData))
                if let data = record.reversalBasisData {
                    try append(data, at: .history(index, .reversalBasisData))
                }
                if let data = record.semanticReversalData {
                    try append(data, at: .history(index, .semanticReversalData))
                }
            }
            var digest = SHA256()
            for segment in segments { digest.update(data: segment) }
            self.references = references
            self.segments = segments
            self.byteCount = byteCount
            self.sha256 = digest.finalize().map { String(format: "%02x", $0) }.joined()
        }

        func token(for slot: Slot) throws -> CanonicalJSONValueV1 {
            guard let reference = references[slot] else {
                throw BackupCanonicalEncodingErrorV1.invalidRecords
            }
            return reference.token
        }

        func forEachChunk(_ consume: (Data) throws -> Void) throws {
            for segment in segments {
                var offset = 0
                while offset < segment.count {
                    let end = offset + min(64 * 1_024, segment.count - offset)
                    try segment.withUnsafeBytes { buffer in
                        guard let address = buffer.baseAddress else {
                            throw BackupCanonicalEncodingErrorV1.invalidRecords
                        }
                        try consume(Data(bytes: address.advanced(by: offset), count: end - offset))
                    }
                    offset = end
                }
            }
        }
    }

    struct Plan: Equatable, Sendable {
        let metadata: EncodedBackupJSONV1
        let slots: Slots

        init(metadata: EncodedBackupJSONV1, slots: Slots, maximumByteCount: Int64) throws {
            try BackupRawDataWireV1.validateCombinedByteCount(
                metadata: Int64(metadata.data.count), raw: Int64(slots.byteCount),
                maximum: maximumByteCount)
            self.metadata = metadata
            self.slots = slots
        }
    }

    /// The combined decoded records budget is NOT doubled by adding a member.
    static func validateCombinedByteCount(metadata: Int64, raw: Int64,
                                          maximum: Int64) throws {
        let total = metadata.addingReportingOverflow(raw)
        let effectiveMaximum = min(maximum,
            StreamingArchiveLimitsV1.card17.maximumUncompressedEntryByteCount)
        guard metadata >= 0, raw >= 0, effectiveMaximum >= 0, !total.overflow,
              total.partialValue <= effectiveMaximum else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
    }

    static func validateManifest(_ manifest: V4BackupManifestV1,
        maximumByteCount: Int64 = StreamingArchiveLimitsV1.card17.maximumUncompressedEntryByteCount
    ) throws {
        let raw = manifest.entries.filter { $0.path == rawPath }
        guard manifest.backupSchemaVersion == backupSchemaVersion else {
            guard raw.isEmpty else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            return
        }
        let metadata = manifest.entries.filter { $0.path == "records.json" }
        guard metadata.count == 1, raw.count == 1,
              let json = metadata.first, let bytes = raw.first,
              json.mimeType == "application/json", bytes.mimeType == rawMIMEType else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        try validateCombinedByteCount(metadata: Int64(json.byteCount), raw: Int64(bytes.byteCount),
                                      maximum: maximumByteCount)
    }

    /// Parse and validate EVERY range in explicit schema order before copying
    /// even one byte. JSONDecoder's Data callback order is deliberately irrelevant.
    static func references(metadata: Data, rawByteCount: Int,
                           maximumByteCount: Int64) throws -> [Slot: Reference] {
        try validateCombinedByteCount(metadata: Int64(metadata.count), raw: Int64(rawByteCount),
                                      maximum: maximumByteCount)
        let index = try JSONDecoder().decode(MetadataIndex.self, from: metadata)
        guard (index.fieldDrafts?.count ?? 0) <= 100_000,
              (index.mutationHistory?.receipts.count ?? 0)
                <= MutationJournalStoreV1.maximumReceiptValidationCount else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        var result: [Slot: Reference] = [:]
        var cursor = 0
        func append(_ reference: Reference, at slot: Slot) throws {
            let end = reference.offset.addingReportingOverflow(reference.count)
            guard reference.offset == cursor, reference.count >= 0, !end.overflow,
                  end.partialValue <= rawByteCount,
                  result.updateValue(reference, forKey: slot) == nil else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
            cursor = end.partialValue
        }
        for (position, record) in (index.fieldDrafts ?? []).enumerated() {
            try append(record.canonicalData, at: .fieldDraft(position))
        }
        for (position, record) in (index.mutationHistory?.receipts ?? []).enumerated() {
            try append(record.envelopeData, at: .history(position, .envelopeData))
            try append(record.receiptData, at: .history(position, .receiptData))
            if let reference = record.reversalBasisData {
                try append(reference, at: .history(position, .reversalBasisData))
            }
            if let reference = record.semanticReversalData {
                try append(reference, at: .history(position, .semanticReversalData))
            }
        }
        guard cursor == rawByteCount else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
        return result
    }

    private struct MetadataIndex: Decodable {
        struct Draft: Decodable { let canonicalData: Reference }
        struct History: Decodable {
            struct Receipt: Decodable {
                let envelopeData: Reference
                let receiptData: Reference
                let reversalBasisData: Reference?
                let semanticReversalData: Reference?
            }
            let receipts: [Receipt]
        }
        let fieldDrafts: [Draft]?
        let mutationHistory: History?
    }

    /// State is local to one synchronous decode. The lock also makes one-use
    /// accounting explicit should a Foundation callback ever be concurrent.
    final class Resolver: @unchecked Sendable {
        private let raw: Data
        private let references: [Slot: Reference]
        private var consumed = Set<Slot>()
        private let lock = NSLock()

        init(metadata: Data, raw: Data, maximumByteCount: Int64) throws {
            references = try BackupRawDataWireV1.references(
                metadata: metadata, rawByteCount: raw.count, maximumByteCount: maximumByteCount)
            self.raw = raw
        }

        func decode(_ decoder: Decoder) throws -> Data {
            guard let slot = Slot(codingPath: decoder.codingPath) else {
                let text = try decoder.singleValueContainer().decode(String.self)
                guard let value = Data(base64Encoded: text) else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
                return value
            }
            let reference = try Reference(from: decoder)
            lock.lock()
            let accepted = references[slot] == reference && consumed.insert(slot).inserted
            lock.unlock()
            guard accepted else { throw BackupCanonicalDecodingErrorV1.invalidRecords }
            if reference.count == 0 { return Data() }
            // Force an owned copy: a mapped Data or sharing slice must never
            // escape the synchronous held-file inspection through a decoded DTO.
            return try raw.withUnsafeBytes { buffer in
                guard let address = buffer.baseAddress else {
                    throw BackupCanonicalDecodingErrorV1.invalidRecords
                }
                return Data(bytes: address.advanced(by: reference.offset), count: reference.count)
            }
        }

        func validateComplete() throws {
            lock.lock()
            defer { lock.unlock() }
            guard consumed == Set(references.keys) else {
                throw BackupCanonicalDecodingErrorV1.invalidRecords
            }
        }
    }
}
