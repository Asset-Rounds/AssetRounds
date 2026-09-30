import Darwin
import Foundation
import CryptoKit

#if DEBUG
/// Serializes policy prose within this process. XCTest owns other console
/// producers, so strict Simulator disposition records use a separate journal.
final class ProtectedFileDiagnosticWriterV1: @unchecked Sendable {
    private let lock = NSLock()
    private let fileHandle: FileHandle

    init(fileHandle: FileHandle) { self.fileHandle = fileHandle }

    func write(_ facts: String) {
        lock.lock()
        defer { lock.unlock() }
        fileHandle.write(Data(facts.utf8))
    }
}
#endif

#if DEBUG && os(iOS) && targetEnvironment(simulator)
enum ProtectedFileDiagnosticTransportErrorV1: Error, Equatable {
    case unavailable
    case unsafeJournal
    case invalidPayload
    case appendFailed
    case synchronizeFailed
    case poisonedStream
}

/// Diagnostic transport only. Its private process stream never supplies file
/// protection authority, and a failed write cannot authorize an unsupported result.
final class ProtectedFileSimulatorDiagnosticJournalV1: @unchecked Sendable {
    private let lock = NSLock()
    private let cachesURL: URL?
    private var streamID: UUID
    private let nextStreamID: @Sendable () -> UUID
    private let framesPerStream: Int
    private let maximumStreams: Int
    private let maximumTotalBytes: Int64
    private let append: @Sendable (Int32, Data) throws -> Void
    private let synchronize: @Sendable (Int32) throws -> Void
    private var cachesDescriptor: Int32 = -1
    private var directoryDescriptor: Int32 = -1
    private var fileDescriptor: Int32 = -1
    private var sequence = 0
    private var byteCount: Int64 = 0
    private var totalByteCount: Int64 = 0
    private var streamCount = 0
    private var poisoned = false
    private static let directoryName = "AssetRoundsNativeDiagnostics"

    init(
        cachesURL: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
        streamID: UUID = UUID(),
        nextStreamID: @escaping @Sendable () -> UUID = { UUID() },
        framesPerStream: Int = 100_000,
        maximumStreams: Int = 64,
        maximumTotalBytes: Int64 = 1_024 * 1_024 * 1_024,
        append: @escaping @Sendable (Int32, Data) throws -> Void = { descriptor, data in
            let written = data.withUnsafeBytes { bytes in
                Darwin.write(descriptor, bytes.baseAddress, bytes.count)
            }
            guard written == data.count else { throw ProtectedFileDiagnosticTransportErrorV1.appendFailed }
        },
        synchronize: @escaping @Sendable (Int32) throws -> Void = { descriptor in
            guard Darwin.fsync(descriptor) == 0 else {
                throw ProtectedFileDiagnosticTransportErrorV1.synchronizeFailed
            }
        }
    ) {
        self.cachesURL = cachesURL
        self.streamID = streamID
        self.nextStreamID = nextStreamID
        self.framesPerStream = framesPerStream
        self.maximumStreams = maximumStreams
        self.maximumTotalBytes = maximumTotalBytes
        self.append = append
        self.synchronize = synchronize
    }

    deinit {
        if fileDescriptor >= 0 { Darwin.close(fileDescriptor) }
        if directoryDescriptor >= 0 { Darwin.close(directoryDescriptor) }
        if cachesDescriptor >= 0 { Darwin.close(cachesDescriptor) }
    }

    func write(_ payload: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !poisoned else { throw ProtectedFileDiagnosticTransportErrorV1.poisonedStream }
        do {
            guard !payload.isEmpty, payload.count <= 4_096,
                  payload.last == 10,
                  !payload.dropLast().contains(10), !payload.contains(13),
                  String(data: payload, encoding: .utf8) != nil,
                  (1...100_000).contains(framesPerStream),
                  (1...64).contains(maximumStreams),
                  (1...(1_024 * 1_024 * 1_024)).contains(maximumTotalBytes) else {
                throw ProtectedFileDiagnosticTransportErrorV1.invalidPayload
            }
            if fileDescriptor < 0 { try openJournal() }
            try verifyJournal()
            if sequence == framesPerStream { try rotateStream() }
            let next = sequence + 1
            var frame = try JSONSerialization.data(withJSONObject: [
                "schema": "v23-simulator-file-protection-frame-v1",
                "streamID": streamID.uuidString.lowercased(),
                "sequence": next,
                "payloadBase64": payload.base64EncodedString(),
                "payloadByteCount": payload.count,
                "payloadSHA256": KernelCanonicalHashV1.sha256(payload).uppercased(),
            ], options: [.sortedKeys, .withoutEscapingSlashes])
            frame.append(10)
            guard frame.count <= 8_192,
                  totalByteCount <= maximumTotalBytes - Int64(frame.count) else {
                throw ProtectedFileDiagnosticTransportErrorV1.invalidPayload
            }
            try append(fileDescriptor, frame)
            byteCount += Int64(frame.count)
            totalByteCount += Int64(frame.count)
            try synchronize(fileDescriptor)
            try verifyJournal()
            sequence = next
        } catch {
            poisoned = true
            throw error
        }
    }

    private var fileName: String { streamID.uuidString.lowercased() + ".jsonl" }

    private func openJournal() throws {
        guard let cachesURL, cachesURL.isFileURL else {
            throw ProtectedFileDiagnosticTransportErrorV1.unavailable
        }
        cachesDescriptor = Darwin.open(cachesURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard cachesDescriptor >= 0 else { throw ProtectedFileDiagnosticTransportErrorV1.unsafeJournal }
        let created = Darwin.mkdirat(cachesDescriptor, Self.directoryName, mode_t(0o700))
        guard created == 0 || errno == EEXIST else {
            throw ProtectedFileDiagnosticTransportErrorV1.unavailable
        }
        directoryDescriptor = Darwin.openat(cachesDescriptor, Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryDescriptor >= 0 else { throw ProtectedFileDiagnosticTransportErrorV1.unsafeJournal }
        try openStream()
    }

    private func openStream() throws {
        guard streamCount < maximumStreams else {
            throw ProtectedFileDiagnosticTransportErrorV1.invalidPayload
        }
        fileDescriptor = Darwin.openat(directoryDescriptor, fileName,
            O_WRONLY | O_APPEND | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fileDescriptor >= 0 else { throw ProtectedFileDiagnosticTransportErrorV1.unsafeJournal }
        streamCount += 1
        try verifyJournal()
    }

    /// Keep the complete synchronized old stream for the existing collector.
    /// A fresh exclusive file has its own sequence; no prior record is rewritten.
    private func rotateStream() throws {
        guard streamCount < maximumStreams else {
            throw ProtectedFileDiagnosticTransportErrorV1.invalidPayload
        }
        try verifyJournal()
        let previousDescriptor = fileDescriptor
        fileDescriptor = -1
        guard Darwin.close(previousDescriptor) == 0 else {
            throw ProtectedFileDiagnosticTransportErrorV1.unsafeJournal
        }
        streamID = nextStreamID()
        sequence = 0
        byteCount = 0
        try openStream()
    }

    private func verifyJournal() throws {
        var directory = stat(), namedDirectory = stat(), file = stat(), namedFile = stat()
        guard Darwin.fstat(directoryDescriptor, &directory) == 0,
              Darwin.fstatat(cachesDescriptor, Self.directoryName, &namedDirectory, AT_SYMLINK_NOFOLLOW) == 0,
              directory.st_mode & S_IFMT == S_IFDIR,
              namedDirectory.st_mode & S_IFMT == S_IFDIR,
              directory.st_dev == namedDirectory.st_dev, directory.st_ino == namedDirectory.st_ino,
              Darwin.fstat(fileDescriptor, &file) == 0,
              Darwin.fstatat(directoryDescriptor, fileName, &namedFile, AT_SYMLINK_NOFOLLOW) == 0,
              file.st_mode & S_IFMT == S_IFREG, namedFile.st_mode & S_IFMT == S_IFREG,
              file.st_nlink == 1, namedFile.st_nlink == 1,
              file.st_dev == namedFile.st_dev, file.st_ino == namedFile.st_ino,
              file.st_size == byteCount, namedFile.st_size == byteCount else {
            throw ProtectedFileDiagnosticTransportErrorV1.unsafeJournal
        }
    }
}

/// Owner decision 15 (2026-09-25) summarizes the per-call journal to cut DEBUG test time.
/// An unsupported disposition payload is a pure function of its file kind. The first one of
/// each kind is written and synchronized before its call returns, exactly as before. Later
/// ones are counted and written as one summary frame per kind: once `flushOccurrences` calls
/// are pending or `flushIntervalNanoseconds` has passed, from a repeating timer, and at exit.
/// Diagnostic transport only. A transport failure fails the call that meets it and is named
/// on the policy writer; every later unsupported result then fails, so a failed write still
/// never authorizes one.
final class ProtectedFileSimulatorDiagnosticSummaryV1: @unchecked Sendable {
    static let marker = "V23_SIMULATOR_FILE_PROTECTION_DIAGNOSTIC_SUMMARY_V1"
    private let lock = NSLock()
    private let journal: ProtectedFileSimulatorDiagnosticJournalV1
    private let report: @Sendable (String) -> Void
    private let flushOccurrences: Int
    private let flushIntervalNanoseconds: UInt64
    private let startsTimer: Bool
    private let now: @Sendable () -> UInt64
    private var exactPayloads: [OwnedFileKindV1: Data] = [:]
    private var pending: [OwnedFileKindV1: Int] = [:]
    private var pendingTotal = 0
    private var lastFlushNanoseconds: UInt64
    private var poisoned = false
    private var timer: DispatchSourceTimer?

    init(
        journal: ProtectedFileSimulatorDiagnosticJournalV1,
        report: @escaping @Sendable (String) -> Void,
        flushOccurrences: Int = 4_096,
        flushIntervalNanoseconds: UInt64 = 10_000_000_000,
        startsTimer: Bool = false,
        now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.journal = journal
        self.report = report
        self.flushOccurrences = max(1, flushOccurrences)
        self.flushIntervalNanoseconds = max(1, flushIntervalNanoseconds)
        self.startsTimer = startsTimer
        self.now = now
        lastFlushNanoseconds = now()
    }

    deinit { timer?.cancel() }

    func record(_ kind: OwnedFileKindV1, payload: () -> Data) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !poisoned else { throw ProtectedFileDiagnosticTransportErrorV1.poisonedStream }
        do {
            guard exactPayloads[kind] != nil else {
                let exact = payload()
                try journal.write(exact)
                exactPayloads[kind] = exact
                return
            }
            pending[kind, default: 0] += 1
            pendingTotal += 1
            if startsTimer && timer == nil { startTimer() }
            if pendingTotal >= flushOccurrences
                || now() &- lastFlushNanoseconds >= flushIntervalNanoseconds {
                try flushLocked()
            }
        } catch {
            fail(error, phase: "record")
            throw error
        }
    }

    /// A flush that no caller waits on (the timer and process exit). Its failure is named on
    /// the writer, and the next unsupported result fails with `poisonedStream`.
    func flush(phase: String, waitsForLock: Bool = true) {
        if waitsForLock { lock.lock() } else if !lock.try() { return }
        defer { lock.unlock() }
        guard !poisoned else { return }
        do { try flushLocked() } catch { fail(error, phase: phase) }
    }

    private func flushLocked() throws {
        lastFlushNanoseconds = now()
        for kind in OwnedFileKindV1.allCases {
            guard let count = pending[kind], count > 0, let exact = exactPayloads[kind] else { continue }
            try journal.write(Self.summaryPayload(exact, occurrences: count))
            pending[kind] = nil
            pendingTotal -= count
        }
    }

    /// The exact payload's fields in their order, under the summary marker, plus the count.
    static func summaryPayload(_ exact: Data, occurrences: Int) throws -> Data {
        guard occurrences > 0, exact.last == 10, let space = exact.firstIndex(of: 32) else {
            throw ProtectedFileDiagnosticTransportErrorV1.invalidPayload
        }
        var summary = Data(marker.utf8)
        summary.append(exact[space..<exact.index(before: exact.endIndex)])
        summary.append(Data(" occurrences=\(occurrences)\n".utf8))
        return summary
    }

    private func fail(_ error: Error, phase: String) {
        poisoned = true
        timer?.cancel()
        report("V23_PROTECTED_FILE_DIAGNOSTIC_JOURNAL_FAILURE phase=\(phase) error=\(error)"
            + " unjournaledOccurrences=\(pendingTotal)\n")
    }

    private func startTimer() {
        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(deadline: .now() + .nanoseconds(Int(flushIntervalNanoseconds)),
                        repeating: .nanoseconds(Int(flushIntervalNanoseconds)))
        source.setEventHandler { [weak self] in self?.flush(phase: "timer") }
        timer = source
        source.resume()
    }
}

/// Development timing only. It aggregates the cost of the Simulator fallback
/// path and never participates in a verification or evidence decision.
final class ProtectedFileSimulatorTimingV1: @unchecked Sendable {
    private let lock = NSLock()
    private let writer: ProtectedFileDiagnosticWriterV1
    private let temporaryPrefix: String
    private let applicationSupportPrefix: String?
    private var calls = 0
    private var fallbackNanoseconds: UInt64 = 0
    private var journalNanoseconds: UInt64 = 0
    private var temporaryCalls = 0
    private var applicationSupportCalls = 0
    private var lastEmitNanoseconds: UInt64

    init(writer: ProtectedFileDiagnosticWriterV1) {
        self.writer = writer
        temporaryPrefix = FileManager.default.temporaryDirectory.standardizedFileURL.path
        applicationSupportPrefix = FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask).first?.standardizedFileURL.path
        lastEmitNanoseconds = DispatchTime.now().uptimeNanoseconds
    }

    func recordFallback(at url: URL, startedAt start: UInt64) {
        let current = DispatchTime.now().uptimeNanoseconds
        let elapsed = current &- start
        let path = url.standardizedFileURL.path
        lock.lock()
        calls += 1
        fallbackNanoseconds &+= elapsed
        if path.hasPrefix(temporaryPrefix) {
            temporaryCalls += 1
        } else if let applicationSupportPrefix, path.hasPrefix(applicationSupportPrefix) {
            applicationSupportCalls += 1
        }
        // Emit on a call count or a 30-second interval so an interrupted test keeps recent totals.
        let due = calls % 2_000 == 0 || current &- lastEmitNanoseconds >= 30_000_000_000
        if due { lastEmitNanoseconds = current }
        let line = due ? summary(uptimeNanoseconds: current) : nil
        lock.unlock()
        if let line { writer.write(line) }
    }

    func recordJournal(startedAt start: UInt64) {
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start
        lock.lock()
        journalNanoseconds &+= elapsed
        lock.unlock()
    }

    private func summary(uptimeNanoseconds: UInt64) -> String {
        "V23_PROTECTED_FILE_TIMING_V1 calls=\(calls)"
            + " fallbackMs=\(fallbackNanoseconds / 1_000_000)"
            + " journalMs=\(journalNanoseconds / 1_000_000)"
            + " temporaryCalls=\(temporaryCalls)"
            + " applicationSupportCalls=\(applicationSupportCalls)"
            + " otherCalls=\(calls - temporaryCalls - applicationSupportCalls)"
            + " uptimeMs=\(uptimeNanoseconds / 1_000_000)\n"
    }
}
#endif

enum C50IncumbentFileExchangeProtectedFileBoundaryV1 {
    static let copiedSourceKind: OwnedFileKindV1 = .temporaryFile
    static let mappingScratchKind: OwnedFileKindV1 = .scratch
    static let quarantineKind: OwnedFileKindV1 = .scratch
    static let persistsSecurityScopedBookmarks = false
    static let externalSourceAndExportFilesAreAppOwned = false

    static func validate() -> Bool {
        ProtectedFilePolicyV1.isExcludedFromBackup(for: copiedSourceKind)
            && ProtectedFilePolicyV1.isExcludedFromBackup(for: mappingScratchKind)
            && ProtectedFilePolicyV1.isExcludedFromBackup(for: quarantineKind)
            && !persistsSecurityScopedBookmarks
            && !externalSourceAndExportFilesAreAppOwned
    }
}

enum EvidenceContextProtectedFilePolicyV1{static let durableRowNames:Set<String>=["EvidenceContextRow","PairedObservationLinkRow"];static let ownsExternalFiles=false;static let canonicalBytesRemainInProtectedDatabase=true}
enum LightingProtectedFilePolicyV1{static let durableRowNames:Set<String>=["LightingSystemRow","LightingObservationRow","LightingIssueRow","MeasurementPlanRow","LightingClaimStateRow"];static let ownsExternalFiles=false;static let canonicalBytesRemainInProtectedDatabase=true}
enum TemporalEvidenceProtectedFilePolicyV1 {
    static let durableRowNames: Set<String> = ["TemporalEvidenceClipRow", "TimecodedEvidenceAnchorRow"]
    static let originalContentFileKind: OwnedFileKindV1 = .mediaOriginal
    static let originalBytesAreCanonicalAndIncludedInBackup = true
    static let derivativesRemainRegenerable = true

    static func validate() throws {
        guard durableRowNames == Set(TemporalEvidencePersistenceEnrollmentV1.persistentFamilies),
              !ProtectedFilePolicyV1.isExcludedFromBackup(for: originalContentFileKind),
              originalBytesAreCanonicalAndIncludedInBackup,
              derivativesRemainRegenerable else {
            throw ProtectedFilePolicyError.invalidType
        }
    }
}

/// The closed set of app-owned file classes that may be passed to the
/// persistence protection policy.  Keeping this list closed prevents a new
/// writer from silently inheriting the wrong backup disposition.
enum OwnedFileKindV1: String, CaseIterable, Equatable, Hashable, Sendable {
    case durableDirectory
    case stagingDirectory
    case restoreStaging
    case stagingFile
    case fieldDraftStagingFile
    case temporaryFile
    case database
    case databaseWAL
    case databaseSHM
    case generationPointer
    case generationPointerTemporary
    case generationLeaseDirectory
    case generationLeaseControl
    case generationLeaseControlTemporary
    case generationLeaseOwnerLock
    case journal
    case journalTemporary
    case mediaOriginal
    case mediaThumbnail
    case reportSnapshot
    case reportPDF
    case diagnostics
    case sceneNavigation
    case commerceEntitlementCache
    case portableExchangeDirectory
    case portableExchangeSessionFile
    case portableExchangeJournalFile
    case portableExchangeQuarantineFile
    case cache
    case scratch
    case searchIndex
}

enum PlanProtectedFileBoundaryV1 {
    static let ownsExternalFiles = false
    static let canonicalRowsUseProtectedDatabase = true
    static let sourceContentRemainsUnderExistingContentAuthority = true
}
enum PlacementPoseProtectedFileBoundaryV1{static let ownsExternalFiles=false;static let durableBytesAreSwiftDataRows=true;static let derivedTipsAreDisposable=true}

struct OwnedFileProtectionDispositionV1: Equatable, Sendable {
    let expectsDirectory: Bool
    let isExcludedFromBackup: Bool
}

enum ProtectedFilePolicyError: Error, Equatable, Sendable {
    case invalidURL
    case invalidRelativePath
    case missing
    case symbolicLink
    case invalidType
    case hardLink
    case identityChanged
    case attributeWriteFailed
    case resourceValueMismatch
    case protectedDataUnavailable
}

enum ProtectedFileVerificationDispositionV1: Equatable, Sendable {
    case verifiedComplete
    case simulatorFileProtectionUnsupported
}

/// Applies the one protection/backup policy used by all persistence writers.
///
/// The URL operations are deliberately paired with a caller-supplied
/// descriptor-authority closure.  Descriptor owners can verify their pinned
/// ancestors immediately before and after the URL operation without replacing
/// their existing O_NOFOLLOW/inode checks with path-only authority.
enum ProtectedFilePolicyV1 {
    static let requiredFileProtection: FileProtectionType = .complete
    #if DEBUG
    private static let diagnosticWriter = ProtectedFileDiagnosticWriterV1(fileHandle: .standardError)

    fileprivate static func emitResourceValueMismatchSource(_ source: StaticString) {
        diagnosticWriter.write("ProtectedFilePolicy resource-value-mismatch-source=\(source)\n")
    }
    #endif

    #if DEBUG && os(iOS) && targetEnvironment(simulator)
    private static let diagnosticJournal = ProtectedFileSimulatorDiagnosticJournalV1()
    private static let simulatorTiming = ProtectedFileSimulatorTimingV1(writer: diagnosticWriter)
    private static let diagnosticSummary: ProtectedFileSimulatorDiagnosticSummaryV1 = {
        let summary = ProtectedFileSimulatorDiagnosticSummaryV1(journal: diagnosticJournal,
            report: { diagnosticWriter.write($0) }, startsTimer: true)
        atexit { ProtectedFilePolicyV1.flushDiagnosticSummaryAtExit() }
        return summary
    }()

    /// Never waits at exit: a lock held by another thread leaves its counts unjournaled.
    private static func flushDiagnosticSummaryAtExit() {
        diagnosticSummary.flush(phase: "exit", waitsForLock: false)
    }
    #endif

    /// C27 adds database rows only. Locator representations are references,
    /// never authority for creating a new app-owned file class.
    static func validateAssetLocatorPersistencePosture() throws {
        guard disposition(for: .database).isExcludedFromBackup == false,
              disposition(for: .journal).isExcludedFromBackup else {
            #if DEBUG
            emitResourceValueMismatchSource("asset-locator-posture")
            #endif
            throw ProtectedFilePolicyError.resourceValueMismatch
        }
    }
    static func validateSchedulePersistencePosture() throws {
        guard disposition(for: .database).isExcludedFromBackup == false,
              disposition(for: .journal).isExcludedFromBackup,
              C51ScheduleBackupClosureV1.embeddedCanonicalComponents.count == 6,
              !C51ScheduleBackupClosureV1.derivedDueReminderAndPreviewStateIsArchived else {
            #if DEBUG
            emitResourceValueMismatchSource("schedule-posture")
            #endif
            throw ProtectedFilePolicyError.resourceValueMismatch
        }
    }
    static func validateSceneNavigationPosture() throws {
        guard C34SceneNavigationDeviceLifecycleBoundaryV1.validate(),
              disposition(for: .sceneNavigation)
                == .init(expectsDirectory: false, isExcludedFromBackup: true) else {
            #if DEBUG
            emitResourceValueMismatchSource("scene-navigation-posture")
            #endif
            throw ProtectedFilePolicyError.resourceValueMismatch
        }
    }

    /// Recoverability verification stages only under the existing disposable
    /// staging policy. The opaque locator never creates a new durable file
    /// class or a second archive/store authority.
    static func protectRecoverabilityVerificationStagingDirectory(
        at url: URL,
        authorityCheck: () throws -> Void = {}
    ) throws {
        try applyAndVerify(.stagingDirectory, at: url, authorityCheck: authorityCheck)
    }

    static func isProtectedDataUnavailable(_ error: Error) -> Bool {
        if let policyError = error as? ProtectedFilePolicyError {
            return policyError == .protectedDataUnavailable
        }
        return mapWriteError(error) == .protectedDataUnavailable
    }

    static func isExcludedFromBackup(for kind: OwnedFileKindV1) -> Bool {
        disposition(for: kind).isExcludedFromBackup
    }

    /// Every closed file kind remains part of owned-byte accounting even when
    /// it is excluded from filesystem backup or portable export.
    static func countsTowardOwnedStorage(_ kind: OwnedFileKindV1) -> Bool {
        OwnedFileKindV1.allCases.contains(kind)
    }

    /// Storage pressure is an admission signal, never deletion authority.
    static func permitsAutomaticStoragePressureDeletion(
        _: OwnedFileKindV1
    ) -> Bool {
        false
    }

    static func disposition(
        for kind: OwnedFileKindV1
    ) -> OwnedFileProtectionDispositionV1 {
        switch kind {
        case .durableDirectory,
             .database,
             .databaseWAL,
             .databaseSHM,
             .generationPointer,
             .mediaOriginal,
             .mediaThumbnail,
             .reportSnapshot,
             .reportPDF:
            return OwnedFileProtectionDispositionV1(
                expectsDirectory: kind == .durableDirectory,
                isExcludedFromBackup: false
            )
        case .stagingDirectory,
             .restoreStaging,
             .generationLeaseDirectory,
             .portableExchangeDirectory,
             .cache,
             .scratch:
            return OwnedFileProtectionDispositionV1(
                expectsDirectory: true,
                isExcludedFromBackup: true
            )
        case .stagingFile,
             .fieldDraftStagingFile,
             .temporaryFile,
             .generationPointerTemporary,
             .generationLeaseControl,
             .generationLeaseControlTemporary,
             .generationLeaseOwnerLock,
             .journal,
             .journalTemporary,
             .diagnostics,
             .sceneNavigation,
             .commerceEntitlementCache,
             .portableExchangeSessionFile,
             .portableExchangeJournalFile,
             .portableExchangeQuarantineFile,
             .searchIndex:
            return OwnedFileProtectionDispositionV1(
                expectsDirectory: false,
                isExcludedFromBackup: true
            )
        }
    }

    @discardableResult
    static func applyAndVerify(
        _ kind: OwnedFileKindV1,
        at url: URL,
        authorityCheck: () throws -> Void = {}
    ) throws -> ProtectedFileVerificationDispositionV1 {
        let result = try applyAndVerifyResult(kind, at: url, authorityCheck: authorityCheck)
        try emitVerificationDisposition(result, kind: kind)
        return result
    }

    private static func applyAndVerifyResult(
        _ kind: OwnedFileKindV1,
        at url: URL,
        authorityCheck: () throws -> Void
    ) throws -> ProtectedFileVerificationDispositionV1 {
        let disposition = disposition(for: kind)
        try authorityCheck()
        let before = try pin(kind, at: url, disposition: disposition)

        #if DEBUG && os(iOS) && targetEnvironment(simulator)
        let beforeRequest = independentProtectionReadback(at: url)
        #endif
        #if DEBUG
        var afterProtection: DirectoryProtectionReadback?
        var afterBackup: DirectoryProtectionReadback?
        #endif
        do {
            try (url as NSURL).setResourceValue(
                URLFileProtection.complete,
                forKey: .fileProtectionKey
            )
            #if DEBUG
            if disposition.expectsDirectory {
                afterProtection = independentProtectionReadback(at: url)
            }
            #endif

            // Rewriting the same backup exclusion can change directory ctime,
            // invalidating a caller's unchanged-source witness. Read fresh
            // metadata and write only when the requested value is not present.
            // The complete-protection request above and full verification below
            // still occur on every call.
            var backupReadURL = URL(fileURLWithPath: url.path)
            backupReadURL.removeAllCachedResourceValues()
            let backupReadback = try backupReadURL.resourceValues(
                forKeys: [.isExcludedFromBackupKey]
            ).isExcludedFromBackup
            if backupReadback != disposition.isExcludedFromBackup {
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = disposition.isExcludedFromBackup
                var resourceURL = url
                try resourceURL.setResourceValues(resourceValues)
            }
            #if DEBUG
            if disposition.expectsDirectory {
                afterBackup = independentProtectionReadback(at: url)
            }
            #endif
        } catch {
            throw mapWriteError(error)
        }

        try authorityCheck()
        let after = try pin(kind, at: url, disposition: disposition)
        guard before == after else {
            throw ProtectedFilePolicyError.identityChanged
        }
        let result: ProtectedFileVerificationDispositionV1
        #if DEBUG && os(iOS) && targetEnvironment(simulator)
        do {
            result = try verifySimulatorResourceValues(kind, at: url, disposition: disposition,
                identity: before, successfulRequestReadback: beforeRequest)
        } catch {
            if (error as? ProtectedFilePolicyError) == .resourceValueMismatch {
                emitDirectoryProtectionReadback(kind: kind, at: url,
                    phase: "afterProtection", readback: afterProtection)
                emitDirectoryProtectionReadback(kind: kind, at: url,
                    phase: "afterBackup", readback: afterBackup)
                emitDirectoryProtectionReadback(kind: kind, at: url,
                    phase: "finalMismatch", readback: independentProtectionReadback(at: url))
            }
            throw error
        }
        #elseif DEBUG
        do {
            try verifyResourceValues(at: url, disposition: disposition)
        } catch {
            if (error as? ProtectedFilePolicyError) == .resourceValueMismatch {
                emitDirectoryProtectionReadback(kind: kind, at: url,
                    phase: "afterProtection", readback: afterProtection)
                emitDirectoryProtectionReadback(kind: kind, at: url,
                    phase: "afterBackup", readback: afterBackup)
                emitDirectoryProtectionReadback(kind: kind, at: url,
                    phase: "finalMismatch", readback: independentProtectionReadback(at: url))
            }
            throw error
        }
        result = .verifiedComplete
        #else
        try verifyResourceValues(at: url, disposition: disposition)
        result = .verifiedComplete
        #endif
        try authorityCheck()
        return result
    }

    @discardableResult
    static func applyAndVerify(
        _ kind: OwnedFileKindV1,
        relativePath: String,
        within rootURL: URL,
        authorityCheck: @escaping () throws -> Void = {}
    ) throws -> ProtectedFileVerificationDispositionV1 {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("\\"),
              !relativePath.contains("\\") else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }

        let root = rootURL.standardizedFileURL
        guard root.isFileURL else {
            throw ProtectedFilePolicyError.invalidURL
        }
        let disposition = disposition(for: kind)
        let target = root
            .appendingPathComponent(relativePath, isDirectory: disposition.expectsDirectory)
            .standardizedFileURL
        guard isWithin(target: target, root: root) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        let before = try captureOwnedPath(
            kind,
            root: root,
            target: target,
            leafDisposition: disposition
        )
        let guardedAuthorityCheck: () throws -> Void = {
            try authorityCheck()
            let current = try captureOwnedPath(
                kind,
                root: root,
                target: target,
                leafDisposition: disposition
            )
            guard before == current else {
                throw ProtectedFilePolicyError.identityChanged
            }
        }
        let result = try applyAndVerifyResult(
            kind,
            at: target,
            authorityCheck: guardedAuthorityCheck
        )
        let after = try captureOwnedPath(
            kind,
            root: root,
            target: target,
            leafDisposition: disposition
        )
        guard before == after else {
            throw ProtectedFilePolicyError.identityChanged
        }
        try emitVerificationDisposition(result, kind: kind)
        return result
    }

    @discardableResult
    static func verify(
        _ kind: OwnedFileKindV1,
        at url: URL
    ) throws -> ProtectedFileVerificationDispositionV1 {
        let result = try verifyResult(kind, at: url)
        try emitVerificationDisposition(result, kind: kind)
        return result
    }

    #if DEBUG
    /// Parameter-scoped hostile witness at the actual lstat/open boundary.
    /// Normal callers and Release builds cannot supply this test callback.
    @discardableResult
    static func verify(
        _ kind: OwnedFileKindV1,
        at url: URL,
        afterPinInspectionForTesting: () throws -> Void
    ) throws -> ProtectedFileVerificationDispositionV1 {
        let result = try verifyResult(kind, at: url, afterPinInspection: afterPinInspectionForTesting)
        try emitVerificationDisposition(result, kind: kind)
        return result
    }
    #endif

    private static func verifyResult(
        _ kind: OwnedFileKindV1,
        at url: URL,
        afterPinInspection: () throws -> Void = {}
    ) throws -> ProtectedFileVerificationDispositionV1 {
        let disposition = disposition(for: kind)
        #if DEBUG && os(iOS) && targetEnvironment(simulator)
        let before = try pin(kind, at: url, disposition: disposition, afterInspection: afterPinInspection)
        return try verifySimulatorResourceValues(kind, at: url, disposition: disposition,
            identity: before, successfulRequestReadback: nil)
        #else
        _ = try pin(kind, at: url, disposition: disposition, afterInspection: afterPinInspection)
        try verifyResourceValues(at: url, disposition: disposition)
        return .verifiedComplete
        #endif
    }

    static func verifyIfPresent(
        _ kind: OwnedFileKindV1,
        at url: URL
    ) throws {
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return }
            throw ProtectedFilePolicyError.invalidURL
        }
        try verify(kind, at: url)
    }

    static func verifyIfPresent(
        _ kind: OwnedFileKindV1,
        relativePath: String,
        within rootURL: URL,
        authorityCheck: () throws -> Void = {}
    ) throws {
        guard !relativePath.isEmpty else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        let target = try targetURL(relativePath: relativePath, within: rootURL, kind: kind)
        try validateOwnedAncestors(
            root: rootURL.standardizedFileURL,
            target: target
        )
        try authorityCheck()
        var info = stat()
        guard Darwin.lstat(target.path, &info) == 0 else {
            if errno == ENOENT { return }
            throw ProtectedFilePolicyError.invalidURL
        }
        let before = try captureOwnedPath(
            kind,
            root: rootURL.standardizedFileURL,
            target: target,
            leafDisposition: disposition(for: kind)
        )
        let result = try verifyResult(kind, at: target)
        let after = try captureOwnedPath(
            kind,
            root: rootURL.standardizedFileURL,
            target: target,
            leafDisposition: disposition(for: kind)
        )
        guard before == after else {
            throw ProtectedFilePolicyError.identityChanged
        }
        try authorityCheck()
        try emitVerificationDisposition(result, kind: kind)
    }

    private struct LeafIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let linkCount: nlink_t
    }

    private static func pin(
        _ kind: OwnedFileKindV1,
        at url: URL,
        disposition: OwnedFileProtectionDispositionV1,
        afterInspection: () throws -> Void = {}
    ) throws -> LeafIdentity {
        guard url.isFileURL else {
            throw ProtectedFilePolicyError.invalidURL
        }

        var inspected = stat()
        guard Darwin.lstat(url.path, &inspected) == 0 else {
            if errno == ENOENT { throw ProtectedFilePolicyError.missing }
            if errno == ELOOP { throw ProtectedFilePolicyError.symbolicLink }
            throw ProtectedFilePolicyError.invalidURL
        }
        let type = inspected.st_mode & S_IFMT
        if type == S_IFLNK {
            throw ProtectedFilePolicyError.symbolicLink
        }
        guard (disposition.expectsDirectory && type == S_IFDIR) ||
              (!disposition.expectsDirectory && type == S_IFREG) else {
            throw ProtectedFilePolicyError.invalidType
        }
        if !disposition.expectsDirectory && inspected.st_nlink != 1 {
            throw ProtectedFilePolicyError.hardLink
        }

        try afterInspection()
        // A regular file can be replaced by a FIFO after lstat. Opening
        // nonblocking lets the unchanged fstat/type/identity checks reject it.
        // O_NONBLOCK does not change regular-file reads; directories retain
        // their existing open flags and every resource-policy check remains.
        let flags = disposition.expectsDirectory
            ? O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            : O_RDONLY | O_NOFOLLOW | O_NONBLOCK
        let descriptor = Darwin.open(url.path, flags)
        guard descriptor >= 0 else {
            if errno == ENOENT { throw ProtectedFilePolicyError.missing }
            if errno == ELOOP { throw ProtectedFilePolicyError.symbolicLink }
            if errno == EACCES || errno == EPERM {
                throw ProtectedFilePolicyError.protectedDataUnavailable
            }
            throw ProtectedFilePolicyError.invalidURL
        }
        defer { _ = Darwin.close(descriptor) }

        var actual = stat()
        guard Darwin.fstat(descriptor, &actual) == 0 else {
            throw ProtectedFilePolicyError.invalidURL
        }
        let actualType = actual.st_mode & S_IFMT
        guard actualType == type else {
            throw ProtectedFilePolicyError.identityChanged
        }
        if !disposition.expectsDirectory && actual.st_nlink != 1 {
            throw ProtectedFilePolicyError.hardLink
        }
        let identity = LeafIdentity(
            device: actual.st_dev,
            inode: actual.st_ino,
            linkCount: actual.st_nlink
        )
        guard identity.device == inspected.st_dev,
              identity.inode == inspected.st_ino,
              identity.linkCount == inspected.st_nlink else {
            throw ProtectedFilePolicyError.identityChanged
        }
        _ = kind
        return identity
    }

    private static func targetURL(
        relativePath: String,
        within rootURL: URL,
        kind: OwnedFileKindV1
    ) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("\\"),
              !relativePath.contains("\\") else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        let root = rootURL.standardizedFileURL
        guard root.isFileURL else { throw ProtectedFilePolicyError.invalidURL }
        let target = root
            .appendingPathComponent(relativePath, isDirectory: disposition(for: kind).expectsDirectory)
            .standardizedFileURL
        guard isWithin(target: target, root: root) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        return target
    }

    private static func isWithin(target: URL, root: URL) -> Bool {
        let targetPath = target.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if rootPath == "/" {
            return targetPath.hasPrefix("/")
        }
        return targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
    }

    private static func captureOwnedPath(
        _ kind: OwnedFileKindV1,
        root: URL,
        target: URL,
        leafDisposition: OwnedFileProtectionDispositionV1
    ) throws -> [LeafIdentity] {
        let root = root.standardizedFileURL
        let target = target.standardizedFileURL
        guard isWithin(target: target, root: root) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        let relative = String(target.path.dropFirst(root.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = relative.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }

        var identities = [try pin(
            .durableDirectory,
            at: root,
            disposition: disposition(for: .durableDirectory)
        )]
        var cursor = root
        for component in components.dropLast() {
            cursor.appendPathComponent(component, isDirectory: true)
            identities.append(try pin(
                .durableDirectory,
                at: cursor,
                disposition: disposition(for: .durableDirectory)
            ))
        }
        identities.append(try pin(kind, at: target, disposition: leafDisposition))
        return identities
    }

    /// Checks only components below the caller-owned root.  System-managed
    /// ancestors (for example /var) are intentionally outside this authority
    /// boundary and are never mutated or rejected here.
    private static func validateOwnedAncestors(root: URL, target: URL) throws {
        let rootPath = root.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        guard isWithin(target: target, root: root) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        var rootInfo = stat()
        guard Darwin.lstat(rootPath, &rootInfo) == 0 else {
            if errno == ENOENT { throw ProtectedFilePolicyError.missing }
            throw ProtectedFilePolicyError.invalidURL
        }
        let rootType = rootInfo.st_mode & S_IFMT
        if rootType == S_IFLNK {
            throw ProtectedFilePolicyError.symbolicLink
        }
        guard rootType == S_IFDIR else {
            throw ProtectedFilePolicyError.invalidType
        }
        let relative = String(targetPath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return }
        let components = relative.split(separator: "/").map(String.init)
        guard components.count > 1 else { return }

        var cursor = root
        for component in components.dropLast() {
            cursor.appendPathComponent(component, isDirectory: true)
            var info = stat()
            guard Darwin.lstat(cursor.path, &info) == 0 else {
                if errno == ENOENT { throw ProtectedFilePolicyError.missing }
                throw ProtectedFilePolicyError.invalidURL
            }
            let type = info.st_mode & S_IFMT
            if type == S_IFLNK {
                throw ProtectedFilePolicyError.symbolicLink
            }
            guard type == S_IFDIR else {
                throw ProtectedFilePolicyError.invalidType
            }
        }
    }

    private static func verifyResourceValues(
        at url: URL,
        disposition: OwnedFileProtectionDispositionV1
    ) throws {
        do {
            // FileManager and other URL instances may have changed the file
            // during this run-loop pass. Cached metadata is not a read-back.
            var currentURL = url
            currentURL.removeAllCachedResourceValues()
            let values = try currentURL.resourceValues(forKeys: [
                .fileProtectionKey,
                .isExcludedFromBackupKey
            ])
            guard values.fileProtection == .complete,
                  values.isExcludedFromBackup == disposition.isExcludedFromBackup else {
                #if DEBUG
                let protection = values.fileProtection
                let exclusion = values.isExcludedFromBackup
                let facts = "ProtectedFilePolicy resource-value-mismatch"
                    + " protection=\(String(describing: protection))"
                    + " protectionMatches=\(protection == .complete)"
                    + " backupExcluded=\(String(describing: exclusion))"
                    + " backupMatches=\(exclusion == disposition.isExcludedFromBackup)"
                    + " expectedDirectory=\(disposition.expectsDirectory)"
                    + " expectedBackupExcluded=\(disposition.isExcludedFromBackup)\n"
                diagnosticWriter.write(facts)
                emitResourceValueMismatchSource("strict-resource-readback")
                #endif
                throw ProtectedFilePolicyError.resourceValueMismatch
            }
        } catch let error as ProtectedFilePolicyError {
            throw error
        } catch {
            throw mapWriteError(error)
        }
    }

    private static func emitVerificationDisposition(
        _ result: ProtectedFileVerificationDispositionV1,
        kind: OwnedFileKindV1
    ) throws {
        #if DEBUG && os(iOS) && targetEnvironment(simulator)
        guard result == .simulatorFileProtectionUnsupported else { return }
        let journalStart = DispatchTime.now().uptimeNanoseconds
        defer { simulatorTiming.recordJournal(startedAt: journalStart) }
        try diagnosticSummary.record(kind) {
            let disposition = disposition(for: kind)
            let facts = "V23_SIMULATOR_FILE_PROTECTION_DIAGNOSTIC_V2"
                + " policyID=V23-SIMULATOR-FILE-PROTECTION-DIAGNOSTIC-20260915"
                + " disposition=SIMULATOR_FILE_PROTECTION_UNSUPPORTED"
                + " kind=\(kind.rawValue) request=complete capabilityBefore=false capabilityAfter=false"
                + " urlProtection=completeUntilFirstUserAuthentication"
                + " backupExcluded=\(disposition.isExcludedFromBackup)"
                + " expectsDirectory=\(disposition.expectsDirectory) identityUnchanged=true\n"
            return Data(facts.utf8)
        }
        #endif
    }

    #if DEBUG && os(iOS) && targetEnvironment(simulator)
    /// The strict readback of `verifyResourceValues`, returning whether the values match
    /// instead of throwing and logging on the expected Simulator mismatch.
    private static func simulatorStrictResourceValuesMatch(
        at url: URL,
        disposition: OwnedFileProtectionDispositionV1
    ) throws -> Bool {
        do {
            var currentURL = url
            currentURL.removeAllCachedResourceValues()
            let values = try currentURL.resourceValues(forKeys: [
                .fileProtectionKey,
                .isExcludedFromBackupKey
            ])
            return values.fileProtection == .complete
                && values.isExcludedFromBackup == disposition.isExcludedFromBackup
        } catch {
            throw mapWriteError(error)
        }
    }

    private static func verifySimulatorResourceValues(
        _ kind: OwnedFileKindV1,
        at url: URL,
        disposition: OwnedFileProtectionDispositionV1,
        identity: LeafIdentity,
        successfulRequestReadback: DirectoryProtectionReadback?
    ) throws -> ProtectedFileVerificationDispositionV1 {
        let start = DispatchTime.now().uptimeNanoseconds
        defer { simulatorTiming.recordFallback(at: url, startedAt: start) }
        return try verifySimulatorResourceValuesUntimed(kind, at: url, disposition: disposition,
            identity: identity, successfulRequestReadback: successfulRequestReadback)
    }

    /// A per-call diagnostic proof. No remembered path or inode can authorize a later call.
    private static func verifySimulatorResourceValuesUntimed(
        _ kind: OwnedFileKindV1,
        at url: URL,
        disposition: OwnedFileProtectionDispositionV1,
        identity: LeafIdentity,
        successfulRequestReadback: DirectoryProtectionReadback?
    ) throws -> ProtectedFileVerificationDispositionV1 {
        // The strict readback is checked without throwing: on the Simulator a mismatch is the
        // expected shape, and a thrown-and-caught error on every protected-file call made
        // XCTest misattribute unrelated test failures to it. Only this exact mismatch can
        // enter the separate diagnostic predicate; read failures still throw unchanged.
        if try simulatorStrictResourceValuesMatch(at: url, disposition: disposition) {
            guard try pin(kind, at: url, disposition: disposition) == identity else {
                throw ProtectedFilePolicyError.identityChanged
            }
            return .verifiedComplete
        }

        let before: DirectoryProtectionReadback
        if let successfulRequestReadback {
            // The apply operation already made its one complete request and repaired backup policy.
            before = successfulRequestReadback
        } else {
            before = independentProtectionReadback(at: url)
            guard simulatorReadbackIsExactFallback(before, disposition: disposition) else {
                emitDirectoryProtectionReadback(kind: kind, at: url,
                    phase: "verifyInitialMismatch", readback: before)
                emitResourceValueMismatchSource("initial-fallback-shape")
                throw ProtectedFilePolicyError.resourceValueMismatch
            }
            guard try pin(kind, at: url, disposition: disposition) == identity else {
                throw ProtectedFilePolicyError.identityChanged
            }
            do {
                try (url as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
            } catch {
                throw mapWriteError(error)
            }
        }
        let after = independentProtectionReadback(at: url)
        let identityUnchanged = try pin(kind, at: url, disposition: disposition) == identity
        guard identityUnchanged else { throw ProtectedFilePolicyError.identityChanged }
        guard simulatorDiagnosticAllows(
            capabilityBefore: before.volumeSupportsProtection,
            after: after, disposition: disposition,
            successfulCompleteRequest: true, identityUnchanged: identityUnchanged
        ) else {
            emitDirectoryProtectionReadback(kind: kind, at: url,
                phase: "allowanceBeforeMismatch", readback: before)
            emitDirectoryProtectionReadback(kind: kind, at: url,
                phase: "allowanceAfterMismatch", readback: after)
            emitResourceValueMismatchSource("final-fallback-predicate")
            throw ProtectedFilePolicyError.resourceValueMismatch
        }
        return .simulatorFileProtectionUnsupported
    }

    static func simulatorDiagnosticAllows(
        capabilityBefore: Bool?,
        after: DirectoryProtectionReadback,
        disposition: OwnedFileProtectionDispositionV1,
        successfulCompleteRequest: Bool,
        identityUnchanged: Bool
    ) -> Bool {
        successfulCompleteRequest && identityUnchanged && capabilityBefore == false
            && simulatorReadbackIsExactFallback(after, disposition: disposition)
    }

    static func simulatorReadbackIsExactFallback(
        _ readback: DirectoryProtectionReadback,
        disposition: OwnedFileProtectionDispositionV1
    ) -> Bool {
        readback.volumeSupportsProtection == false
            && readback.urlProtection == "completeUntilFirstUserAuthentication"
            && readback.backupExcluded == disposition.isExcludedFromBackup
            && readback.isDirectory == disposition.expectsDirectory
    }
    #endif

    #if DEBUG
    struct DirectoryProtectionReadback {
        let urlProtection: String
        let fileManagerProtection: String
        let backupExcluded: Bool?
        let isDirectory: Bool?
        let volumeSupportsProtection: Bool?
    }

    /// Read a separately constructed URL so diagnostic observations cannot
    /// populate or clear the caller's cached metadata between its two setters.
    private static func independentProtectionReadback(at url: URL) -> DirectoryProtectionReadback {
        var independent = URL(fileURLWithPath: url.path)
        independent.removeAllCachedResourceValues()
        let values = try? independent.resourceValues(forKeys: [
            .fileProtectionKey, .isExcludedFromBackupKey,
            .isDirectoryKey, .volumeSupportsFileProtectionKey
        ])
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let urlProtection: String
        switch values?.fileProtection {
        case .some(.complete): urlProtection = "complete"
        case .some(.completeUnlessOpen): urlProtection = "completeUnlessOpen"
        case .some(.completeUntilFirstUserAuthentication): urlProtection = "completeUntilFirstUserAuthentication"
        case .some(.none): urlProtection = "none"
        case nil: urlProtection = values == nil ? "readError" : "unknown"
        default: urlProtection = "other"
        }
        let fileManagerProtection: String
        switch attributes?[.protectionKey] as? FileProtectionType {
        case .some(.complete): fileManagerProtection = "complete"
        case .some(.completeUnlessOpen): fileManagerProtection = "completeUnlessOpen"
        case .some(.completeUntilFirstUserAuthentication): fileManagerProtection = "completeUntilFirstUserAuthentication"
        case .some(.none): fileManagerProtection = "none"
        case nil: fileManagerProtection = attributes == nil ? "readError" : "unknown"
        default: fileManagerProtection = "other"
        }
        return DirectoryProtectionReadback(
            urlProtection: urlProtection, fileManagerProtection: fileManagerProtection,
            backupExcluded: values?.isExcludedFromBackup, isDirectory: values?.isDirectory,
            volumeSupportsProtection: values?.allValues[.volumeSupportsFileProtectionKey] as? Bool
        )
    }

    private static func emitDirectoryProtectionReadback(
        kind: OwnedFileKindV1, at url: URL, phase: String,
        readback: DirectoryProtectionReadback?
    ) {
        guard let readback else { return }
        let role: String
        switch (kind, url.lastPathComponent) {
        case (.generationLeaseDirectory, "FieldEvidenceOperations"),
             (.stagingDirectory, "FieldEvidenceOperations"): role = "operationsRoot"
        case (.generationLeaseDirectory, "generation-leases"): role = "generationLeases"
        case (.generationLeaseDirectory, "owners"): role = "leaseOwners"
        case (.stagingDirectory, "schema-migration"): role = "schemaMigration"
        default: role = "other"
        }
        let facts = "ProtectedFilePolicy phase-readback"
            + " kind=\(kind.rawValue) role=\(role) phase=\(phase)"
            + " independentURLProtection=\(readback.urlProtection)"
            + " fileManagerProtection=\(readback.fileManagerProtection)"
            + " backupExcluded=\(String(describing: readback.backupExcluded))"
            + " isDirectory=\(String(describing: readback.isDirectory))"
            + " volumeSupportsProtection=\(String(describing: readback.volumeSupportsProtection))\n"
        diagnosticWriter.write(facts)
    }
    #endif

    private static func mapWriteError(_ error: Error) -> ProtectedFilePolicyError {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain,
           (nsError.code == EACCES || nsError.code == EPERM) {
            return .protectedDataUnavailable
        }
        if nsError.domain == NSCocoaErrorDomain,
           (nsError.code == CocoaError.Code.fileReadNoPermission.rawValue ||
            nsError.code == CocoaError.Code.fileWriteNoPermission.rawValue) {
            return .protectedDataUnavailable
        }
        return .attributeWriteFailed
    }
}

/// C48 exchange state is app-owned protected data, but it is not workspace
/// canonical truth and is never admitted to filesystem backup implicitly.
/// Eligible sessions enter an explicit V4 backup projection instead.
enum PortableExchangeProtectedFilePolicyV2 {
    static let directoryKind: OwnedFileKindV1 = .portableExchangeDirectory
    static let sessionKind: OwnedFileKindV1 = .portableExchangeSessionFile
    static let journalKind: OwnedFileKindV1 = .portableExchangeJournalFile
    static let quarantineKind: OwnedFileKindV1 = .portableExchangeQuarantineFile
    static let restoreSidecarKind: OwnedFileKindV1 = .stagingFile
    static let fileProtection: FileProtectionType = .complete

    static func validate() throws {
        guard ProtectedFilePolicyV1.requiredFileProtection == fileProtection,
              ProtectedFilePolicyV1.disposition(for: directoryKind)
                == .init(expectsDirectory: true, isExcludedFromBackup: true),
              [sessionKind, journalKind, quarantineKind].allSatisfy({
                  ProtectedFilePolicyV1.disposition(for: $0)
                    == .init(expectsDirectory: false, isExcludedFromBackup: true)
              }),
              ProtectedFilePolicyV1.disposition(for: restoreSidecarKind)
                == .init(expectsDirectory: false, isExcludedFromBackup: true) else {
            #if DEBUG
            ProtectedFilePolicyV1.emitResourceValueMismatchSource("portable-exchange-posture")
            #endif
            throw ProtectedFilePolicyError.resourceValueMismatch
        }
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Persistence_ProtectedFilePolicy {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

enum C45AcceptedLabelProtectedFileBoundaryV1 { static let canonicalStoreRequiresCompleteProtection=true;static let leasedOutputScratchIsNotBackupAuthority=true }

enum C46OperationalContactBoundary_21{static let persistentFamilies=OperationalContactPersistenceEnrollmentV1.persistentFamilies;static let platformOutcomesPersistent=false}

/// C49 manual work-resource truth is stored in the protected SwiftData
/// generation.  It introduces no file-backed inventory, timer, or accounting
/// artifact; only the already-authorized C48 exchange scratch remains in the
/// protected-file policy.
enum C49WorkResourceProtectedFileBoundaryV1 {
    static let workResourceTruthUsesPersistentModel = true
    static let introducesWorkResourceFileKind = false
    static let localPartReferenceIsEmbeddedSnapshot = true
    static let exchangeScratchRemainsExcludedFromBackup = true
    static let persistentSchemaVersion = C49WorkResourcePersistenceBoundaryV1.persistentSchemaVersion
    static let recordsSchemaVersion = C49WorkResourcePersistenceBoundaryV1.recordsSchemaVersion

    static func validate() throws {
        guard workResourceTruthUsesPersistentModel,
              !introducesWorkResourceFileKind,
              localPartReferenceIsEmbeddedSnapshot,
              exchangeScratchRemainsExcludedFromBackup else {
            #if DEBUG
            ProtectedFilePolicyV1.emitResourceValueMismatchSource("work-resource-posture")
            #endif
            throw ProtectedFilePolicyError.resourceValueMismatch
        }
        try C49WorkResourcePersistenceBoundaryV1.validate()
    }
}
// C52_BOUNDARY_ANCHOR: accepted-source-protection
enum C52ServiceRequestProtectedFileBoundaryV1 {
    static let acceptedPortableSourceBytesUseCompleteProtection = true
    static let acceptedSanitizedMediaUsesCanonicalContentStore = true
    static let rawCapabilityBytesMayEnterWorkspaceFiles = false
    static let unsanitizedMediaMayEnterCanonicalContent = false
}

/// Observation only. Pending means the exact incumbent DEBUG Simulator
/// fallback shape; it is not an accepted protection result or effect authority.
struct TemporalPolicyObservationV1: Equatable, Sendable {
    enum State: String, Sendable { case strictComplete, pendingSimulatorRequest }
    let state: State
    let device: UInt64
    let inode: UInt64
    let linkCount: UInt64
    let mode: UInt16
    let urlProtection: String
    let fileManagerProtection: String
    let backupExcluded: Bool?
    let isDirectory: Bool?
    let volumeSupportsProtection: Bool?
}

/// LIVE observation-only descriptor owner. No external lease or effect is
/// owned. Usable numeric slots are fenced before their one checked close;
/// uncertain slots remain evidence forever. There is no deinit close.
@MainActor
final class OriginalEraseScratchTemporalPolicyAttemptV1 {
    private enum State { case observing, terminal, uncertain }
    private var state: State = .observing
    private var openDescriptors: [Int32] = []
    private var uncertainDescriptors: [Int32] = []
    private var unreportedUncertainty: [Int32] = []
    private var selection: OriginalEraseScratchTemporalPolicyReadContextV1.Selection?
    private var scopeIdentity: ObjectIdentifier?
    private var operationID: UUID?
    private var observationID: UUID?
    private var uncertainOwner: OriginalEraseScratchTemporalObservationScopeV1?
    private struct CompletedObservation {
        let scopeIdentity: ObjectIdentifier
        let operationID: UUID
        let observationID: UUID
        let values: [TemporalPolicyObservationV1]
    }
    private var completed: CompletedObservation?
    fileprivate var needsFinish: Bool { state == .observing || !openDescriptors.isEmpty || !unreportedUncertainty.isEmpty }
    /// Resource sets only: refusal cleanup or last-pop-before-close may pass.
    /// Completed calls, positive receipts and nonpoisoned owner are separate.
    func requireCheckedObservationTerminal() throws {
        guard state == .terminal, openDescriptors.isEmpty, uncertainDescriptors.isEmpty else {
            throw ProtectedFilePolicyError.identityChanged
        }
    }
    /// Positive memory settlement of THIS actual checked observation call.
    /// It grants no next-effect authority and does not replace fresh source/G.
    func requireCheckedSettlement() throws {
        try requireCheckedObservationTerminal()
        guard let completed, let scopeIdentity,
              completed.scopeIdentity == scopeIdentity,
              completed.operationID == operationID, completed.observationID == observationID,
              !completed.values.isEmpty else { throw ProtectedFilePolicyError.identityChanged }
    }
    fileprivate func bind(_ selection: OriginalEraseScratchTemporalPolicyReadContextV1.Selection,
        scope: OriginalEraseScratchTemporalObservationScopeV1) throws {
        try requireObserving()
        guard self.selection == nil, openDescriptors.isEmpty else { throw ProtectedFilePolicyError.identityChanged }
        self.selection = selection; scopeIdentity = ObjectIdentifier(scope)
        operationID = scope.operationID; observationID = scope.observationID
    }
    private func freshBinding(_ scope: OriginalEraseScratchTemporalObservationScopeV1) throws {
        try scope.requireCurrentBinding()
        if let selection {
            guard scopeIdentity == ObjectIdentifier(scope), operationID == scope.operationID,
                  observationID == scope.observationID else { throw ProtectedFilePolicyError.identityChanged }
            switch selection {
            case .node(let node):
                guard OriginalEraseScratchTemporalPolicyReadContextV1.sameNode(
                    try scope.requirePolicyNode(node.kind, at: node.url, fullFact: node.fullFact), node) else {
                    throw ProtectedFilePolicyError.identityChanged
                }
            case .pair(let pair, let urls):
                guard OriginalEraseScratchTemporalPolicyReadContextV1.samePair(
                    try scope.requirePair(aliasURLs: urls), pair) else { throw ProtectedFilePolicyError.identityChanged }
            }
        } else {
            // Before any selection/acquisition, refusal cleanup owns no FDs.
            guard openDescriptors.isEmpty else { throw ProtectedFilePolicyError.identityChanged }
        }
        try scope.requireCurrentBinding()
    }
    fileprivate func acceptCompleted(scope: OriginalEraseScratchTemporalObservationScopeV1,
        values: [TemporalPolicyObservationV1]) throws {
        try requireCheckedObservationTerminal(); try freshBinding(scope)
        guard let selection, completed == nil else { throw ProtectedFilePolicyError.identityChanged }
        switch selection {
        case .node: guard values.count == 1 else { throw ProtectedFilePolicyError.identityChanged }
        case .pair: guard values.count == 2, values[0] == values[1] else { throw ProtectedFilePolicyError.identityChanged }
        }
        // Called only after private real policy/SHA checks, finish RETURNED
        // and final fresh binding. Neither refusal nor in-flight close calls it.
        completed = CompletedObservation(scopeIdentity: ObjectIdentifier(scope),
            operationID: scope.operationID, observationID: scope.observationID, values: values)
    }
    fileprivate func poison(scope: OriginalEraseScratchTemporalObservationScopeV1) {
        uncertainOwner = scope // Retain actual owner before poison/callback; no success cycle.
        scope.poisonOnUncertainObservation()
    }
    fileprivate func requireObserving() throws {
        guard state == .observing, uncertainDescriptors.isEmpty else {
            throw ProtectedFilePolicyError.identityChanged
        }
    }
    fileprivate func remember(_ fd: Int32, scope: OriginalEraseScratchTemporalObservationScopeV1,
        retain: (Int32) -> Void) throws {
        try requireObserving()
        guard fd >= 0 else { throw ProtectedFilePolicyError.invalidURL }
        guard selection != nil, scopeIdentity == ObjectIdentifier(scope) else {
            state = .uncertain; uncertainDescriptors.append(fd)
            poison(scope: scope); retain(fd)
            throw ProtectedFilePolicyError.identityChanged
        }
        guard !openDescriptors.contains(fd) else {
            openDescriptors.removeAll { $0 == fd }
            state = .uncertain; uncertainDescriptors.append(fd)
            poison(scope: scope); retain(fd)
            throw ProtectedFilePolicyError.identityChanged
        }
        openDescriptors.append(fd)
    }
    fileprivate func abandonHeldDescriptor(_ fd: Int32, scope: OriginalEraseScratchTemporalObservationScopeV1) {
        // Identity/fstat ambiguity is not a definitely-owned numeric close slot.
        openDescriptors.removeAll { $0 == fd }
        if !uncertainDescriptors.contains(fd) {
            uncertainDescriptors.append(fd); unreportedUncertainty.append(fd)
        }
        state = .uncertain; poison(scope: scope)
    }
    fileprivate func finish(scope: OriginalEraseScratchTemporalObservationScopeV1,
        retain: (Int32) -> Void) throws {
        guard needsFinish else { throw ProtectedFilePolicyError.identityChanged }
        if state == .observing { state = .terminal }
        while !unreportedUncertainty.isEmpty {
            let fd = unreportedUncertainty.removeFirst()
            poison(scope: scope); retain(fd) // Already permanently fenced before callback.
        }
        var first: Error?
        while let fd = openDescriptors.popLast() {
            do { try freshBinding(scope) }
            catch { if first == nil { first = error }; poison(scope: scope) }
            let result = Darwin.close(fd)
            if result != 0 {
                state = .uncertain; uncertainDescriptors.append(fd)
                poison(scope: scope); retain(fd)
                if first == nil { first = ProtectedFilePolicyError.identityChanged }
            }
            do { try freshBinding(scope) }
            catch { if first == nil { first = error }; poison(scope: scope) }
        }
        if let first { throw first }
    }
}

/// PFP-private actor boundary, populated only by a genuine LIVE scope getter.
/// No caller closure, link-count exemption or setter reaches this context.
@MainActor
fileprivate final class OriginalEraseScratchTemporalPolicyReadContextV1 {
    enum Selection {
        case node(OriginalEraseScratchTemporalPolicyNodeV1)
        case pair(OriginalEraseScratchTemporalPairV1, [URL])
    }
    struct Leaf { let url: URL; let fullFact: String }
    let scope: OriginalEraseScratchTemporalObservationScopeV1
    let attempt: OriginalEraseScratchTemporalPolicyAttemptV1
    let selection: Selection
    let kind: OwnedFileKindV1
    let ancestors: [OriginalEraseScratchTemporalPolicyNodeV1.Ancestor]
    let leaves: [Leaf]
    private let operationID: UUID
    private let observationID: UUID
    private let expectedBytes: UInt64
    private let expectedCalls: UInt64
    private var ancestorFDs: [Int32] = []
    private var leafFDs: [Int32] = []
    private var readBytes: UInt64 = 0
    private var readCalls: UInt64 = 0
    init(scope: OriginalEraseScratchTemporalObservationScopeV1,
        attempt: OriginalEraseScratchTemporalPolicyAttemptV1, selection: Selection) throws {
        self.scope = scope; self.attempt = attempt; self.selection = selection
        operationID = scope.operationID; observationID = scope.observationID
        switch selection {
        case .node(let n):
            kind = n.kind; ancestors = n.ancestors; leaves = [Leaf(url: n.url, fullFact: n.fullFact)]
            expectedBytes = 0; expectedCalls = 0
        case .pair(let p, _):
            kind = p.kind; ancestors = p.ancestors
            leaves = p.members.map { Leaf(url: $0.url, fullFact: $0.fullFact) }
            guard p.byteCount >= 0, let b = UInt64(exactly: p.byteCount) else {
                throw ProtectedFilePolicyError.invalidURL
            }
            let bytes = b.multipliedReportingOverflow(by: 4)
            let round = b.addingReportingOverflow(65_535)
            guard !bytes.overflow, !round.overflow else { throw ProtectedFilePolicyError.invalidURL }
            let calls = (round.partialValue / 65_536).multipliedReportingOverflow(by: 4)
            guard !calls.overflow else { throw ProtectedFilePolicyError.invalidURL }
            expectedBytes = bytes.partialValue; expectedCalls = calls.partialValue
        }
        try validateData()
        try attempt.bind(selection, scope: scope)
    }
    private static func fact(_ f: stat) -> String {
        "\(f.st_dev)|\(f.st_ino)|\(f.st_mode)|\(f.st_uid)|\(f.st_gid)|\(f.st_nlink)|\(f.st_size)|\(f.st_mtimespec.tv_sec)|\(f.st_mtimespec.tv_nsec)|\(f.st_ctimespec.tv_sec)|\(f.st_ctimespec.tv_nsec)"
    }
    private static func originalFact(_ full: String) -> String {
        let f = full.split(separator: "|", omittingEmptySubsequences: false)
        guard f.count == 11 else { return "" }
        return [f[0], f[1], f[2], f[5], f[6], f[7], f[8], f[9], f[10]].joined(separator: "|")
    }
    private static func validPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { OperationalDiagnosticsBoundsV1.validRelativeName(String($0)) }
    }
    private static func sameAncestors(_ a: [OriginalEraseScratchTemporalPolicyNodeV1.Ancestor],
        _ b: [OriginalEraseScratchTemporalPolicyNodeV1.Ancestor]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { p in p.0.url == p.1.url && p.0.fullFact == p.1.fullFact && p.0.directoryRole == p.1.directoryRole }
    }
    fileprivate static func sameNode(_ a: OriginalEraseScratchTemporalPolicyNodeV1,
        _ b: OriginalEraseScratchTemporalPolicyNodeV1) -> Bool {
        a.kind == b.kind && a.url == b.url && a.fullFact == b.fullFact &&
        a.parentURL == b.parentURL && a.parentFullFact == b.parentFullFact &&
        a.directoryRole == b.directoryRole && sameAncestors(a.ancestors, b.ancestors)
    }
    fileprivate static func samePair(_ a: OriginalEraseScratchTemporalPairV1,
        _ b: OriginalEraseScratchTemporalPairV1) -> Bool {
        guard a.members.count == b.members.count,
              zip(a.members, b.members).allSatisfy({ p in p.0.relativePath == p.1.relativePath &&
                p.0.url == p.1.url && p.0.fullFact == p.1.fullFact }),
              a.kind == b.kind, a.sha256 == b.sha256, a.byteCount == b.byteCount,
              a.device == b.device, a.inode == b.inode, a.user == b.user, a.group == b.group,
              a.parentURL == b.parentURL, a.parentFullFact == b.parentFullFact,
              sameAncestors(a.ancestors, b.ancestors) else { return false }
        switch (a.role, b.role) {
        case let (.declaredLinkPublication(ac, al, at, af), .declaredLinkPublication(bc, bl, bt, bf)):
            return ac == bc && al == bl && at == bt && af == bf
        case let (.admittedOriginalOwnedGenericAliases(ai, ap, af, ah, am),
                  .admittedOriginalOwnedGenericAliases(bi, bp, bf, bh, bm)):
            return ai == bi && ap == bp && af == bf && ah == bh && am == bm
        default: return false
        }
    }
    private func validateData() throws {
        guard !ancestors.isEmpty, ancestors[0].url.lastPathComponent == "Operations", !leaves.isEmpty,
              kind == .stagingDirectory || kind == .temporaryFile else { throw ProtectedFilePolicyError.invalidURL }
        let nodes = ancestors.map { Leaf(url: $0.url, fullFact: $0.fullFact) } + leaves
        guard nodes.allSatisfy({ $0.url.isFileURL && $0.url.standardizedFileURL == $0.url &&
            $0.fullFact.split(separator: "|", omittingEmptySubsequences: false).count == 11 }) else {
            throw ProtectedFilePolicyError.invalidURL
        }
        for i in ancestors.indices where i > 0 {
            guard ancestors[i].url.deletingLastPathComponent() == ancestors[i - 1].url,
                  OperationalDiagnosticsBoundsV1.validRelativeName(ancestors[i].url.lastPathComponent) else {
                throw ProtectedFilePolicyError.invalidURL
            }
        }
        let parent = ancestors[ancestors.count - 1]
        guard leaves.allSatisfy({ $0.url.deletingLastPathComponent() == parent.url &&
            OperationalDiagnosticsBoundsV1.validRelativeName($0.url.lastPathComponent) }) else {
            throw ProtectedFilePolicyError.invalidURL
        }
        switch selection {
        case .node(let n):
            guard n.parentURL == parent.url, n.parentFullFact == parent.fullFact,
                  (n.directoryRole != nil) == (kind == .stagingDirectory) else {
                throw ProtectedFilePolicyError.invalidURL
            }
        case .pair(let p, let urls):
            guard kind == .temporaryFile, p.members.count == 2, urls == p.members.map(\.url),
                  urls[0] != urls[1], p.members[0].fullFact == p.members[1].fullFact,
                  p.parentURL == parent.url, p.parentFullFact == parent.fullFact,
                  OperationalDiagnosticsBoundsV1.isLowercaseSHA256(p.sha256),
                  p.members[0].relativePath.utf8.lexicographicallyPrecedes(p.members[1].relativePath.utf8),
                  p.members.allSatisfy({ Self.validPath($0.relativePath) &&
                    ancestors[0].url.appendingPathComponent($0.relativePath) == $0.url }) else {
                throw ProtectedFilePolicyError.invalidURL
            }
            switch p.role {
            case .declaredLinkPublication(_, _, let temporary, let final):
                guard Self.validPath(temporary), Self.validPath(final), temporary != final,
                      Set(p.members.map(\.relativePath)) == Set([temporary, final]) else {
                    throw ProtectedFilePolicyError.invalidURL
                }
            case .admittedOriginalOwnedGenericAliases(let index, let paths, let facts, let hash, let metadata):
                guard index >= 0, paths.count == 2, facts.count == 2,
                      paths[0].utf8.lexicographicallyPrecedes(paths[1].utf8), paths.allSatisfy(Self.validPath),
                      hash == p.sha256, facts[0] == facts[1],
                      facts.allSatisfy({ $0 == Self.originalFact(p.members[0].fullFact) }),
                      paths.allSatisfy({ $0.hasPrefix("ScratchDataV1/") && ($0 as NSString).lastPathComponent != "lease.json" }),
                      p.members.allSatisfy({ $0.relativePath.hasPrefix("ScratchDataV1/") && $0.url.lastPathComponent != "lease.json" }) else {
                    throw ProtectedFilePolicyError.invalidURL
                }
                let originalParent = (paths[0] as NSString).deletingLastPathComponent
                guard originalParent == (paths[1] as NSString).deletingLastPathComponent else {
                    throw ProtectedFilePolicyError.invalidURL
                }
                for (path, member) in zip(paths, p.members) {
                    guard (path as NSString).lastPathComponent == member.url.lastPathComponent else {
                        throw ProtectedFilePolicyError.invalidURL
                    }
                }
                switch metadata {
                case .validatedLease(let directory, let bytes, let sha):
                    guard directory == originalParent, bytes.count <= 65_536,
                          OperationalDiagnosticsBoundsV1.isLowercaseSHA256(sha),
                          SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == sha else {
                        throw ProtectedFilePolicyError.invalidURL
                    }
                case .ownedOrphan(let directory):
                    guard directory == originalParent else { throw ProtectedFilePolicyError.invalidURL }
                }
                // Original metadata never becomes an orphan after consumption.
                // The scope proves actual current mapping/relations afresh.
            }
        }
    }
    private func boundary() throws {
        try scope.requireCurrentBinding(); try attempt.requireObserving()
        guard scope.operationID == operationID, scope.observationID == observationID else {
            throw ProtectedFilePolicyError.identityChanged
        }
        switch selection {
        case .node(let n):
            guard Self.sameNode(try scope.requirePolicyNode(n.kind, at: n.url, fullFact: n.fullFact), n) else {
                throw ProtectedFilePolicyError.identityChanged
            }
        case .pair(let p, let urls):
            guard Self.samePair(try scope.requirePair(aliasURLs: urls), p) else { throw ProtectedFilePolicyError.identityChanged }
        }
        try scope.requireCurrentBinding(); try attempt.requireObserving()
    }
    private func io<Value>(_ body: @MainActor () throws -> Value) throws -> Value {
        try boundary()
        let result: Result<Value, Error>
        do { result = .success(try body()) } catch { result = .failure(error) }
        try boundary(); return try result.get()
    }
    private func open(_ body: @MainActor () -> Int32, retain: (Int32) -> Void) throws -> Int32 {
        try boundary(); let fd = body()
        let remembered: Result<Void, Error>
        if fd >= 0 {
            do { try attempt.remember(fd, scope: scope, retain: retain); remembered = .success(()) }
            catch { remembered = .failure(error) }
        } else { remembered = .failure(ProtectedFilePolicyError.invalidURL) }
        try boundary(); try remembered.get(); return fd
    }
    func openAll(retain: (Int32) -> Void) throws {
        let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        for i in ancestors.indices {
            let fd = try open({ i == 0 ? Darwin.open(ancestors[i].url.path, directoryFlags) :
                Darwin.openat(ancestorFDs[i - 1], ancestors[i].url.lastPathComponent, directoryFlags) }, retain: retain)
            ancestorFDs.append(fd); _ = try inspectAncestor(i)
        }
        for leaf in leaves {
            let flags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (kind == .stagingDirectory ? O_DIRECTORY : 0)
            let fd = try open({ Darwin.openat(ancestorFDs[ancestors.count - 1], leaf.url.lastPathComponent, flags) }, retain: retain)
            leafFDs.append(fd); _ = try inspectLeaf(leafFDs.count - 1)
        }
    }
    private func inspectAncestor(_ i: Int) throws -> stat {
        var held = stat(), named = stat()
        try io {
            guard Darwin.fstat(ancestorFDs[i], &held) == 0, Self.fact(held) == ancestors[i].fullFact else {
                attempt.abandonHeldDescriptor(ancestorFDs[i], scope: scope)
                throw ProtectedFilePolicyError.identityChanged
            }
        }
        try io {
            let result = i == 0 ? Darwin.lstat(ancestors[i].url.path, &named) :
                Darwin.fstatat(ancestorFDs[i - 1], ancestors[i].url.lastPathComponent, &named, AT_SYMLINK_NOFOLLOW)
            guard result == 0 else { throw ProtectedFilePolicyError.identityChanged }
        }
        try requireOwned(held, named: named, fullFact: ancestors[i].fullFact, directory: true,
            parentFact: i == 0 ? nil : ancestors[i - 1].fullFact, directoryRole: ancestors[i].directoryRole)
        return held
    }
    private func requireOwned(_ held: stat, named: stat, fullFact: String, directory: Bool,
        parentFact: String?, directoryRole: OriginalEraseScratchPrivateDirectoryRoleV1?) throws {
        let root = ancestors[0].fullFact.split(separator: "|", omittingEmptySubsequences: false)
        guard Self.fact(held) == fullFact, Self.fact(named) == fullFact,
              held.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
              (directory ? (held.st_mode & 0o7777 == 0o700 || held.st_mode & 0o7777 == 0o2700)
                         : held.st_mode & 0o7777 == 0o600), held.st_uid == Darwin.geteuid(),
              held.st_dev >= 0, String(held.st_dev) == root[0],
              String(held.st_uid) == root[3] else {
            throw ProtectedFilePolicyError.identityChanged
        }
        if directory {
            guard let directoryRole, directoryRole.admits(fullMode: UInt32(held.st_mode)),
                  directoryRole.recordedFullMode == UInt32(held.st_mode) else { throw ProtectedFilePolicyError.identityChanged }
        } else { guard directoryRole == nil else { throw ProtectedFilePolicyError.identityChanged } }
        if let parentFact {
            let parent = parentFact.split(separator: "|", omittingEmptySubsequences: false)
            guard parent.count == 11, let mode = UInt16(parent[2]), let group = UInt32(parent[4]),
                  held.st_gid == (mode & UInt16(S_ISGID) != 0 ? group : Darwin.getegid()) else {
                throw ProtectedFilePolicyError.identityChanged
            }
        }
    }
    private func inspectLeaf(_ i: Int) throws -> stat {
        var held = stat(), named = stat()
        try io {
            guard Darwin.fstat(leafFDs[i], &held) == 0, Self.fact(held) == leaves[i].fullFact else {
                attempt.abandonHeldDescriptor(leafFDs[i], scope: scope)
                throw ProtectedFilePolicyError.identityChanged
            }
        }
        try io { guard Darwin.fstatat(ancestorFDs[ancestors.count - 1], leaves[i].url.lastPathComponent,
            &named, AT_SYMLINK_NOFOLLOW) == 0 else { throw ProtectedFilePolicyError.identityChanged } }
        let directory = kind == .stagingDirectory
        try requireOwned(held, named: named, fullFact: leaves[i].fullFact, directory: directory,
            parentFact: ancestors[ancestors.count - 1].fullFact, directoryRole: {
                if case .node(let n) = selection { return n.directoryRole }
                return nil
            }())
        switch selection {
        case .node:
            guard directory || held.st_nlink == 1 else { throw ProtectedFilePolicyError.hardLink }
        case .pair(let p, _):
            guard !directory, held.st_nlink == 2, held.st_size == p.byteCount,
                  UInt64(held.st_dev) == p.device, UInt64(held.st_ino) == p.inode,
                  held.st_uid == p.user, held.st_gid == p.group else { throw ProtectedFilePolicyError.identityChanged }
        }
        return held
    }
    func requirePolicyBoundary() throws -> stat {
        try boundary()
        guard ancestorFDs.count == ancestors.count, leafFDs.count == leaves.count else { throw ProtectedFilePolicyError.identityChanged }
        for i in ancestors.indices { _ = try inspectAncestor(i) }
        var first = stat()
        for i in leaves.indices {
            let actual = try inspectLeaf(i)
            if i == 0 { first = actual }
            else if case .pair = selection {
                guard actual.st_dev == first.st_dev, actual.st_ino == first.st_ino else { throw ProtectedFilePolicyError.hardLink }
            }
        }
        try boundary(); return first
    }
    private func stream(_ p: OriginalEraseScratchTemporalPairV1) throws {
        var digest = SHA256(), offset: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while offset < p.byteCount {
            _ = try requirePolicyBoundary()
            let wanted = Int(min(Int64(buffer.count), p.byteCount - offset))
            let calls = readCalls.addingReportingOverflow(1)
            guard !calls.overflow, calls.partialValue <= expectedCalls else { throw ProtectedFilePolicyError.identityChanged }
            readCalls = calls.partialValue
            let got = try io { buffer.withUnsafeMutableBytes { Darwin.pread(leafFDs[0], $0.baseAddress!, wanted, off_t(offset)) } }
            guard got == wanted else { throw ProtectedFilePolicyError.identityChanged }
            let bytes = readBytes.addingReportingOverflow(UInt64(got))
            guard !bytes.overflow, bytes.partialValue <= expectedBytes else { throw ProtectedFilePolicyError.identityChanged }
            readBytes = bytes.partialValue
            buffer.withUnsafeBytes { digest.update(bufferPointer: UnsafeRawBufferPointer(start: $0.baseAddress, count: wanted)) }
            offset += Int64(wanted); _ = try requirePolicyBoundary()
        }
        guard offset == p.byteCount, digest.finalize().map({ String(format: "%02x", $0) }).joined() == p.sha256 else {
            throw ProtectedFilePolicyError.identityChanged
        }
    }
    func requireUnchangedPolicyInput() throws -> stat {
        let first = try requirePolicyBoundary()
        if case .pair(let p, _) = selection { try stream(p); _ = try requirePolicyBoundary() }
        return first
    }
    func requireCompletedPayloadWork() throws {
        guard readBytes == expectedBytes, readCalls == expectedCalls else { throw ProtectedFilePolicyError.identityChanged }
        try boundary()
    }
}

/// The two actual publication-policy calls, in their fixed order.
enum OriginalEraseScratchPublicationPolicyStepV1: Equatable {
    case completeProtection, backupExclusion
}

/// A saved real Foundation call event. Only the PFP setter constructs it,
/// immediately after the call returns or throws and before invoking a scope.
@MainActor
fileprivate final class OriginalEraseScratchPublicationPolicyEventV1 {
    let step: OriginalEraseScratchPublicationPolicyStepV1
    let result: Result<Void, Error>
    init(step: OriginalEraseScratchPublicationPolicyStepV1, result: Result<Void, Error>) {
        self.step = step; self.result = result
    }
}

/// An intermediate actual event plus its independently held/named postfact.
/// It neither claims final policy qualification nor grants another effect.
@MainActor
final class OriginalEraseScratchPublicationPolicyOutcomeV1 {
    let step: OriginalEraseScratchPublicationPolicyStepV1
    fileprivate let event: OriginalEraseScratchPublicationPolicyEventV1
    fileprivate let fullFact: String
    private weak var attempt: OriginalEraseScratchPublicationPolicyAttemptV1?
    fileprivate init(attempt: OriginalEraseScratchPublicationPolicyAttemptV1,
        event: OriginalEraseScratchPublicationPolicyEventV1, fullFact: String) {
        self.attempt = attempt; self.event = event; self.fullFact = fullFact; step = event.step
    }
    func requireBound(scope: OriginalEraseScratchCleanupPolicyEffectScopeV1,
        kind: OwnedFileKindV1, at url: URL, fullFact: String) throws {
        guard let attempt else { throw ProtectedFilePolicyError.identityChanged }
        try attempt.requireOutcome(self, scope: scope, kind: kind, at: url, fullFact: fullFact)
    }
}

/// One real LIVE publication-policy subattempt. Scope retains it before the
/// first getter/open. Terminal slots are fenced before their sole close;
/// uncertainty retains the actual owner before poison and never retries an FD.
@MainActor
final class OriginalEraseScratchPublicationPolicyAttemptV1 {
    private enum State { case applying, terminal, uncertain }
    private var state: State = .applying
    private var openDescriptors: [Int32] = []
    private var uncertainDescriptors: [Int32] = []
    private var unreportedUncertainty: [Int32] = []
    private var closedDescriptors: [Int32] = []
    private var scopeIdentity: ObjectIdentifier?
    private var operationID: UUID?
    private var requestID: UUID?
    private var target: OriginalEraseScratchTemporalPolicyNodeV1?
    private var sourceSHA256: String?
    private var byteCount: Int64?
    private var uncertainOwner: OriginalEraseScratchCleanupPolicyEffectScopeV1?
    private var events: [OriginalEraseScratchPublicationPolicyEventV1] = []
    private var outcomes: [OriginalEraseScratchPublicationPolicyOutcomeV1] = []
    private var acceptedOutcomes: [OriginalEraseScratchPublicationPolicyOutcomeV1] = []
    private struct CompletedPolicy {
        let scopeIdentity: ObjectIdentifier
        let operationID: UUID
        let requestID: UUID
        let kind: OwnedFileKindV1
        let url: URL
        let fullFact: String
        let value: TemporalPolicyObservationV1
    }
    private var completed: CompletedPolicy?
    fileprivate var needsFinish: Bool { state == .applying || !openDescriptors.isEmpty || !unreportedUncertainty.isEmpty }
    fileprivate func bind(scope: OriginalEraseScratchCleanupPolicyEffectScopeV1,
        target: OriginalEraseScratchTemporalPolicyNodeV1) throws {
        try requireApplying()
        guard self.target == nil, openDescriptors.isEmpty else { throw ProtectedFilePolicyError.identityChanged }
        self.target = target; scopeIdentity = ObjectIdentifier(scope)
        operationID = scope.operationID; requestID = scope.requestID
        sourceSHA256 = scope.sourceSHA256; byteCount = scope.byteCount
    }
    fileprivate func requireApplying() throws {
        guard state == .applying, uncertainDescriptors.isEmpty else { throw ProtectedFilePolicyError.identityChanged }
    }
    fileprivate func freshBinding(_ scope: OriginalEraseScratchCleanupPolicyEffectScopeV1) throws {
        try scope.requireCurrentBinding()
        if let target {
            guard scopeIdentity == ObjectIdentifier(scope), operationID == scope.operationID,
                  requestID == scope.requestID, sourceSHA256 == scope.sourceSHA256, byteCount == scope.byteCount,
                  OriginalEraseScratchTemporalPolicyReadContextV1.sameNode(
                    try scope.requireTarget(target.kind, at: target.url, initialFullFact: target.fullFact), target) else {
                throw ProtectedFilePolicyError.identityChanged
            }
        } else { guard openDescriptors.isEmpty else { throw ProtectedFilePolicyError.identityChanged } }
        try scope.requireCurrentBinding()
    }
    fileprivate func poison(_ scope: OriginalEraseScratchCleanupPolicyEffectScopeV1) {
        uncertainOwner = scope
        scope.poisonOnUncertainPolicy()
    }
    fileprivate func remember(_ fd: Int32, scope: OriginalEraseScratchCleanupPolicyEffectScopeV1,
        retain: (Int32) -> Void) throws {
        try requireApplying()
        guard fd >= 0 else { throw ProtectedFilePolicyError.invalidURL }
        guard target != nil, scopeIdentity == ObjectIdentifier(scope),
              !openDescriptors.contains(fd), !closedDescriptors.contains(fd), !uncertainDescriptors.contains(fd) else {
            openDescriptors.removeAll { $0 == fd }
            state = .uncertain; uncertainDescriptors.append(fd)
            poison(scope); retain(fd)
            throw ProtectedFilePolicyError.identityChanged
        }
        openDescriptors.append(fd)
    }
    fileprivate func requireNextStep(_ step: OriginalEraseScratchPublicationPolicyStepV1) throws {
        try requireApplying()
        guard events.count == acceptedOutcomes.count,
              (events.isEmpty && step == .completeProtection) ||
              (events.count == 1 && step == .backupExclusion) else { throw ProtectedFilePolicyError.identityChanged }
    }
    fileprivate func record(_ event: OriginalEraseScratchPublicationPolicyEventV1) throws {
        try requireNextStep(event.step); events.append(event)
    }
    fileprivate func capture(_ event: OriginalEraseScratchPublicationPolicyEventV1,
        fullFact: String) throws -> OriginalEraseScratchPublicationPolicyOutcomeV1 {
        try requireApplying()
        guard events.last === event, outcomes.count == acceptedOutcomes.count else {
            throw ProtectedFilePolicyError.identityChanged
        }
        try event.result.get()
        let outcome = OriginalEraseScratchPublicationPolicyOutcomeV1(attempt: self, event: event, fullFact: fullFact)
        outcomes.append(outcome); return outcome
    }
    fileprivate func requireOutcome(_ outcome: OriginalEraseScratchPublicationPolicyOutcomeV1,
        scope: OriginalEraseScratchCleanupPolicyEffectScopeV1, kind: OwnedFileKindV1,
        at url: URL, fullFact: String) throws {
        guard state != .uncertain, uncertainDescriptors.isEmpty, scopeIdentity == ObjectIdentifier(scope),
              operationID == scope.operationID, requestID == scope.requestID,
              let target, target.kind == kind, target.url == url,
              outcomes.contains(where: { $0 === outcome }), events.contains(where: { $0 === outcome.event }),
              outcome.fullFact == fullFact, outcome.step == outcome.event.step else {
            throw ProtectedFilePolicyError.identityChanged
        }
        try outcome.event.result.get() // Actual returned event, never caller success DATA.
    }
    fileprivate func accept(_ outcome: OriginalEraseScratchPublicationPolicyOutcomeV1,
        scope: OriginalEraseScratchCleanupPolicyEffectScopeV1) throws {
        try requireApplying()
        guard let target, outcomes.last === outcome, acceptedOutcomes.count + 1 == outcomes.count else {
            throw ProtectedFilePolicyError.identityChanged
        }
        try requireOutcome(outcome, scope: scope, kind: target.kind, at: target.url, fullFact: outcome.fullFact)
        acceptedOutcomes.append(outcome)
    }
    fileprivate func abandonHeldDescriptor(_ fd: Int32, scope: OriginalEraseScratchCleanupPolicyEffectScopeV1) {
        openDescriptors.removeAll { $0 == fd }
        if !uncertainDescriptors.contains(fd) {
            uncertainDescriptors.append(fd); unreportedUncertainty.append(fd)
        }
        state = .uncertain; poison(scope)
    }
    fileprivate func finish(scope: OriginalEraseScratchCleanupPolicyEffectScopeV1,
        retain: (Int32) -> Void) throws {
        guard needsFinish else { throw ProtectedFilePolicyError.identityChanged }
        if state == .applying { state = .terminal }
        while !unreportedUncertainty.isEmpty {
            let fd = unreportedUncertainty.removeFirst(); poison(scope); retain(fd)
        }
        var first: Error?
        while let fd = openDescriptors.popLast() {
            do { try freshBinding(scope) } catch { if first == nil { first = error }; poison(scope) }
            let result = Darwin.close(fd)
            if result == 0 { closedDescriptors.append(fd) }
            else {
                state = .uncertain; uncertainDescriptors.append(fd); poison(scope); retain(fd)
                if first == nil { first = ProtectedFilePolicyError.identityChanged }
            }
            do { try freshBinding(scope) } catch { if first == nil { first = error }; poison(scope) }
        }
        if let first { throw first }
    }
    fileprivate func complete(scope: OriginalEraseScratchCleanupPolicyEffectScopeV1,
        value: TemporalPolicyObservationV1, fullFact: String) throws {
        try freshBinding(scope)
        guard state == .terminal, openDescriptors.isEmpty, uncertainDescriptors.isEmpty, completed == nil,
              let target, closedDescriptors.count == target.ancestors.count + 1,
              events.count == 2, outcomes.count == 2, acceptedOutcomes.count == 2,
              acceptedOutcomes[0].step == .completeProtection, acceptedOutcomes[1].step == .backupExclusion,
              acceptedOutcomes[1].fullFact == fullFact else { throw ProtectedFilePolicyError.identityChanged }
        for outcome in acceptedOutcomes {
            try requireOutcome(outcome, scope: scope, kind: target.kind, at: target.url, fullFact: outcome.fullFact)
        }
        // Only the private setter invokes this after actual source/policy proof,
        // both genuine Scope step admissions, and finish has RETURNED.
        completed = CompletedPolicy(scopeIdentity: ObjectIdentifier(scope), operationID: scope.operationID,
            requestID: scope.requestID, kind: target.kind, url: target.url, fullFact: fullFact, value: value)
    }
    /// Positive MEMORY-only settlement; no numeric FD read, lifecycle revival,
    /// external lease release or next-effect authority. Refusal/last-pop cannot pass.
    func requireCheckedSettlement(scope: OriginalEraseScratchCleanupPolicyEffectScopeV1,
        kind: OwnedFileKindV1, at url: URL) throws {
        guard state == .terminal, openDescriptors.isEmpty, uncertainDescriptors.isEmpty,
              let completed, completed.scopeIdentity == ObjectIdentifier(scope),
              completed.operationID == scope.operationID, completed.requestID == scope.requestID,
              completed.kind == kind, completed.url == url,
              acceptedOutcomes.count == 2, acceptedOutcomes[1].fullFact == completed.fullFact,
              completed.value.isDirectory == (kind == .stagingDirectory),
              completed.value.backupExcluded == ProtectedFilePolicyV1.disposition(for: kind).isExcludedFromBackup,
              kind == .stagingDirectory || completed.value.linkCount == 1 else {
            throw ProtectedFilePolicyError.identityChanged
        }
        for outcome in acceptedOutcomes {
            try requireOutcome(outcome, scope: scope, kind: kind, at: url, fullFact: outcome.fullFact)
        }
    }
}

/// Separate actor-aware effect boundary, never a read Scope or cold permit.
@MainActor
fileprivate final class OriginalEraseScratchPublicationPolicyContextV1 {
    let scope: OriginalEraseScratchCleanupPolicyEffectScopeV1
    let attempt: OriginalEraseScratchPublicationPolicyAttemptV1
    let target: OriginalEraseScratchTemporalPolicyNodeV1
    private(set) var currentFullFact: String
    private var ancestorFDs: [Int32] = []
    private var descriptor: Int32?
    private let expectedBytes: UInt64
    private let expectedCalls: UInt64
    private var readBytes: UInt64 = 0
    private var readCalls: UInt64 = 0
    init(scope: OriginalEraseScratchCleanupPolicyEffectScopeV1,
        attempt: OriginalEraseScratchPublicationPolicyAttemptV1,
        target: OriginalEraseScratchTemporalPolicyNodeV1) throws {
        self.scope = scope; self.attempt = attempt; self.target = target; currentFullFact = target.fullFact
        guard target.kind == .temporaryFile || target.kind == .stagingDirectory,
              !target.ancestors.isEmpty, target.ancestors[0].url.lastPathComponent == "Operations",
              target.url.isFileURL, target.url.standardizedFileURL == target.url,
              OperationalDiagnosticsBoundsV1.validRelativeName(target.url.lastPathComponent),
              target.fullFact.split(separator: "|", omittingEmptySubsequences: false).count == 11,
              (target.directoryRole != nil) == (target.kind == .stagingDirectory) else {
            throw ProtectedFilePolicyError.invalidURL
        }
        for i in target.ancestors.indices {
            let a = target.ancestors[i]
            guard a.url.isFileURL, a.url.standardizedFileURL == a.url,
                  a.fullFact.split(separator: "|", omittingEmptySubsequences: false).count == 11,
                  i == 0 || (a.url.deletingLastPathComponent() == target.ancestors[i - 1].url &&
                    OperationalDiagnosticsBoundsV1.validRelativeName(a.url.lastPathComponent)) else {
                throw ProtectedFilePolicyError.invalidURL
            }
        }
        let parent = target.ancestors[target.ancestors.count - 1]
        guard target.parentURL == parent.url, target.parentFullFact == parent.fullFact,
              target.url.deletingLastPathComponent() == parent.url else { throw ProtectedFilePolicyError.invalidURL }
        if target.kind == .stagingDirectory {
            guard scope.byteCount == nil, scope.sourceSHA256 == nil else { throw ProtectedFilePolicyError.invalidURL }
            expectedBytes = 0; expectedCalls = 0
        } else {
            guard let b = scope.byteCount, b >= 0, let bytes = UInt64(exactly: b),
                  let sha = scope.sourceSHA256, OperationalDiagnosticsBoundsV1.isLowercaseSHA256(sha),
                  String(b) == target.fullFact.split(separator: "|", omittingEmptySubsequences: false)[6] else {
                throw ProtectedFilePolicyError.invalidURL
            }
            let work = bytes.multipliedReportingOverflow(by: 2), round = bytes.addingReportingOverflow(65_535)
            guard !work.overflow, !round.overflow else { throw ProtectedFilePolicyError.invalidURL }
            let calls = (round.partialValue / 65_536).multipliedReportingOverflow(by: 2)
            guard !calls.overflow else { throw ProtectedFilePolicyError.invalidURL }
            expectedBytes = work.partialValue; expectedCalls = calls.partialValue
        }
        try attempt.bind(scope: scope, target: target)
    }
    private static func fact(_ f: stat) -> String {
        "\(f.st_dev)|\(f.st_ino)|\(f.st_mode)|\(f.st_uid)|\(f.st_gid)|\(f.st_nlink)|\(f.st_size)|\(f.st_mtimespec.tv_sec)|\(f.st_mtimespec.tv_nsec)|\(f.st_ctimespec.tv_sec)|\(f.st_ctimespec.tv_nsec)"
    }
    private static func ctimeOnly(_ actual: String, from prior: String) -> Bool {
        let a = actual.split(separator: "|", omittingEmptySubsequences: false)
        let b = prior.split(separator: "|", omittingEmptySubsequences: false)
        return a.count == 11 && b.count == 11 && a.prefix(9).elementsEqual(b.prefix(9))
    }
    private func boundary() throws { try attempt.freshBinding(scope); try attempt.requireApplying() }
    private func io<Value>(_ body: @MainActor () throws -> Value) throws -> Value {
        try boundary()
        let result: Result<Value, Error>
        do { result = .success(try body()) } catch { result = .failure(error) }
        try boundary(); return try result.get()
    }
    private func open(_ body: @MainActor () -> Int32, retain: (Int32) -> Void) throws -> Int32 {
        try boundary(); let fd = body()
        let remembered: Result<Void, Error>
        if fd >= 0 {
            do { try attempt.remember(fd, scope: scope, retain: retain); remembered = .success(()) }
            catch { remembered = .failure(error) }
        } else { remembered = .failure(ProtectedFilePolicyError.invalidURL) }
        try boundary(); try remembered.get(); return fd
    }
    func openAll(retain: (Int32) -> Void) throws {
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        for i in target.ancestors.indices {
            let fd = try open({ i == 0 ? Darwin.open(target.ancestors[i].url.path, flags) :
                Darwin.openat(ancestorFDs[i - 1], target.ancestors[i].url.lastPathComponent, flags) }, retain: retain)
            ancestorFDs.append(fd); _ = try inspectAncestor(i)
        }
        descriptor = try open({ Darwin.openat(ancestorFDs[ancestorFDs.count - 1], target.url.lastPathComponent,
            O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (target.kind == .stagingDirectory ? O_DIRECTORY : 0)) }, retain: retain)
        _ = try requirePolicyBoundary()
    }
    private func requireOwned(_ held: stat, named: stat, fact: String, directory: Bool, parentFact: String?,
        directoryRole: OriginalEraseScratchPrivateDirectoryRoleV1?) throws {
        let root = target.ancestors[0].fullFact.split(separator: "|", omittingEmptySubsequences: false)
        guard Self.fact(held) == fact, Self.fact(named) == fact,
              held.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
              (directory ? (held.st_mode & 0o7777 == 0o700 || held.st_mode & 0o7777 == 0o2700)
                         : held.st_mode & 0o7777 == 0o600), held.st_uid == Darwin.geteuid(),
              held.st_dev >= 0, String(held.st_dev) == root[0], String(held.st_uid) == root[3] else {
            throw ProtectedFilePolicyError.identityChanged
        }
        if directory {
            guard let directoryRole, directoryRole.admits(fullMode: UInt32(held.st_mode)),
                  directoryRole.recordedFullMode == UInt32(held.st_mode) else { throw ProtectedFilePolicyError.identityChanged }
        } else { guard directoryRole == nil else { throw ProtectedFilePolicyError.identityChanged } }
        if let parentFact {
            let parent = parentFact.split(separator: "|", omittingEmptySubsequences: false)
            guard parent.count == 11, let mode = UInt16(parent[2]), let group = UInt32(parent[4]),
                  held.st_gid == (mode & UInt16(S_ISGID) != 0 ? group : Darwin.getegid()) else {
                throw ProtectedFilePolicyError.identityChanged
            }
        }
    }
    private func inspectAncestor(_ i: Int) throws -> stat {
        var held = stat(), named = stat()
        try io {
            guard Darwin.fstat(ancestorFDs[i], &held) == 0, Self.fact(held) == target.ancestors[i].fullFact else {
                attempt.abandonHeldDescriptor(ancestorFDs[i], scope: scope)
                throw ProtectedFilePolicyError.identityChanged
            }
        }
        try io {
            let result = i == 0 ? Darwin.lstat(target.ancestors[i].url.path, &named) :
                Darwin.fstatat(ancestorFDs[i - 1], target.ancestors[i].url.lastPathComponent, &named, AT_SYMLINK_NOFOLLOW)
            guard result == 0 else { throw ProtectedFilePolicyError.identityChanged }
        }
        try requireOwned(held, named: named, fact: target.ancestors[i].fullFact, directory: true,
            parentFact: i == 0 ? nil : target.ancestors[i - 1].fullFact,
            directoryRole: target.ancestors[i].directoryRole)
        return held
    }
    private func inspectLeaf(allowPolicyCTime: Bool = false) throws -> stat {
        guard let descriptor else { throw ProtectedFilePolicyError.identityChanged }
        var held = stat(), named = stat()
        try io {
            let result = Darwin.fstat(descriptor, &held)
            let actual = Self.fact(held)
            guard result == 0, allowPolicyCTime ? Self.ctimeOnly(actual, from: currentFullFact) : actual == currentFullFact else {
                attempt.abandonHeldDescriptor(descriptor, scope: scope)
                throw ProtectedFilePolicyError.identityChanged
            }
        }
        try io { guard Darwin.fstatat(ancestorFDs[ancestorFDs.count - 1], target.url.lastPathComponent,
            &named, AT_SYMLINK_NOFOLLOW) == 0 else { throw ProtectedFilePolicyError.identityChanged } }
        let actual = Self.fact(held)
        guard !allowPolicyCTime || Self.ctimeOnly(actual, from: currentFullFact) else { throw ProtectedFilePolicyError.identityChanged }
        try requireOwned(held, named: named, fact: allowPolicyCTime ? actual : currentFullFact,
            directory: target.kind == .stagingDirectory, parentFact: target.parentFullFact, directoryRole: target.directoryRole)
        guard target.kind == .stagingDirectory || held.st_nlink == 1 else { throw ProtectedFilePolicyError.hardLink }
        return held
    }
    func requirePolicyBoundary() throws -> stat {
        try boundary()
        guard ancestorFDs.count == target.ancestors.count, descriptor != nil else { throw ProtectedFilePolicyError.identityChanged }
        for i in target.ancestors.indices { _ = try inspectAncestor(i) }
        let held = try inspectLeaf(); try boundary(); return held
    }
    func streamSource() throws {
        _ = try requirePolicyBoundary()
        guard target.kind == .temporaryFile else { return }
        guard let descriptor, let count = scope.byteCount, let sha = scope.sourceSHA256 else {
            throw ProtectedFilePolicyError.identityChanged
        }
        var digest = SHA256(), offset: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while offset < count {
            _ = try requirePolicyBoundary()
            let wanted = Int(min(Int64(buffer.count), count - offset))
            let calls = readCalls.addingReportingOverflow(1)
            guard !calls.overflow, calls.partialValue <= expectedCalls else { throw ProtectedFilePolicyError.identityChanged }
            readCalls = calls.partialValue
            let got = try io { buffer.withUnsafeMutableBytes { Darwin.pread(descriptor, $0.baseAddress!, wanted, off_t(offset)) } }
            guard got == wanted else { throw ProtectedFilePolicyError.identityChanged }
            let bytes = readBytes.addingReportingOverflow(UInt64(got))
            guard !bytes.overflow, bytes.partialValue <= expectedBytes else { throw ProtectedFilePolicyError.identityChanged }
            readBytes = bytes.partialValue
            buffer.withUnsafeBytes { digest.update(bufferPointer: UnsafeRawBufferPointer(start: $0.baseAddress, count: wanted)) }
            offset += Int64(wanted); _ = try requirePolicyBoundary()
        }
        guard offset == count, digest.finalize().map({ String(format: "%02x", $0) }).joined() == sha else {
            throw ProtectedFilePolicyError.identityChanged
        }
        _ = try requirePolicyBoundary()
    }
    func requireCompletedWork() throws {
        guard readBytes == expectedBytes, readCalls == expectedCalls else { throw ProtectedFilePolicyError.identityChanged }
        _ = try requirePolicyBoundary()
    }
    func perform(_ step: OriginalEraseScratchPublicationPolicyStepV1) throws -> OriginalEraseScratchPublicationPolicyOutcomeV1 {
        _ = try requirePolicyBoundary(); try attempt.requireNextStep(step)
        let result: Result<Void, Error>
        do {
            switch step {
            case .completeProtection:
                try (target.url as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
            case .backupExclusion:
                var values = URLResourceValues()
                values.isExcludedFromBackup = ProtectedFilePolicyV1.disposition(for: target.kind).isExcludedFromBackup
                var writable = target.url
                try writable.setResourceValues(values)
            }
            result = .success(())
        } catch { result = .failure(error) }
        // Save the real call event BEFORE any issuer callback, including errors.
        let event = OriginalEraseScratchPublicationPolicyEventV1(step: step, result: result)
        try attempt.record(event); try boundary()
        try event.result.get()
        for i in target.ancestors.indices { _ = try inspectAncestor(i) }
        let actual = try inspectLeaf(allowPolicyCTime: true)
        let postFact = Self.fact(actual)
        let outcome = try attempt.capture(event, fullFact: postFact)
        try scope.requireOwnedPolicyPostFact(fullFact: postFact, outcome: outcome)
        try boundary(); try attempt.accept(outcome, scope: scope)
        currentFullFact = postFact
        _ = try requirePolicyBoundary(); return outcome
    }
}

extension ProtectedFilePolicyV1 {
    /// This path must never call verify/applyAndVerify or emit a success
    /// disposition. It independently reads Foundation metadata between held
    /// and named identity checks and does not populate the caller URL cache.
    static func observeTemporalPolicy(_ kind: OwnedFileKindV1, at url: URL)
        throws -> TemporalPolicyObservationV1 {
        let expected = disposition(for: kind)
        let before = try pin(kind, at: url, disposition: expected)
        let flags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
            | (expected.expectsDirectory ? O_DIRECTORY : 0)
        let descriptor = Darwin.open(url.path, flags)
        guard descriptor >= 0 else { throw ProtectedFilePolicyError.invalidURL }
        defer { Darwin.close(descriptor) }
        func reproveHeld() throws {
            var held = stat()
            guard Darwin.fstat(descriptor, &held) == 0,
                  held.st_dev == before.device, held.st_ino == before.inode,
                  held.st_nlink == before.linkCount,
                  (held.st_mode & S_IFMT) == (expected.expectsDirectory ? S_IFDIR : S_IFREG) else {
                throw ProtectedFilePolicyError.identityChanged
            }
        }
        try reproveHeld()
        let result = try readTemporalPolicy(kind, at: url,
            expectedDevice: UInt64(before.device), expectedInode: UInt64(before.inode),
            expectedLinkCount: UInt64(before.linkCount))
        try reproveHeld()
        guard try pin(kind, at: url, disposition: expected) == before else {
            throw ProtectedFilePolicyError.identityChanged
        }
        return result
    }

    /// A retained owner can observe the unchanged temporal policy while
    /// accounting for ambiguous closes of this helper's transient descriptors.
    /// Existing ordinary callers above retain their established behavior.
    /// On a failed close the supplied exact owner keeps the FD number as
    /// terminal uncertainty; neither helper nor owner retries that close.
    static func observeTemporalPolicyWithCheckedClose(
        _ kind: OwnedFileKindV1, at url: URL,
        retainUncertainDescriptor: (Int32) -> Void
    ) throws -> TemporalPolicyObservationV1 {
        let expected = disposition(for: kind)
        let before = try pinForRestoreExit(kind, at: url,
            disposition: expected,
            retainUncertainDescriptor: retainUncertainDescriptor)
        let flags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
            | (expected.expectsDirectory ? O_DIRECTORY : 0)
        return try withRestoreExitDescriptor(
            path: url.path, flags: flags,
            retainUncertainDescriptor: retainUncertainDescriptor) { descriptor in
            func reproveHeld() throws {
                var held = stat()
                guard Darwin.fstat(descriptor, &held) == 0,
                      held.st_dev == before.device, held.st_ino == before.inode,
                      held.st_nlink == before.linkCount,
                      (held.st_mode & S_IFMT) == (expected.expectsDirectory ? S_IFDIR : S_IFREG) else {
                    throw ProtectedFilePolicyError.identityChanged
                }
            }
            try reproveHeld()
            let result = try readTemporalPolicy(kind, at: url,
                expectedDevice: UInt64(before.device),
                expectedInode: UInt64(before.inode),
                expectedLinkCount: UInt64(before.linkCount))
            try reproveHeld()
            guard try pinForRestoreExit(kind, at: url,
                disposition: expected,
                retainUncertainDescriptor: retainUncertainDescriptor) == before else {
                throw ProtectedFilePolicyError.identityChanged
            }
            return result
        }
    }

    private static func withRestoreExitDescriptor<Value>(
        path: String, flags: Int32,
        retainUncertainDescriptor: (Int32) -> Void,
        openFailure: () -> Error = { ProtectedFilePolicyError.invalidURL },
        _ body: (Int32) throws -> Value
    ) throws -> Value {
        let descriptor = Darwin.open(path, flags)
        guard descriptor >= 0 else { throw openFailure() }
        var closeAttempted = false
        do {
            let result = try body(descriptor)
            closeAttempted = true
            guard Darwin.close(descriptor) == 0 else {
                retainUncertainDescriptor(descriptor)
                throw ProtectedFilePolicyError.identityChanged
            }
            return result
        } catch {
            if !closeAttempted {
                closeAttempted = true
                guard Darwin.close(descriptor) == 0 else {
                    retainUncertainDescriptor(descriptor)
                    throw ProtectedFilePolicyError.identityChanged
                }
            }
            throw error
        }
    }

    private static func pinForRestoreExit(
        _ kind: OwnedFileKindV1, at url: URL,
        disposition: OwnedFileProtectionDispositionV1,
        retainUncertainDescriptor: (Int32) -> Void
    ) throws -> LeafIdentity {
        guard url.isFileURL else { throw ProtectedFilePolicyError.invalidURL }
        var inspected = stat()
        guard Darwin.lstat(url.path, &inspected) == 0 else {
            if errno == ENOENT { throw ProtectedFilePolicyError.missing }
            if errno == ELOOP { throw ProtectedFilePolicyError.symbolicLink }
            throw ProtectedFilePolicyError.invalidURL
        }
        let type = inspected.st_mode & S_IFMT
        if type == S_IFLNK { throw ProtectedFilePolicyError.symbolicLink }
        guard (disposition.expectsDirectory && type == S_IFDIR) ||
              (!disposition.expectsDirectory && type == S_IFREG) else {
            throw ProtectedFilePolicyError.invalidType
        }
        if !disposition.expectsDirectory && inspected.st_nlink != 1 {
            throw ProtectedFilePolicyError.hardLink
        }
        let flags = disposition.expectsDirectory
            ? O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            : O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        return try withRestoreExitDescriptor(
            path: url.path, flags: flags,
            retainUncertainDescriptor: retainUncertainDescriptor,
            openFailure: {
                if errno == ENOENT { return ProtectedFilePolicyError.missing }
                if errno == ELOOP { return ProtectedFilePolicyError.symbolicLink }
                if errno == EACCES || errno == EPERM {
                    return ProtectedFilePolicyError.protectedDataUnavailable
                }
                return ProtectedFilePolicyError.invalidURL
            }) { descriptor in
            var actual = stat()
            guard Darwin.fstat(descriptor, &actual) == 0 else {
                throw ProtectedFilePolicyError.invalidURL
            }
            guard (actual.st_mode & S_IFMT) == type else {
                throw ProtectedFilePolicyError.identityChanged
            }
            if !disposition.expectsDirectory && actual.st_nlink != 1 {
                throw ProtectedFilePolicyError.hardLink
            }
            let identity = LeafIdentity(device: actual.st_dev, inode: actual.st_ino,
                linkCount: actual.st_nlink)
            guard identity.device == inspected.st_dev,
                  identity.inode == inspected.st_ino,
                  identity.linkCount == inspected.st_nlink else {
                throw ProtectedFilePolicyError.identityChanged
            }
            _ = kind
            return identity
        }
    }

    /// Narrow census observation for the actual two names of one scratch
    /// final/partial inode. No caller-selected link-count exemption exists.
    /// This is not accepted policy and does not authorize a setter/removal.
    static func observeTemporalScratchPair(finalURL: URL, partialURL: URL)
        throws -> [TemporalPolicyObservationV1] {
        let parent = finalURL.deletingLastPathComponent()
        let partialName = partialURL.lastPathComponent
        guard finalURL.isFileURL, partialURL.isFileURL,
              parent == partialURL.deletingLastPathComponent(),
              OperationalDiagnosticsBoundsV1.validRelativeName(finalURL.lastPathComponent),
              !finalURL.lastPathComponent.hasPrefix(".partial-"),
              partialName.hasPrefix(".partial-"),
              let id = UUID(uuidString: String(partialName.dropFirst(9))),
              partialName == ".partial-" + id.uuidString.lowercased() else {
            throw ProtectedFilePolicyError.invalidURL
        }
        let parentFD = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parentFD >= 0 else { throw ProtectedFilePolicyError.invalidURL }
        defer { Darwin.close(parentFD) }
        let finalFD = Darwin.openat(parentFD, finalURL.lastPathComponent,
            O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard finalFD >= 0 else { throw ProtectedFilePolicyError.invalidURL }
        defer { Darwin.close(finalFD) }
        let partialFD = Darwin.openat(parentFD, partialName,
            O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard partialFD >= 0 else { throw ProtectedFilePolicyError.invalidURL }
        defer { Darwin.close(partialFD) }
        func inspect(_ fd: Int32, name: String) throws -> stat {
            var held = stat(), named = stat()
            guard Darwin.fstat(fd, &held) == 0,
                  Darwin.fstatat(parentFD, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  (held.st_mode & S_IFMT) == S_IFREG, held.st_nlink == 2,
                  named.st_dev == held.st_dev, named.st_ino == held.st_ino,
                  named.st_mode == held.st_mode, named.st_nlink == held.st_nlink else {
                throw ProtectedFilePolicyError.identityChanged
            }
            return held
        }
        let first = try inspect(finalFD, name: finalURL.lastPathComponent)
        let second = try inspect(partialFD, name: partialName)
        guard first.st_dev == second.st_dev, first.st_ino == second.st_ino else {
            throw ProtectedFilePolicyError.hardLink
        }
        let values = try [finalURL, partialURL].map {
            try readTemporalPolicy(.temporaryFile, at: $0,
                expectedDevice: UInt64(first.st_dev), expectedInode: UInt64(first.st_ino),
                expectedLinkCount: 2)
        }
        let afterFirst = try inspect(finalFD, name: finalURL.lastPathComponent)
        let afterSecond = try inspect(partialFD, name: partialName)
        guard afterFirst.st_dev == first.st_dev, afterFirst.st_ino == first.st_ino,
              afterSecond.st_dev == first.st_dev, afterSecond.st_ino == first.st_ino else {
            throw ProtectedFilePolicyError.identityChanged
        }
        return values
    }


    /// Exact LIVE owned single/root policy. The genuine scope refuses an
    /// unaccepted active temporary until its actual policy request succeeds.
    @MainActor
    static func observeOriginalEraseScratchTemporalPolicyWithCheckedClose(
        _ kind: OwnedFileKindV1, at url: URL, fullFact: String,
        scope: OriginalEraseScratchTemporalObservationScopeV1,
        retainUncertainDescriptor: (Int32) -> Void
    ) throws -> TemporalPolicyObservationV1 {
        let attempt = OriginalEraseScratchTemporalPolicyAttemptV1()
        scope.retainObservationAttempt(attempt) // Before any getter/acquisition IO.
        do {
            try scope.requireCurrentBinding()
            let node = try scope.requirePolicyNode(kind, at: url, fullFact: fullFact)
            guard node.kind == kind, node.url == url, node.fullFact == fullFact else {
                throw ProtectedFilePolicyError.identityChanged
            }
            let context = try OriginalEraseScratchTemporalPolicyReadContextV1(
                scope: scope, attempt: attempt, selection: .node(node))
            let values = try readOriginalEraseScratchPolicies(context, retain: retainUncertainDescriptor)
            guard values.count == 1 else { throw ProtectedFilePolicyError.identityChanged }
            try attempt.finish(scope: scope, retain: retainUncertainDescriptor)
            try scope.requireCurrentBinding(); try attempt.requireCheckedObservationTerminal()
            try attempt.acceptCompleted(scope: scope, values: values)
            try attempt.requireCheckedSettlement()
            return values[0]
        } catch {
            try finishOriginalEraseScratchRefusal(attempt, scope: scope, retain: retainUncertainDescriptor)
            throw error
        }
    }
    /// Exact LIVE two-name publication/original DATA role, not an ordinary
    /// nlink exception. No historical final, future receipt or cold origin is
    /// guessed. Returned pending Simulator state is observation only.
    @MainActor
    static func observeOriginalEraseScratchTemporalPairWithCheckedClose(
        aliasURLs: [URL], scope: OriginalEraseScratchTemporalObservationScopeV1,
        retainUncertainDescriptor: (Int32) -> Void
    ) throws -> [TemporalPolicyObservationV1] {
        let attempt = OriginalEraseScratchTemporalPolicyAttemptV1()
        scope.retainObservationAttempt(attempt) // Before any getter/acquisition IO.
        do {
            try scope.requireCurrentBinding()
            let pair = try scope.requirePair(aliasURLs: aliasURLs)
            let context = try OriginalEraseScratchTemporalPolicyReadContextV1(
                scope: scope, attempt: attempt, selection: .pair(pair, aliasURLs))
            let values = try readOriginalEraseScratchPolicies(context, retain: retainUncertainDescriptor)
            guard values.count == 2, values[0] == values[1] else { throw ProtectedFilePolicyError.resourceValueMismatch }
            try attempt.finish(scope: scope, retain: retainUncertainDescriptor)
            try scope.requireCurrentBinding(); try attempt.requireCheckedObservationTerminal()
            try attempt.acceptCompleted(scope: scope, values: values)
            try attempt.requireCheckedSettlement()
            return values
        } catch {
            try finishOriginalEraseScratchRefusal(attempt, scope: scope, retain: retainUncertainDescriptor)
            throw error
        }
    }
    @MainActor
    private static func finishOriginalEraseScratchRefusal(_ attempt: OriginalEraseScratchTemporalPolicyAttemptV1,
        scope: OriginalEraseScratchTemporalObservationScopeV1, retain: (Int32) -> Void) throws {
        if attempt.needsFinish {
            do { try attempt.finish(scope: scope, retain: retain) }
            catch { attempt.poison(scope: scope); throw error }
        }
        attempt.poison(scope: scope)
    }
    @MainActor
    private static func readOriginalEraseScratchPolicies(_ context: OriginalEraseScratchTemporalPolicyReadContextV1,
        retain: (Int32) -> Void) throws -> [TemporalPolicyObservationV1] {
        try context.openAll(retain: retain)
        var values: [TemporalPolicyObservationV1] = []
        for leaf in context.leaves {
            let before = try context.requireUnchangedPolicyInput()
            let value = try readOriginalEraseScratchTemporalPolicy(context.kind, at: leaf.url,
                expectedDevice: UInt64(before.st_dev), expectedInode: UInt64(before.st_ino),
                expectedLinkCount: UInt64(before.st_nlink), context: context)
            _ = try context.requireUnchangedPolicyInput()
            values.append(value)
        }
        try context.requireCompletedPayloadWork()
        return values
    }

    @MainActor
    private static func readOriginalEraseScratchTemporalPolicy(_ kind: OwnedFileKindV1, at url: URL,
        expectedDevice: UInt64, expectedInode: UInt64, expectedLinkCount: UInt64,
        context: OriginalEraseScratchTemporalPolicyReadContextV1)
        throws -> TemporalPolicyObservationV1 {
        let expected = disposition(for: kind)
        var independent = URL(fileURLWithPath: url.path)
        independent.removeAllCachedResourceValues()
        let values: URLResourceValues
        let attributes: [FileAttributeKey: Any]
        _ = try context.requirePolicyBoundary()
        do {
            values = try independent.resourceValues(forKeys: [.fileProtectionKey,
                .isExcludedFromBackupKey, .isDirectoryKey, .volumeSupportsFileProtectionKey])
        } catch { _ = try context.requirePolicyBoundary(); throw mapWriteError(error) }
        _ = try context.requirePolicyBoundary()
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch { _ = try context.requirePolicyBoundary(); throw mapWriteError(error) }
        _ = try context.requirePolicyBoundary()
        func protectionName(_ value: URLFileProtection?) -> String {
            switch value {
            case .some(.complete): return "complete"
            case .some(.completeUnlessOpen): return "completeUnlessOpen"
            case .some(.completeUntilFirstUserAuthentication): return "completeUntilFirstUserAuthentication"
            case .some(.none): return "none"
            case nil: return "unknown"
            default: return "other"
            }
        }
        let managerProtection: String
        switch attributes[.protectionKey] as? FileProtectionType {
        case .some(.complete): managerProtection = "complete"
        case .some(.completeUnlessOpen): managerProtection = "completeUnlessOpen"
        case .some(.completeUntilFirstUserAuthentication): managerProtection = "completeUntilFirstUserAuthentication"
        case .some(.none): managerProtection = "none"
        case nil: managerProtection = "unknown"
        default: managerProtection = "other"
        }
        var named = stat()
        _ = try context.requirePolicyBoundary()
        let namedResult = Darwin.lstat(url.path, &named)
        _ = try context.requirePolicyBoundary()
        guard namedResult == 0,
              UInt64(named.st_dev) == expectedDevice, UInt64(named.st_ino) == expectedInode,
              UInt64(named.st_nlink) == expectedLinkCount,
              (named.st_mode & S_IFMT) == (expected.expectsDirectory ? S_IFDIR : S_IFREG),
              attributes[.type] as? FileAttributeType == (expected.expectsDirectory ? .typeDirectory : .typeRegular),
              values.isDirectory == expected.expectsDirectory,
              values.isExcludedFromBackup == expected.isExcludedFromBackup else {
            throw ProtectedFilePolicyError.resourceValueMismatch
        }
        let capability = values.allValues[.volumeSupportsFileProtectionKey] as? Bool
        let state: TemporalPolicyObservationV1.State
        if values.fileProtection == .complete {
            state = .strictComplete
        } else {
#if DEBUG && os(iOS) && targetEnvironment(simulator)
            let readback = DirectoryProtectionReadback(urlProtection: protectionName(values.fileProtection),
                fileManagerProtection: managerProtection, backupExcluded: values.isExcludedFromBackup,
                isDirectory: values.isDirectory, volumeSupportsProtection: capability)
            guard simulatorReadbackIsExactFallback(readback, disposition: expected) else {
                throw ProtectedFilePolicyError.resourceValueMismatch
            }
            state = .pendingSimulatorRequest
#else
            throw ProtectedFilePolicyError.resourceValueMismatch
#endif
        }
        return TemporalPolicyObservationV1(state: state, device: expectedDevice,
            inode: expectedInode, linkCount: expectedLinkCount, mode: UInt16(named.st_mode),
            urlProtection: protectionName(values.fileProtection), fileManagerProtection: managerProtection,
            backupExcluded: values.isExcludedFromBackup, isDirectory: values.isDirectory,
            volumeSupportsProtection: capability)
    }

    /// The exact active LIVE policy request, privately issued by the image
    /// owner. A read-only observation Scope can never call this setter.
    @MainActor
    static func applyOriginalEraseScratchPublicationPolicyWithCheckedClose(
        _ kind: OwnedFileKindV1, at url: URL, initialFullFact: String,
        scope: OriginalEraseScratchCleanupPolicyEffectScopeV1,
        retainUncertainDescriptor: (Int32) -> Void
    ) throws -> TemporalPolicyObservationV1 {
        let attempt = OriginalEraseScratchPublicationPolicyAttemptV1()
        scope.retainPolicyAttempt(attempt) // Retain actual owner before first getter/open.
        do {
            try scope.requireCurrentBinding()
            let target = try scope.requireTarget(kind, at: url, initialFullFact: initialFullFact)
            guard target.kind == kind, target.url == url, target.fullFact == initialFullFact else {
                throw ProtectedFilePolicyError.identityChanged
            }
            let context = try OriginalEraseScratchPublicationPolicyContextV1(scope: scope, attempt: attempt, target: target)
            try context.openAll(retain: retainUncertainDescriptor)
            #if DEBUG && os(iOS) && targetEnvironment(simulator)
            var independent = URL(fileURLWithPath: url.path)
            independent.removeAllCachedResourceValues()
            _ = try context.requirePolicyBoundary()
            let capabilityBefore: Bool?
            do {
                capabilityBefore = try independent.resourceValues(forKeys: [.volumeSupportsFileProtectionKey])
                    .allValues[.volumeSupportsFileProtectionKey] as? Bool
            } catch { _ = try context.requirePolicyBoundary(); throw mapWriteError(error) }
            _ = try context.requirePolicyBoundary()
            #endif
            try context.streamSource()
            let protection = try context.perform(.completeProtection)
            let backup = try context.perform(.backupExclusion)
            let held = try context.requirePolicyBoundary()
            let value = try readOriginalEraseScratchPublicationPolicy(kind, at: url,
                expectedDevice: UInt64(held.st_dev), expectedInode: UInt64(held.st_ino),
                expectedLinkCount: UInt64(held.st_nlink), context: context)
            try context.streamSource(); try context.requireCompletedWork()
            try protection.requireBound(scope: scope, kind: kind, at: url, fullFact: protection.fullFact)
            try backup.requireBound(scope: scope, kind: kind, at: url, fullFact: backup.fullFact)
            #if DEBUG && os(iOS) && targetEnvironment(simulator)
            if value.state == .pendingSimulatorRequest {
                let readback = DirectoryProtectionReadback(urlProtection: value.urlProtection,
                    fileManagerProtection: value.fileManagerProtection, backupExcluded: value.backupExcluded,
                    isDirectory: value.isDirectory, volumeSupportsProtection: value.volumeSupportsProtection)
                // Both flags derive this call's real events and full held/named
                // ctime-only proof, never a caller success Boolean.
                guard simulatorDiagnosticAllows(capabilityBefore: capabilityBefore, after: readback,
                    disposition: disposition(for: kind), successfulCompleteRequest: true,
                    identityUnchanged: true) else { throw ProtectedFilePolicyError.resourceValueMismatch }
                _ = try context.requirePolicyBoundary()
                do { try emitVerificationDisposition(.simulatorFileProtectionUnsupported, kind: kind) }
                catch { _ = try context.requirePolicyBoundary(); throw error }
                _ = try context.requirePolicyBoundary()
            }
            #endif
            _ = try context.requirePolicyBoundary()
            let finalFact = context.currentFullFact
            try attempt.finish(scope: scope, retain: retainUncertainDescriptor)
            try scope.requireCurrentBinding()
            try attempt.complete(scope: scope, value: value, fullFact: finalFact)
            try attempt.requireCheckedSettlement(scope: scope, kind: kind, at: url)
            return value
        } catch {
            if attempt.needsFinish {
                do { try attempt.finish(scope: scope, retain: retainUncertainDescriptor) }
                catch { attempt.poison(scope); throw error }
            }
            attempt.poison(scope)
            if let error = error as? ProtectedFilePolicyError { throw error }
            throw mapWriteError(error)
        }
    }

    @MainActor
    private static func readOriginalEraseScratchPublicationPolicy(_ kind: OwnedFileKindV1, at url: URL,
        expectedDevice: UInt64, expectedInode: UInt64, expectedLinkCount: UInt64,
        context: OriginalEraseScratchPublicationPolicyContextV1)
        throws -> TemporalPolicyObservationV1 {
        let expected = disposition(for: kind)
        var independent = URL(fileURLWithPath: url.path)
        independent.removeAllCachedResourceValues()
        let values: URLResourceValues
        let attributes: [FileAttributeKey: Any]
        _ = try context.requirePolicyBoundary()
        do {
            values = try independent.resourceValues(forKeys: [.fileProtectionKey,
                .isExcludedFromBackupKey, .isDirectoryKey, .volumeSupportsFileProtectionKey])
        } catch { _ = try context.requirePolicyBoundary(); throw mapWriteError(error) }
        _ = try context.requirePolicyBoundary()
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch { _ = try context.requirePolicyBoundary(); throw mapWriteError(error) }
        _ = try context.requirePolicyBoundary()
        func protectionName(_ value: URLFileProtection?) -> String {
            switch value {
            case .some(.complete): return "complete"
            case .some(.completeUnlessOpen): return "completeUnlessOpen"
            case .some(.completeUntilFirstUserAuthentication): return "completeUntilFirstUserAuthentication"
            case .some(.none): return "none"
            case nil: return "unknown"
            default: return "other"
            }
        }
        let managerProtection: String
        switch attributes[.protectionKey] as? FileProtectionType {
        case .some(.complete): managerProtection = "complete"
        case .some(.completeUnlessOpen): managerProtection = "completeUnlessOpen"
        case .some(.completeUntilFirstUserAuthentication): managerProtection = "completeUntilFirstUserAuthentication"
        case .some(.none): managerProtection = "none"
        case nil: managerProtection = "unknown"
        default: managerProtection = "other"
        }
        var named = stat()
        _ = try context.requirePolicyBoundary()
        let namedResult = Darwin.lstat(url.path, &named)
        _ = try context.requirePolicyBoundary()
        guard namedResult == 0,
              UInt64(named.st_dev) == expectedDevice, UInt64(named.st_ino) == expectedInode,
              UInt64(named.st_nlink) == expectedLinkCount,
              (named.st_mode & S_IFMT) == (expected.expectsDirectory ? S_IFDIR : S_IFREG),
              attributes[.type] as? FileAttributeType == (expected.expectsDirectory ? .typeDirectory : .typeRegular),
              values.isDirectory == expected.expectsDirectory,
              values.isExcludedFromBackup == expected.isExcludedFromBackup else {
            throw ProtectedFilePolicyError.resourceValueMismatch
        }
        let capability = values.allValues[.volumeSupportsFileProtectionKey] as? Bool
        let state: TemporalPolicyObservationV1.State
        if values.fileProtection == .complete {
            state = .strictComplete
        } else {
#if DEBUG && os(iOS) && targetEnvironment(simulator)
            let readback = DirectoryProtectionReadback(urlProtection: protectionName(values.fileProtection),
                fileManagerProtection: managerProtection, backupExcluded: values.isExcludedFromBackup,
                isDirectory: values.isDirectory, volumeSupportsProtection: capability)
            guard simulatorReadbackIsExactFallback(readback, disposition: expected) else {
                throw ProtectedFilePolicyError.resourceValueMismatch
            }
            state = .pendingSimulatorRequest
#else
            throw ProtectedFilePolicyError.resourceValueMismatch
#endif
        }
        return TemporalPolicyObservationV1(state: state, device: expectedDevice,
            inode: expectedInode, linkCount: expectedLinkCount, mode: UInt16(named.st_mode),
            urlProtection: protectionName(values.fileProtection), fileManagerProtection: managerProtection,
            backupExcluded: values.isExcludedFromBackup, isDirectory: values.isDirectory,
            volumeSupportsProtection: capability)
    }

    private static func readTemporalPolicy(_ kind: OwnedFileKindV1, at url: URL,
        expectedDevice: UInt64, expectedInode: UInt64, expectedLinkCount: UInt64)
        throws -> TemporalPolicyObservationV1 {
        let expected = disposition(for: kind)
        var independent = URL(fileURLWithPath: url.path)
        independent.removeAllCachedResourceValues()
        let values: URLResourceValues
        let attributes: [FileAttributeKey: Any]
        do {
            values = try independent.resourceValues(forKeys: [.fileProtectionKey,
                .isExcludedFromBackupKey, .isDirectoryKey, .volumeSupportsFileProtectionKey])
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch { throw mapWriteError(error) }
        func protectionName(_ value: URLFileProtection?) -> String {
            switch value {
            case .some(.complete): return "complete"
            case .some(.completeUnlessOpen): return "completeUnlessOpen"
            case .some(.completeUntilFirstUserAuthentication): return "completeUntilFirstUserAuthentication"
            case .some(.none): return "none"
            case nil: return "unknown"
            default: return "other"
            }
        }
        let managerProtection: String
        switch attributes[.protectionKey] as? FileProtectionType {
        case .some(.complete): managerProtection = "complete"
        case .some(.completeUnlessOpen): managerProtection = "completeUnlessOpen"
        case .some(.completeUntilFirstUserAuthentication): managerProtection = "completeUntilFirstUserAuthentication"
        case .some(.none): managerProtection = "none"
        case nil: managerProtection = "unknown"
        default: managerProtection = "other"
        }
        var named = stat()
        guard Darwin.lstat(url.path, &named) == 0,
              UInt64(named.st_dev) == expectedDevice, UInt64(named.st_ino) == expectedInode,
              UInt64(named.st_nlink) == expectedLinkCount,
              (named.st_mode & S_IFMT) == (expected.expectsDirectory ? S_IFDIR : S_IFREG),
              attributes[.type] as? FileAttributeType == (expected.expectsDirectory ? .typeDirectory : .typeRegular),
              values.isDirectory == expected.expectsDirectory,
              values.isExcludedFromBackup == expected.isExcludedFromBackup else {
            throw ProtectedFilePolicyError.resourceValueMismatch
        }
        let capability = values.allValues[.volumeSupportsFileProtectionKey] as? Bool
        let state: TemporalPolicyObservationV1.State
        if values.fileProtection == .complete {
            state = .strictComplete
        } else {
#if DEBUG && os(iOS) && targetEnvironment(simulator)
            let readback = DirectoryProtectionReadback(urlProtection: protectionName(values.fileProtection),
                fileManagerProtection: managerProtection, backupExcluded: values.isExcludedFromBackup,
                isDirectory: values.isDirectory, volumeSupportsProtection: capability)
            guard simulatorReadbackIsExactFallback(readback, disposition: expected) else {
                throw ProtectedFilePolicyError.resourceValueMismatch
            }
            state = .pendingSimulatorRequest
#else
            throw ProtectedFilePolicyError.resourceValueMismatch
#endif
        }
        return TemporalPolicyObservationV1(state: state, device: expectedDevice,
            inode: expectedInode, linkCount: expectedLinkCount, mode: UInt16(named.st_mode),
            urlProtection: protectionName(values.fileProtection), fileManagerProtection: managerProtection,
            backupExcluded: values.isExcludedFromBackup, isDirectory: values.isDirectory,
            volumeSupportsProtection: capability)
    }
}

extension ProtectedFilePolicyV1 {
    /// Observation-only verification for a private Erase-owned scratch leaf.
    /// This has the same resource-value predicate as `verify`, while every
    /// transient identity pin uses the checked-close owner.
    @discardableResult
    static func verifyEraseColdPrivateWithCheckedClose(
        _ kind: OwnedFileKindV1,
        at url: URL,
        retainUncertainDescriptor: (Int32) -> Void
    ) throws -> ProtectedFileVerificationDispositionV1 {
        let expected = disposition(for: kind)
        let identity = try pinForRestoreExit(kind, at: url,
            disposition: expected,
            retainUncertainDescriptor: retainUncertainDescriptor)
        let result: ProtectedFileVerificationDispositionV1
        #if DEBUG && os(iOS) && targetEnvironment(simulator)
        result = try verifySimulatorResourceValues(kind, at: url,
            disposition: expected, identity: identity,
            successfulRequestReadback: nil)
        #else
        try verifyResourceValues(at: url, disposition: expected)
        result = .verifiedComplete
        #endif
        try emitVerificationDisposition(result, kind: kind)
        return result
    }

    /// The C05 private validation copy is newly owned staging, so its exact
    /// files still receive the ordinary complete/backup policy request. This
    /// variant replaces only the original unchecked transient pin closes with
    /// the retained checked-close primitive; established callers are intact.
    @discardableResult
    static func applyAndVerifyEraseColdPrivateWithCheckedClose(
        _ kind: OwnedFileKindV1,
        at url: URL,
        retainUncertainDescriptor: (Int32) -> Void,
        authorityCheck: () throws -> Void,
        beforeFirstEffect: (() throws -> Void)? = nil
    ) throws -> ProtectedFileVerificationDispositionV1 {
        let expected = disposition(for: kind)
        try authorityCheck()
        let before = try pinForRestoreExit(kind, at: url,
            disposition: expected,
            retainUncertainDescriptor: retainUncertainDescriptor)
        try beforeFirstEffect?()
        #if DEBUG && os(iOS) && targetEnvironment(simulator)
        let beforeRequest = independentProtectionReadback(at: url)
        #endif
        do {
            try (url as NSURL).setResourceValue(URLFileProtection.complete,
                forKey: .fileProtectionKey)
            var fresh = URL(fileURLWithPath: url.path)
            fresh.removeAllCachedResourceValues()
            let backup = try fresh.resourceValues(
                forKeys: [.isExcludedFromBackupKey]
            ).isExcludedFromBackup
            if backup != expected.isExcludedFromBackup {
                var values = URLResourceValues()
                values.isExcludedFromBackup = expected.isExcludedFromBackup
                var writable = url
                try writable.setResourceValues(values)
            }
        } catch {
            throw mapWriteError(error)
        }
        try authorityCheck()
        let after = try pinForRestoreExit(kind, at: url,
            disposition: expected,
            retainUncertainDescriptor: retainUncertainDescriptor)
        guard before == after else {
            throw ProtectedFilePolicyError.identityChanged
        }
        let result: ProtectedFileVerificationDispositionV1
        #if DEBUG && os(iOS) && targetEnvironment(simulator)
        if try simulatorStrictResourceValuesMatch(at: url,
            disposition: expected) {
            result = .verifiedComplete
        } else {
            let readback = independentProtectionReadback(at: url)
            guard simulatorDiagnosticAllows(
                capabilityBefore: beforeRequest.volumeSupportsProtection,
                after: readback, disposition: expected,
                successfulCompleteRequest: true,
                identityUnchanged: true) else {
                throw ProtectedFilePolicyError.resourceValueMismatch
            }
            result = .simulatorFileProtectionUnsupported
        }
        #else
        try verifyResourceValues(at: url, disposition: expected)
        result = .verifiedComplete
        #endif
        try authorityCheck()
        guard try pinForRestoreExit(kind, at: url,
                disposition: expected,
                retainUncertainDescriptor: retainUncertainDescriptor)
                == before else {
            throw ProtectedFilePolicyError.identityChanged
        }
        try emitVerificationDisposition(result, kind: kind)
        return result
    }

    /// One Erase-cold read/effect boundary. A pending DEBUG Simulator shape
    /// makes a *new* complete-protection request on this exact leaf; it never
    /// becomes a cached strict policy result. The caller's witness must cover
    /// its held/named metadata and canonical bytes or directory names.
    static func verifyEraseColdTemporalPolicyWithCheckedRequest<Witness: Equatable>(
        _ kind: OwnedFileKindV1,
        at url: URL,
        retainUncertainDescriptor: (Int32) -> Void,
        willRequestCompleteProtection: () throws -> Void = {},
        unchangedWitness: () throws -> Witness
    ) throws -> ProtectedFileVerificationDispositionV1 {
        var diagnosticStage = "initial-witness"
        do {
        let original = try unchangedWitness()
        diagnosticStage = "initial-checked-policy-observation"
        let initial = try observeTemporalPolicyWithCheckedClose(kind,
            at: url, retainUncertainDescriptor: retainUncertainDescriptor)
        diagnosticStage = "initial-witness-reproof"
        guard try unchangedWitness() == original else {
            throw ProtectedFilePolicyError.identityChanged
        }
        if initial.state == .strictComplete {
            diagnosticStage = "strict-checked-policy-reproof"
            let after = try observeTemporalPolicyWithCheckedClose(kind,
                at: url, retainUncertainDescriptor: retainUncertainDescriptor)
            guard after == initial,
                  try unchangedWitness() == original else {
                throw ProtectedFilePolicyError.identityChanged
            }
            try emitVerificationDisposition(.verifiedComplete, kind: kind)
            return .verifiedComplete
        }

        #if DEBUG && os(iOS) && targetEnvironment(simulator)
        diagnosticStage = "pending-policy-shape"
        guard initial.state == .pendingSimulatorRequest else {
            throw ProtectedFilePolicyError.resourceValueMismatch
        }
        let expected = disposition(for: kind)
        diagnosticStage = "pre-request-resource-readback"
        let beforeReadback = independentProtectionReadback(at: url)
        guard simulatorReadbackIsExactFallback(beforeReadback,
                disposition: expected),
              beforeReadback.volumeSupportsProtection == false else {
            throw ProtectedFilePolicyError.resourceValueMismatch
        }
        diagnosticStage = "pre-request-witness-reproof"
        guard try unchangedWitness() == original else {
            throw ProtectedFilePolicyError.identityChanged
        }
        // The caller boundary is reached only for an actual pending
        // request. It can require the exact last preimage before allowing its
        // witness to account for this setter's own metadata transition.
        // It grants no success: the checked request/readback below must finish.
        diagnosticStage = "complete-request-boundary"
        try willRequestCompleteProtection()
        diagnosticStage = "complete-request"
        do {
            try (url as NSURL).setResourceValue(
                URLFileProtection.complete, forKey: .fileProtectionKey)
        } catch {
            throw mapWriteError(error)
        }
        // No backup setter is used: the exact pending predicate already
        // proved its required value. Refuse even a same-inode byte or metadata
        // drift caused by the request before accepting this one call.
        diagnosticStage = "post-request-witness-reproof"
        guard try unchangedWitness() == original else {
            throw ProtectedFilePolicyError.identityChanged
        }
        diagnosticStage = "post-request-checked-policy-observation"
        let after = try observeTemporalPolicyWithCheckedClose(kind,
            at: url, retainUncertainDescriptor: retainUncertainDescriptor)
        guard after.device == initial.device,
              after.inode == initial.inode,
              after.linkCount == initial.linkCount,
              after.mode == initial.mode,
              after.backupExcluded == initial.backupExcluded,
              after.isDirectory == initial.isDirectory,
              after.volumeSupportsProtection
                == initial.volumeSupportsProtection,
              try unchangedWitness() == original else {
            throw ProtectedFilePolicyError.identityChanged
        }
        if after.state == .strictComplete {
            try emitVerificationDisposition(.verifiedComplete, kind: kind)
            return .verifiedComplete
        }
        diagnosticStage = "post-request-resource-readback"
        let afterReadback = independentProtectionReadback(at: url)
        guard simulatorDiagnosticAllows(
                capabilityBefore: beforeReadback.volumeSupportsProtection,
                after: afterReadback, disposition: expected,
                successfulCompleteRequest: true,
                identityUnchanged: true) else {
            throw ProtectedFilePolicyError.resourceValueMismatch
        }
        try emitVerificationDisposition(.simulatorFileProtectionUnsupported,
            kind: kind)
        return .simulatorFileProtectionUnsupported
        #else
        throw ProtectedFilePolicyError.resourceValueMismatch
        #endif
        } catch {
            #if DEBUG && os(iOS) && targetEnvironment(simulator)
            // Keep the diagnostic a fixed vocabulary. NSError descriptions
            // and arbitrary error types can contain filesystem paths.
            let category: String
            switch error as? ProtectedFilePolicyError {
            case .resourceValueMismatch: category = "resourceValueMismatch"
            case .identityChanged: category = "identityChanged"
            case .invalidURL: category = "invalidURL"
            case .invalidRelativePath: category = "invalidRelativePath"
            case .missing: category = "missing"
            case .symbolicLink: category = "symbolicLink"
            case .invalidType: category = "invalidType"
            case .hardLink: category = "hardLink"
            case .attributeWriteFailed: category = "attributeWriteFailed"
            case .protectedDataUnavailable: category = "protectedDataUnavailable"
            case nil: category = "other"
            }
            diagnosticWriter.write("V23_ERASE_POLICY_REQUEST_FAILURE_V1"
                + " kind=\(kind.rawValue) stage=\(diagnosticStage)"
                + " category=\(category)\n")
            emitDirectoryProtectionReadback(kind: kind, at: url,
                phase: diagnosticStage,
                readback: independentProtectionReadback(at: url))
            #endif
            throw error
        }
    }
}
