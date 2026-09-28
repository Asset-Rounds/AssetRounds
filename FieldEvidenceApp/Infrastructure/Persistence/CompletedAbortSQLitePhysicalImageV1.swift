#if DEBUG
import CryptoKit
import Darwin
import Foundation
import SQLite3

/// A page-complete view of a closed SQLite source. This is deliberately
/// independent of the rows that SwiftData happens to fetch: checkpointing may
/// move any committed WAL page into the main file, including freelist pages.
struct CompletedAbortSQLitePhysicalImageV1: Equatable {
    private let pageSize: Int
    private let basePages: [Data]
    private let committedPages: [Data]
    private let committedWALPageCandidates: [Int: Set<Data>]
    private let walHeader: Data?
    private let walFrames: [Data]

    private enum Invalid: Error { case physical }

    static func capture(model: Int32, wal: Int32?) throws -> Self {
        var modelStat = stat()
        guard Darwin.fstat(model, &modelStat) == 0,
              modelStat.st_mode & S_IFMT == S_IFREG,
              modelStat.st_size >= 512 else { throw Invalid.physical }
        let header = try read(model, at: 0, count: 100)
        guard header.count == 100,
              header.prefix(16) == Data("SQLite format 3\0".utf8) else {
            throw Invalid.physical
        }
        let encodedPageSize = Int(word16(header, 16))
        let pageSize = encodedPageSize == 1 ? 65_536 : encodedPageSize
        guard pageSize >= 512, pageSize <= 65_536,
              pageSize.nonzeroBitCount == 1,
              Int64(pageSize) <= modelStat.st_size,
              modelStat.st_size % Int64(pageSize) == 0,
              UInt64(modelStat.st_size) <= ScratchDataPurposeV1.source.maximumByteCount else {
            throw Invalid.physical
        }
        var base: [Data] = []
        base.reserveCapacity(Int(modelStat.st_size) / pageSize)
        for index in 0..<(Int(modelStat.st_size) / pageSize) {
            base.append(digest(try exactRead(model, at: Int64(index) * Int64(pageSize),
                                             count: pageSize)))
        }
        var committed = base
        var candidates: [Int: Set<Data>] = [:]
        var headerDigest: Data?
        var frameDigests: [Data] = []
        if let wal {
            var walStat = stat()
            guard Darwin.fstat(wal, &walStat) == 0,
                  walStat.st_mode & S_IFMT == S_IFREG,
                  walStat.st_size >= 0,
                  UInt64(walStat.st_size) <= ScratchDataPurposeV1.source.maximumByteCount else {
                throw Invalid.physical
            }
            if walStat.st_size > 0 {
                guard walStat.st_size >= 32 else { throw Invalid.physical }
                let walHeader = try exactRead(wal, at: 0, count: 32)
                let magic = word32(walHeader, 0)
                guard magic == 0x377f0682 || magic == 0x377f0683,
                      word32(walHeader, 4) == 3_007_000,
                      word32(walHeader, 8) == UInt32(pageSize) else {
                    throw Invalid.physical
                }
                let checksumBigEndian = magic == 0x377f0683
                var checksum = checksumWords(walHeader.prefix(24),
                    bigEndian: checksumBigEndian, initial: (0, 0))
                guard checksum.0 == word32(walHeader, 24),
                      checksum.1 == word32(walHeader, 28) else {
                    throw Invalid.physical
                }
                headerDigest = digest(walHeader)
                let frameSize = Int64(24 + pageSize)
                guard (walStat.st_size - 32) % frameSize == 0 else {
                    throw Invalid.physical
                }
                var pending: [Int: Data] = [:]
                var activePrefix = true
                let frameCount = Int((walStat.st_size - 32) / frameSize)
                frameDigests.reserveCapacity(frameCount)
                for index in 0..<frameCount {
                    let bytes = try exactRead(wal,
                        at: 32 + Int64(index) * frameSize,
                        count: Int(frameSize))
                    frameDigests.append(digest(bytes))
                    if !activePrefix { continue }
                    // Old frames after a WAL reset have different salts and
                    // are never part of SQLite's current committed frontier.
                    if word32(bytes, 8) != word32(walHeader, 16) ||
                       word32(bytes, 12) != word32(walHeader, 20) {
                        activePrefix = false
                        continue
                    }
                    let pageNumber = word32(bytes, 0)
                    guard pageNumber > 0,
                          pageNumber <= UInt32(ScratchDataPurposeV1.source.maximumByteCount /
                                               UInt64(pageSize)) else {
                        throw Invalid.physical
                    }
                    checksum = checksumWords(bytes.prefix(8),
                        bigEndian: checksumBigEndian, initial: checksum)
                    checksum = checksumWords(bytes.dropFirst(24),
                        bigEndian: checksumBigEndian, initial: checksum)
                    guard checksum.0 == word32(bytes, 16),
                          checksum.1 == word32(bytes, 20) else {
                        throw Invalid.physical
                    }
                    let pageIndex = Int(pageNumber - 1)
                    pending[pageIndex] = digest(bytes.dropFirst(24))
                    let commitPages = word32(bytes, 4)
                    if commitPages > 0 {
                        guard commitPages <= UInt32(
                            ScratchDataPurposeV1.source.maximumByteCount / UInt64(pageSize))
                        else { throw Invalid.physical }
                        let count = Int(commitPages)
                        if committed.count < count {
                            committed.append(contentsOf: repeatElement(Data(), count: count - committed.count))
                        } else if committed.count > count {
                            committed.removeLast(committed.count - count)
                        }
                        for (page, hash) in pending {
                            guard page < count else { throw Invalid.physical }
                            committed[page] = hash
                            candidates[page, default: []].insert(hash)
                        }
                        pending.removeAll(keepingCapacity: true)
                    }
                }
            }
        }
        guard committed.allSatisfy({ !$0.isEmpty }) else { throw Invalid.physical }
        return Self(pageSize: pageSize, basePages: base,
                    committedPages: committed,
                    committedWALPageCandidates: candidates,
                    walHeader: headerDigest, walFrames: frameDigests)
    }

    /// A clean close may checkpoint authenticated committed WAL pages and
    /// truncate the WAL. It cannot invent a new page image or rewrite a
    /// surviving frame. The full committed page vector includes freelist and
    /// otherwise unfetched pages, not merely application rows.
    func requireOwnedCloseTransition(to after: Self) throws {
        guard pageSize == after.pageSize,
              committedPages == after.committedPages else {
            throw Invalid.physical
        }
        for (index, page) in after.basePages.enumerated() {
            if index < basePages.count && page == basePages[index] { continue }
            guard committedWALPageCandidates[index]?.contains(page) == true else {
                throw Invalid.physical
            }
        }
        if let afterHeader = after.walHeader {
            guard afterHeader == walHeader,
                  after.walFrames.count <= walFrames.count,
                  Array(walFrames.prefix(after.walFrames.count)) == after.walFrames else {
                throw Invalid.physical
            }
        }
    }

    /// Run on the bounded private copy only. SQLite's full integrity check
    /// validates B-trees, indexes, missing/surplus pages and the freelist;
    /// foreign-key check covers relationships not diagnosed by that pragma.
    @MainActor
    static func requireFullIntegrity(at modelURL: URL) throws {
        var connection: OpaquePointer?
        let opened = modelURL.path.withCString {
            sqlite3_open_v2($0, &connection,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        }
        guard opened == SQLITE_OK, let connection else {
            if let connection {
                if sqlite3_close(connection) != SQLITE_OK {
                    retainedUncertainConnections.append(connection)
                }
            }
            throw Invalid.physical
        }
        var closeAttempted = false
        defer {
            if !closeAttempted {
                if sqlite3_close(connection) != SQLITE_OK {
                    retainedUncertainConnections.append(connection)
                }
            }
        }
        try requireSingleOKRow("PRAGMA main.integrity_check", connection: connection)
        try requireNoRows("PRAGMA main.foreign_key_check", connection: connection)
        closeAttempted = true
        guard sqlite3_close(connection) == SQLITE_OK else {
            retainedUncertainConnections.append(connection)
            throw Invalid.physical
        }
    }

    @MainActor private static var retainedUncertainConnections: [OpaquePointer] = []

    @MainActor
    private static func requireSingleOKRow(_ sql: String,
        connection: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw Invalid.physical }
        var rows = 0
        var valid = true
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { valid = false; break }
            rows += 1
            guard rows == 1, let value = sqlite3_column_text(statement, 0),
                  sqlite3_column_bytes(statement, 0) == 2,
                  value[0] == 111, value[1] == 107 else {
                valid = false
                break
            }
        }
        let finalized = sqlite3_finalize(statement)
        guard valid, rows == 1, finalized == SQLITE_OK else {
            throw Invalid.physical
        }
    }

    @MainActor
    private static func requireNoRows(_ sql: String,
        connection: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw Invalid.physical }
        let result = sqlite3_step(statement)
        let finalized = sqlite3_finalize(statement)
        guard result == SQLITE_DONE, finalized == SQLITE_OK else {
            throw Invalid.physical
        }
    }

    private static func digest<S: DataProtocol>(_ bytes: S) -> Data {
        Data(SHA256.hash(data: Data(bytes)))
    }

    private static func word16(_ bytes: Data, _ offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func word32(_ bytes: Data, _ offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16) |
        (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    private static func checksumWords<S: DataProtocol>(_ bytes: S,
        bigEndian: Bool, initial: (UInt32, UInt32)) -> (UInt32, UInt32) {
        let values = Array(bytes)
        var state = initial
        for offset in stride(from: 0, to: values.count, by: 8) {
            let a = bigEndian
                ? (UInt32(values[offset]) << 24 | UInt32(values[offset + 1]) << 16 |
                   UInt32(values[offset + 2]) << 8 | UInt32(values[offset + 3]))
                : (UInt32(values[offset + 3]) << 24 | UInt32(values[offset + 2]) << 16 |
                   UInt32(values[offset + 1]) << 8 | UInt32(values[offset]))
            let b = bigEndian
                ? (UInt32(values[offset + 4]) << 24 | UInt32(values[offset + 5]) << 16 |
                   UInt32(values[offset + 6]) << 8 | UInt32(values[offset + 7]))
                : (UInt32(values[offset + 7]) << 24 | UInt32(values[offset + 6]) << 16 |
                   UInt32(values[offset + 5]) << 8 | UInt32(values[offset + 4]))
            state.0 = state.0 &+ a &+ state.1
            state.1 = state.1 &+ b &+ state.0
        }
        return state
    }

    private static func exactRead(_ descriptor: Int32,
        at offset: Int64, count: Int) throws -> Data {
        let value = try read(descriptor, at: offset, count: count)
        guard value.count == count else { throw Invalid.physical }
        return value
    }

    private static func read(_ descriptor: Int32,
        at offset: Int64, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, count <= 65_560 else {
            throw Invalid.physical
        }
        var bytes = [UInt8](repeating: 0, count: count)
        var readCount = 0
        while readCount < count {
            let amount = bytes.withUnsafeMutableBytes { raw in
                Darwin.pread(descriptor, raw.baseAddress!.advanced(by: readCount),
                             count - readCount, offset + Int64(readCount))
            }
            if amount == 0 { break }
            if amount < 0 && errno == EINTR { continue }
            guard amount > 0 else { throw Invalid.physical }
            readCount += amount
        }
        return Data(bytes.prefix(readCount))
    }
}
#endif
