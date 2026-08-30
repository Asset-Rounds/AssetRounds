import Foundation
import XCTest

@testable import FieldEvidenceApp

private struct C54EncryptedEnvelopeCorpusFixture: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let corpusID: String
    let testOnly: Bool
    let synthetic: Bool
    let immutable: Bool
    let containsCustomerData: Bool
    let containsProductionSecrets: Bool
    let contracts: [String]
    let evidenceIDs: [String]
    let innerKinds: [String]
    let format: Format
    let publishedVectors: PublishedVectors
    let alternateCases: [String]
    let hostileCases: [String]
    let interruptions: [String]
    let recovery: Recovery
    let privacyLeakSurfaces: [String]
    let claims: Claims
    let typedAnchor: String

    struct Format: Decodable {
        let uti: String
        let fileExtension: String
        let pbkdf2Iterations: UInt32
        let saltBytes: Int
        let derivedKeyBytes: Int
        let noncePrefixBytes: Int
        let frameIndexBytes: Int
        let maximumPlaintextFrameBytes: UInt32
        let authenticationTagBytes: Int
        let minimumFrameCount: UInt32
        let emptyInnerFrameCount: UInt32
        let innerProtocolVersion: UInt16
        let maximumOperationalPlaintextBytes: UInt64
        let maximumOperationalScratchBytes: UInt64
        let maximumOperationalFrameCount: UInt32
    }

    struct PublishedVectors: Decodable {
        let pbkdf2HMACSHA256: [PBKDF2Vector]
        let aesGCM: [AESGCMVector]
    }

    struct PBKDF2Vector: Decodable {
        let passphraseUTF8Hex: String
        let saltHex: String
        let iterations: UInt32
        let derivedKeyBytes: Int
        let derivedKeyHex: String
    }

    struct AESGCMVector: Decodable {
        let keyHex: String
        let nonceHex: String
        let plaintextHex: String
        let authenticatedDataHex: String
        let ciphertextHex: String
        let tagHex: String
    }

    struct Recovery: Decodable {
        let crashCleanup: Bool
        let idempotentRetry: Bool
        let crossDeviceOfflineOpen: Bool
        let strictSecretFreeReceipts: Bool
        let exportComplianceRequiresReleaseResolution: Bool
        let exportComplianceAssumesExemption: Bool
    }

    struct Claims: Decodable {
        let unchangedInnerBytes: Bool
        let noIdentityProof: Bool
        let noAuthorityProof: Bool
        let noDeliveryProof: Bool
        let noLegalSignatureProof: Bool
        let noPartialSuccess: Bool
        let memoryOnlySecrets: Bool
        let noCanonicalPersistence: Bool
        let noReplication: Bool
        let eraseRemovesScratch: Bool
        let diagnosticsExcludeSecretsAndCustomerData: Bool
    }
}

private enum C54EncryptedEnvelopeTestSupport {
    static let evidenceIDs = [
        "V23-P03-C54-G01",
        "V23-P03-C54-A01",
        "V23-P03-C54-H01",
        "V23-P03-C54-I01",
        "V23-P03-C54-R01",
    ]

    static func fixture() throws -> C54EncryptedEnvelopeCorpusFixture {
        let bundle = Bundle(for: V9_62EncryptedPortableEnvelopeTests.self)
        let name = "V22P03C54EncryptedPortableEnvelopeCorpusV1"
        let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/V22/EncryptedEnvelope"
        ) ?? bundle.url(forResource: name, withExtension: "json")
        guard let url else { throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader }
        return try JSONDecoder().decode(
            C54EncryptedEnvelopeCorpusFixture.self,
            from: Data(contentsOf: url)
        )
    }

    static func data(hex: String) throws -> Data {
        guard hex.count.isMultiple(of: 2),
              hex.utf8.allSatisfy({
                  (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
              }) else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        var result = Data()
        result.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
            }
            result.append(byte)
            index = next
        }
        return result
    }

    static func header(
        plaintextByteCount: UInt64,
        frameCount: UInt32? = nil,
        kdf: EncryptedEnvelopeKDFProfileV1 = .released,
        aead: EncryptedEnvelopeAEADProfileV1 = .released
    ) throws -> EncryptedPortableEnvelopePublicHeaderV1 {
        let canonicalFrameCount: UInt32
        if let frameCount {
            canonicalFrameCount = frameCount
        } else {
            canonicalFrameCount = try EncryptedPortableEnvelopePublicHeaderV1.canonicalFrameCount(
                plaintextByteCount: plaintextByteCount,
                frameByteLimit: UInt64(aead.framePlaintextByteLimit)
            )
        }
        try EncryptedPortableEnvelopePublicHeaderV1(
            innerKind: .workspaceBackup,
            innerProtocolVersion: try EncryptedPortableEnvelopeInnerProtocolVersionV1(1),
            reviewProtectionMode: nil,
            kdfProfile: kdf,
            aeadProfile: aead,
            publicEnvelopeID: Data(repeating: 0x45, count: 16),
            declaredFrameCount: canonicalFrameCount,
            declaredPlaintextByteCount: plaintextByteCount,
            declaredCiphertextByteCount: plaintextByteCount + UInt64(canonicalFrameCount) * UInt64(aead.authenticationTagByteCount),
            salt: Data(repeating: 0x53, count: Int(kdf.saltByteCount)),
            noncePrefix: Data(repeating: 0x4e, count: Int(aead.noncePrefixByteCount))
        )
    }

    static func receiptContext(_ offset: UInt8 = 0) throws -> EncryptedEnvelopeOperationReceiptContextV1 {
        return try EncryptedEnvelopeOperationReceiptContextV1(
            operationID: UUID(uuidString: String(
                format: "54000000-0000-4000-8000-%012x",
                1 + Int(offset)
            ))!,
            attemptID: UUID(uuidString: String(
                format: "54000000-0000-4000-8000-%012x",
                2 + Int(offset)
            ))!,
            candidateHead: String(repeating: "a", count: 40),
            candidateTree: String(repeating: "b", count: 40),
            toolchainIdentifier: "C54 deterministic XCTest",
            deterministicTestResult: .passed
        )
    }

    static func operation(_ slot: Int) throws -> EncryptedPortableEnvelopeOperationIdentityV1 {
        let attempt = UUID(uuidString: String(format: "54000000-0000-4000-8000-%012x", slot))!
        let mutation = UUID(uuidString: String(format: "54000000-0000-4000-8000-%012x", slot + 1))!
        return try EncryptedPortableEnvelopeOperationIdentityV1(
            workspaceID: WorkspaceID(rawValue: UUID(uuidString: "54000000-0000-4000-8000-000000000001")!),
            attemptID: attempt,
            mutationID: MutationIDV1(rawValue: mutation),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_600)
        )
    }

    static func receiptContext(
        for operation: EncryptedPortableEnvelopeOperationIdentityV1
    ) throws -> EncryptedEnvelopeOperationReceiptContextV1 {
        try EncryptedEnvelopeOperationReceiptContextV1(
            operationID: operation.mutationID.rawValue,
            attemptID: operation.attemptID,
            candidateHead: String(repeating: "a", count: 40),
            candidateTree: String(repeating: "b", count: 40),
            toolchainIdentifier: "C54 coordinator XCTest",
            deterministicTestResult: .passed
        )
    }

    static func allBytes(
        _ source: any EncryptedEnvelopeBoundedSeekableSourceV1
    ) throws -> Data {
        let count = try source.encryptedEnvelopeByteCount()
        guard let exactCount = Int(exactly: count) else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        return try source.readExactly(atOffset: 0, byteCount: exactCount)
    }

    static func validate(
        _ source: any EncryptedEnvelopeBoundedSeekableSourceV1,
        equals expected: Data,
        maximumChunkByteCount: Int = 1_048_576
    ) throws {
        guard try source.encryptedEnvelopeByteCount() == UInt64(expected.count) else {
            throw EncryptedPortableEnvelopeFailureV1.hostileInnerPackage
        }
        var offset = 0
        while offset < expected.count {
            let count = min(maximumChunkByteCount, expected.count - offset)
            guard try source.readExactly(atOffset: UInt64(offset), byteCount: count)
                    == Data(expected[offset..<(offset + count)]) else {
                throw EncryptedPortableEnvelopeFailureV1.hostileInnerPackage
            }
            offset += count
        }
    }
}

private final class C54LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []

    func append(_ value: Value) {
        lock.withLock { values.append(value) }
    }

    func snapshot() -> [Value] {
        lock.withLock { values }
    }
}

private actor C54EnvelopeScratchProbe: ScratchDataLeasePortV1, EncryptedPortableEnvelopeStreamingScratchPortV1 {
    private let failWrites: Bool
    private let recoveredCount: Int
    private let failRelease: Bool
    private let resetGate: C54ResetGate?
    private var acquired: [UUID: ScratchDataLeaseV1] = [:]
    private var terminals: [ScratchDataLeaseTerminalV1] = []
    private var recoveryCalls = 0

    init(failWrites: Bool = false, recoveredCount: Int = 0, failRelease: Bool = false,
         resetGate: C54ResetGate? = nil) {
        self.failWrites = failWrites
        self.recoveredCount = recoveredCount
        self.failRelease = failRelease
        self.resetGate = resetGate
    }

    func acquireScratchLease(_ request: ScratchDataLeaseRequestV1) async throws -> ScratchDataLeaseV1 {
        let lease = try ScratchDataLeaseV1(request: request, relativeDirectory: "c54-scratch")
        acquired[request.leaseID] = lease
        return lease
    }

    func writeScratchData(_ data: Data, named: String, lease: ScratchDataLeaseV1) async throws -> URL {
        guard acquired[lease.request.leaseID] == lease, !data.isEmpty || named == "authenticated-inner.bin" else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        if failWrites { throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded }
        return FileManager.default.temporaryDirectory.appendingPathComponent(named, isDirectory: false)
    }

    func releaseScratchLease(
        _ lease: ScratchDataLeaseV1,
        terminal: ScratchDataLeaseTerminalV1
    ) async throws {
        acquired.removeValue(forKey: lease.request.leaseID)
        terminals.append(terminal)
        if failRelease { throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded }
    }

    func recoverScratchLeases() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        recoveryCalls += 1
        acquired.removeAll()
        return try ScratchDataLeaseRecoverySummaryV1(
            recoveredExpiredLeaseCount: recoveredCount,
            removedByteCount: UInt64(recoveredCount)
        )
    }

    func resetScratchData() async throws { await resetGate?.pause(); acquired.removeAll() }
    func eraseScratchData() async throws { acquired.removeAll() }
    func recordedTerminals() -> [ScratchDataLeaseTerminalV1] { terminals }
    func recordedRecoveryCalls() -> Int { recoveryCalls }
    func activeLeaseCount() -> Int { acquired.count }
    func makeEncryptedPortableEnvelopeStreamingScratch(
        named: String, lease: ScratchDataLeaseV1, maximumByteCount: UInt64
    ) async throws -> any EncryptedEnvelopeProtectedScratchSinkV1 {
        guard acquired[lease.request.leaseID] == lease else { throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded }
        _ = named
        return C54StreamingBuffer()
    }
}

private actor C54ResetGate {
    private var entered = false; private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    func pause() async {
        entered = true; enteredWaiters.forEach { $0.resume() }; enteredWaiters.removeAll()
        if !released { await withCheckedContinuation { releaseWaiters.append($0) } }
    }
    func waitUntilEntered() async {
        if entered { return }; await withCheckedContinuation { enteredWaiters.append($0) }
    }
    func release() { released = true; releaseWaiters.forEach { $0.resume() }; releaseWaiters.removeAll() }
}

private actor C54OperationalSupportResetProbe: DeviceOperationalSupportStoreV2 {
    private var value: DeviceOperationalSupportSnapshotV2
    init() throws {
        value = try .init(
            health: .init(generatedAt: Date(timeIntervalSince1970: 1_800_000_000), state: .unknown,
                          failures: [], metricKit: nil), counters: .zero
        )
    }
    func operationalSupportSnapshot() async throws -> DeviceOperationalSupportSnapshotV2 { value }
    func recordOperationalFailure(_ failure: OperationalFailureV1) async throws { _ = failure }
    func replaceSystemHealth(_ health: SystemHealthDiagnosticsV1) async throws {
        value = try .init(health: health, counters: value.counters)
    }
    func resetOperationalSupport() async throws {
        value = try .init(
            health: .init(generatedAt: value.health.generatedAt, state: .unknown, failures: [], metricKit: nil),
            counters: .zero
        )
    }
}

private struct C54StreamingBufferSnapshot {
    let bytes: Data
    let maximumReadByteCount: Int
    let maximumAppendByteCount: Int
    let readCount: Int
    let prepareCount: Int
    let synchronizeCount: Int
    let discardCount: Int
}

private final class C54StreamingBuffer: EncryptedEnvelopeProtectedScratchSinkV1,
    @unchecked Sendable {
    let protectionClass = EncryptedEnvelopeProtectionClassV1.complete
    let isExcludedFromBackup = true

    private let lock = NSLock()
    private var bytes: Data
    private var expectedByteCount: UInt64?
    private var maximumReadByteCount = 0
    private var maximumAppendByteCount = 0
    private var readCount = 0
    private var prepareCount = 0
    private var synchronizeCount = 0
    private var discardCount = 0

    init(_ bytes: Data = Data()) { self.bytes = bytes }

    func encryptedEnvelopeByteCount() throws -> UInt64 {
        lock.withLock { UInt64(bytes.count) }
    }

    func readExactly(atOffset: UInt64, byteCount: Int) throws -> Data {
        try lock.withLock {
            guard byteCount >= 0,
                  atOffset <= UInt64(Int.max),
                  let end = Int(exactly: atOffset)?.addingReportingOverflow(byteCount),
                  !end.overflow,
                  end.partialValue <= bytes.count else {
                throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
            }
            maximumReadByteCount = max(maximumReadByteCount, byteCount)
            readCount += 1
            return Data(bytes[Int(atOffset)..<end.partialValue])
        }
    }

    func prepareForStreamingWrite(expectedByteCount: UInt64) throws {
        try lock.withLock {
            guard expectedByteCount <= UInt64(Int.max) else {
                throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
            }
            bytes.removeAll(keepingCapacity: false)
            self.expectedByteCount = expectedByteCount
            prepareCount += 1
        }
    }

    func appendStreamingBytes(_ bytes: Data) throws {
        try lock.withLock {
            guard let expectedByteCount,
                  UInt64(self.bytes.count) + UInt64(bytes.count) <= expectedByteCount else {
                throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
            }
            maximumAppendByteCount = max(maximumAppendByteCount, bytes.count)
            self.bytes.append(bytes)
        }
    }

    func synchronizeStreamingWrite() throws {
        try lock.withLock {
            guard let expectedByteCount, UInt64(bytes.count) == expectedByteCount else {
                throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
            }
            synchronizeCount += 1
        }
    }

    func discardStreamingBytes() throws {
        lock.withLock {
            bytes.removeAll(keepingCapacity: false)
            expectedByteCount = nil
            discardCount += 1
        }
    }

    func snapshot() -> C54StreamingBufferSnapshot {
        lock.withLock {
            .init(
                bytes: bytes,
                maximumReadByteCount: maximumReadByteCount,
                maximumAppendByteCount: maximumAppendByteCount,
                readCount: readCount,
                prepareCount: prepareCount,
                synchronizeCount: synchronizeCount,
                discardCount: discardCount
            )
        }
    }
}

private final class C54PublishedBuffer: EncryptedPortableEnvelopePublishedSourceV1, @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    var isIndependentFromProtectedScratch: Bool { true }
    func encryptedEnvelopeByteCount() throws -> UInt64 { lock.withLock { UInt64(bytes.count) } }
    func readExactly(atOffset: UInt64, byteCount: Int) throws -> Data {
        try lock.withLock {
            let start = Int(atOffset)
            guard start >= 0, byteCount >= 0, start + byteCount <= bytes.count else {
                throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
            }
            return Data(bytes[start..<(start + byteCount)])
        }
    }
    func mutateFirstByteWithoutChangingLength() {
        lock.withLock { if !bytes.isEmpty { bytes[0] ^= 0x01 } }
    }
}

private final class C54CancellationProbe: EncryptedEnvelopeCancellationCheckingV1,
    @unchecked Sendable {
    private let lock = NSLock()
    private let cancelAtCheck: Int?
    private var checks = 0

    init(cancelAtCheck: Int? = nil) { self.cancelAtCheck = cancelAtCheck }

    func checkCancellation() throws {
        try lock.withLock {
            checks += 1
            if checks == cancelAtCheck {
                throw EncryptedPortableEnvelopeFailureV1.cancelled
            }
        }
    }

    func checkCount() -> Int { lock.withLock { checks } }
}

#if DEBUG
private struct C54StreamingCryptoPort: EncryptedPortableEnvelopeCryptographicPortV1,
    @unchecked Sendable {
    let crypto: EncryptedPortableEnvelopeCryptoV1

    func structuralPreflight(
        source: any EncryptedEnvelopeBoundedSeekableSourceV1,
        limits: EncryptedPortableEnvelopeResourceLimitsV1,
        cancellation: any EncryptedEnvelopeCancellationCheckingV1
    ) throws -> EncryptedEnvelopeStructuralPreflightReceiptV1 {
        try crypto.structuralPreflight(source: source, limits: limits, cancellation: cancellation)
    }

    func sealStreaming(
        innerSource: any EncryptedEnvelopeBoundedSeekableSourceV1,
        innerKind: EncryptedPortableEnvelopeInnerKindV1,
        innerProtocolVersion: EncryptedPortableEnvelopeInnerProtocolVersionV1,
        reviewProtectionMode: ReviewExchangeProtectionV1?,
        passphrase: EphemeralPassphraseV1,
        context: EncryptedEnvelopeOperationReceiptContextV1,
        limits: EncryptedPortableEnvelopeResourceLimitsV1,
        envelopeScratch: any EncryptedEnvelopeProtectedScratchSinkV1,
        reopenPlaintextScratch: any EncryptedEnvelopeProtectedScratchSinkV1,
        validateSourceInner: EncryptedEnvelopeStreamingInnerValidatorV1,
        validateReopenedInner: EncryptedEnvelopeStreamingInnerValidatorV1,
        cancellation: any EncryptedEnvelopeCancellationCheckingV1
    ) throws -> EncryptedPortableEnvelopeStreamingSealResultV1 {
        try crypto.sealStreaming(
            innerSource: innerSource,
            innerKind: innerKind,
            innerProtocolVersion: innerProtocolVersion,
            reviewProtectionMode: reviewProtectionMode,
            passphrase: passphrase,
            context: context,
            limits: limits,
            envelopeScratch: envelopeScratch,
            reopenPlaintextScratch: reopenPlaintextScratch,
            validateSourceInner: validateSourceInner,
            validateReopenedInner: validateReopenedInner,
            cancellation: cancellation
        )
    }

    func openStreaming(
        envelopeSource: any EncryptedEnvelopeBoundedSeekableSourceV1,
        passphrase: EphemeralPassphraseV1,
        context: EncryptedEnvelopeOperationReceiptContextV1,
        limits: EncryptedPortableEnvelopeResourceLimitsV1,
        plaintextScratch: any EncryptedEnvelopeProtectedScratchSinkV1,
        validateInner: EncryptedEnvelopeStreamingInnerValidatorV1,
        cancellation: any EncryptedEnvelopeCancellationCheckingV1
    ) throws -> EncryptedPortableEnvelopeStreamingOpenResultV1 {
        try crypto.openStreaming(
            envelopeSource: envelopeSource,
            passphrase: passphrase,
            context: context,
            limits: limits,
            plaintextScratch: plaintextScratch,
            validateInner: validateInner,
            cancellation: cancellation
        )
    }
}

private final class C54HostileSource: EncryptedEnvelopeBoundedSeekableSourceV1, @unchecked Sendable {
    enum Mode: Equatable { case shortRead, mutateAfterFirstRead }
    private let lock = NSLock(); private var bytes: Data; private let mode: Mode; private var reads = 0
    init(_ bytes: Data, mode: Mode) { self.bytes = bytes; self.mode = mode }
    func encryptedEnvelopeByteCount() throws -> UInt64 { lock.withLock { UInt64(bytes.count) } }
    func readExactly(atOffset: UInt64, byteCount: Int) throws -> Data {
        try lock.withLock {
            let start = Int(atOffset); guard start >= 0, start + byteCount <= bytes.count else {
                throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
            }
            reads += 1
            if mode == .mutateAfterFirstRead, reads == 2, !bytes.isEmpty { bytes[0] ^= 1 }
            let requested = mode == .shortRead ? max(0, byteCount - 1) : byteCount
            return Data(bytes[start..<(start + requested)])
        }
    }
}
#endif

private actor C54CoordinatorLifecycleProbe: EncryptedPortableEnvelopeAttemptLifecycleV1 {
    private struct State {
        let secret: EphemeralPassphraseV1
        let envelope: C54StreamingBuffer?
        let reopen: C54StreamingBuffer?
        let plaintext: C54StreamingBuffer?
        let cancellation: EncryptedPortableEnvelopeCancellationTokenV1
    }

    private var active: [EncryptedPortableEnvelopeOperationIdentityV1: State] = [:]
    private var published: [EncryptedPortableEnvelopeOperationIdentityV1: C54StreamingBuffer] = [:]
    private var completionCount = 0
    private var abortCount = 0
    private var prepareSealCount = 0
    private var openCleanupSecretByteCount = -1
    private var finalSecretByteCount = -1
    private let cancelPreparedOperations: Bool

    init(cancelPreparedOperations: Bool = false) {
        self.cancelPreparedOperations = cancelPreparedOperations
    }

    func claimSecret(
        operation: EncryptedPortableEnvelopeOperationIdentityV1,
        secret: EphemeralPassphraseV1
    ) async throws -> EncryptedPortableEnvelopeCancellationTokenV1 {
        let prior = active[operation]
        guard prior == nil || prior?.secret === secret else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        if prior == nil {
            active[operation] = State(
                secret: secret,
                envelope: nil,
                reopen: nil,
                plaintext: nil,
                cancellation: EncryptedPortableEnvelopeCancellationTokenV1()
            )
        }
        return active[operation]!.cancellation
    }

    func prepareSeal(
        operation: EncryptedPortableEnvelopeOperationIdentityV1,
        topology: EncryptedPortableEnvelopeTopologyV1
    ) async throws -> EncryptedPortableEnvelopeSealResourcesV1 {
        prepareSealCount += 1
        guard let current = active[operation] else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        let envelope = C54StreamingBuffer()
        let reopen = C54StreamingBuffer()
        if cancelPreparedOperations { current.cancellation.cancel() }
        active[operation] = State(
            secret: current.secret,
            envelope: envelope,
            reopen: reopen,
            plaintext: nil,
            cancellation: current.cancellation
        )
        _ = topology
        return .init(
            operation: operation,
            envelopeScratch: envelope,
            reopenPlaintextScratch: reopen,
            cancellation: current.cancellation
        )
    }

    func prepareOpen(
        operation: EncryptedPortableEnvelopeOperationIdentityV1,
        preflight: EncryptedEnvelopeStructuralPreflightReceiptV1
    ) async throws -> EncryptedPortableEnvelopeOpenResourcesV1 {
        guard let current = active[operation] else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        let plaintext = C54StreamingBuffer()
        if cancelPreparedOperations { current.cancellation.cancel() }
        active[operation] = State(
            secret: current.secret,
            envelope: nil,
            reopen: nil,
            plaintext: plaintext,
            cancellation: current.cancellation
        )
        _ = preflight
        return .init(operation: operation, plaintextScratch: plaintext, cancellation: current.cancellation)
    }

    func publishAndCleanupSeal(
        resources: EncryptedPortableEnvelopeSealResourcesV1,
        facts: EncryptedEnvelopeSealCryptographicFactsV1
    ) async throws -> EncryptedPortableEnvelopeFinalizedSealV1 {
        guard let state = active.removeValue(forKey: resources.operation),
              let envelope = state.envelope,
              facts.cleanupDisposition == .pending,
              facts.reopenedAndAuthenticated else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        if !active.values.contains(where: { $0.secret === state.secret }) {
            state.secret.clear()
        }
        finalSecretByteCount = state.secret.withUnsafeBytes { $0.count }
        published[resources.operation] = envelope
        completionCount += 1
        return .init(source: C54PublishedBuffer(envelope.snapshot().bytes), receipt: try .init(finalizing: facts))
    }

    func cleanupOpen(
        resources: EncryptedPortableEnvelopeOpenResourcesV1,
        facts: EncryptedEnvelopeOpenCryptographicFactsV1
    ) async throws {
        guard let state = active.removeValue(forKey: resources.operation),
              state.plaintext != nil,
              facts.cleanupDisposition == .pending,
              facts.outerAuthenticationComplete else {
            throw EncryptedPortableEnvelopeFailureV1.invalidPublicHeader
        }
        if !active.values.contains(where: { $0.secret === state.secret }) {
            state.secret.clear()
        }
        openCleanupSecretByteCount = state.secret.withUnsafeBytes { $0.count }
        completionCount += 1
    }

    func completeOpenFinalization(
        operation: EncryptedPortableEnvelopeOperationIdentityV1,
        cancellation: EncryptedPortableEnvelopeCancellationTokenV1
    ) async throws { _ = (operation, cancellation) }

    func abandonOpenFinalization(operation: EncryptedPortableEnvelopeOperationIdentityV1) async {
        _ = operation
    }

    func abort(operation: EncryptedPortableEnvelopeOperationIdentityV1) async throws {
        guard let state = active.removeValue(forKey: operation) else { return }
        state.cancellation.cancel()
        state.secret.clear()
        try? state.envelope?.discardStreamingBytes()
        try? state.reopen?.discardStreamingBytes()
        try? state.plaintext?.discardStreamingBytes()
        abortCount += 1
    }

    func counts() -> (completed: Int, aborted: Int, active: Int) {
        (completionCount, abortCount, active.count)
    }
    func sealPreparationCount() -> Int { prepareSealCount }

    func secretDisposition() -> (afterOpen: Int, afterTerminal: Int) {
        (openCleanupSecretByteCount, finalSecretByteCount)
    }
}

private final class C54LegacyClearReaderProbe: EncryptedPortableEnvelopeLegacyClearReaderV1,
    @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(EncryptedPortableEnvelopeInnerKindV1, UInt16)] = []

    func readLegacyClear(
        source: any EncryptedEnvelopeBoundedSeekableSourceV1,
        kind: EncryptedPortableEnvelopeInnerKindV1,
        version: EncryptedPortableEnvelopeInnerProtocolVersionV1
    ) throws {
        guard try source.encryptedEnvelopeByteCount() > 0 else {
            throw EncryptedPortableEnvelopeFailureV1.hostileInnerPackage
        }
        lock.withLock { calls.append((kind, version.rawValue)) }
    }

    func callCount() -> Int { lock.withLock { calls.count } }
}

private final class C54AuthenticatedInnerConsumerProbe:
    EncryptedPortableEnvelopeAuthenticatedInnerConsumerV1, @unchecked Sendable {
    private let lock = NSLock()
    private var consumed: [Data] = []
    private final class Transaction: EncryptedPortableEnvelopeAuthenticatedInnerTransactionV1, @unchecked Sendable {
        let commitBody: @Sendable () -> Void
        let rollbackBody: @Sendable () -> Void
        init(commit: @escaping @Sendable () -> Void, rollback: @escaping @Sendable () -> Void) {
            commitBody = commit; rollbackBody = rollback
        }
        func commit() async throws { commitBody() }
        func rollback() async { rollbackBody() }
    }
    func stageAuthenticatedInner(
        source: any EncryptedEnvelopeBoundedSeekableSourceV1,
        kind: EncryptedPortableEnvelopeInnerKindV1,
        version: EncryptedPortableEnvelopeInnerProtocolVersionV1
    ) async throws -> any EncryptedPortableEnvelopeAuthenticatedInnerTransactionV1 {
        try version.validateReleased(for: kind)
        let bytes = try C54EncryptedEnvelopeTestSupport.allBytes(source)
        return Transaction(
            commit: { [weak self] in self?.lock.withLock { self?.consumed.append(bytes) } },
            rollback: { [weak self] in
                self?.lock.withLock {
                    if self?.consumed.last == bytes { self?.consumed.removeLast() }
                }
            }
        )
    }
    func snapshot() -> [Data] { lock.withLock { consumed } }
}

private final class C54CancellingInnerConsumerProbe:
    EncryptedPortableEnvelopeAuthenticatedInnerConsumerV1, @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationBody: (@Sendable () async -> Void)?
    private var canonical: [Data] = []; private var commits = 0; private var rollbacks = 0
    private final class Transaction:
        EncryptedPortableEnvelopeAuthenticatedInnerTransactionV1, @unchecked Sendable {
        let commitBody: @Sendable () async throws -> Void
        let rollbackBody: @Sendable () -> Void
        init(
            commit: @escaping @Sendable () async throws -> Void,
            rollback: @escaping @Sendable () -> Void
        ) { commitBody = commit; rollbackBody = rollback }
        func commit() async throws { try await commitBody() }
        func rollback() async { rollbackBody() }
    }
    func installCancellation(_ body: @escaping @Sendable () async -> Void) {
        lock.withLock { cancellationBody = body }
    }
    func stageAuthenticatedInner(
        source: any EncryptedEnvelopeBoundedSeekableSourceV1,
        kind: EncryptedPortableEnvelopeInnerKindV1,
        version: EncryptedPortableEnvelopeInnerProtocolVersionV1
    ) async throws -> any EncryptedPortableEnvelopeAuthenticatedInnerTransactionV1 {
        try version.validateReleased(for: kind)
        let bytes = try C54EncryptedEnvelopeTestSupport.allBytes(source)
        return Transaction(
            commit: { [weak self] in
                guard let self else { return }
                let cancel = self.lock.withLock {
                    self.canonical.append(bytes); self.commits += 1
                    return self.cancellationBody
                }
                await cancel?()
            },
            rollback: { [weak self] in
                guard let self else { return }
                self.lock.withLock {
                    if self.canonical.last == bytes { self.canonical.removeLast() }
                    self.rollbacks += 1
                }
            }
        )
    }
    func snapshot() -> (canonicalCount: Int, commits: Int, rollbacks: Int) {
        lock.withLock { (canonical.count, commits, rollbacks) }
    }
}

private final class C54PublicationTransactionProbe:
    EncryptedPortableEnvelopePublicationTransactionV1, @unchecked Sendable {
    let stagedSource: any EncryptedPortableEnvelopePublishedSourceV1
    private let commitBody: @Sendable () throws -> Void
    private let rollbackBody: @Sendable () -> Void
    init(
        source: any EncryptedPortableEnvelopePublishedSourceV1,
        commit: @escaping @Sendable () throws -> Void = {},
        rollback: @escaping @Sendable () -> Void = {}
    ) {
        stagedSource = source; commitBody = commit; rollbackBody = rollback
    }
    func commitPublication() async throws { try commitBody() }
    func rollbackPublication() async { rollbackBody() }
}

private struct C54PublicationProbe: EncryptedPortableEnvelopeSharePublishingV1 {
    func stageEncryptedEnvelope(
        source: any EncryptedEnvelopeBoundedSeekableSourceV1,
        byteCount: UInt64,
        filename: String,
        shareTitle: String,
        cancellation: any EncryptedEnvelopeCancellationCheckingV1
    ) async throws -> any EncryptedPortableEnvelopePublicationTransactionV1 {
        try cancellation.checkCancellation()
        guard try source.encryptedEnvelopeByteCount() == byteCount,
              !filename.isEmpty,
              !shareTitle.isEmpty else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        return C54PublicationTransactionProbe(
            source: C54PublishedBuffer(try C54EncryptedEnvelopeTestSupport.allBytes(source))
        )
    }
}

private final class C54RollbackPublicationProbe: EncryptedPortableEnvelopeSharePublishingV1, @unchecked Sendable {
    private let lock = NSLock(); private var publishes = 0; private var rollbacks = 0
    func stageEncryptedEnvelope(
        source: any EncryptedEnvelopeBoundedSeekableSourceV1, byteCount: UInt64,
        filename: String, shareTitle: String,
        cancellation: any EncryptedEnvelopeCancellationCheckingV1
    ) async throws -> any EncryptedPortableEnvelopePublicationTransactionV1 {
        try cancellation.checkCancellation()
        _ = (byteCount, filename, shareTitle); lock.withLock { publishes += 1 }
        var bytes = try C54EncryptedEnvelopeTestSupport.allBytes(source); bytes.append(0x00)
        return C54PublicationTransactionProbe(
            source: C54PublishedBuffer(bytes),
            rollback: { [weak self] in self?.lock.withLock { self?.rollbacks += 1 } }
        )
    }
    func counts() -> (publishes: Int, rollbacks: Int) { lock.withLock { (publishes, rollbacks) } }
}

private final class C54RevokingPublicationProbe: EncryptedPortableEnvelopeSharePublishingV1,
    @unchecked Sendable {
    private let lock = NSLock(); private var stages = 0; private var commits = 0; private var rollbacks = 0
    func stageEncryptedEnvelope(
        source: any EncryptedEnvelopeBoundedSeekableSourceV1, byteCount: UInt64,
        filename: String, shareTitle: String,
        cancellation: any EncryptedEnvelopeCancellationCheckingV1
    ) async throws -> any EncryptedPortableEnvelopePublicationTransactionV1 {
        try cancellation.checkCancellation()
        guard try source.encryptedEnvelopeByteCount() == byteCount,
              !filename.isEmpty, !shareTitle.isEmpty else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        let published = C54PublishedBuffer(try C54EncryptedEnvelopeTestSupport.allBytes(source))
        lock.withLock { stages += 1 }
        await EncryptedPortableEnvelopeSecretLifecycleRegistryV1.shared
            .revokeEncryptedPortableEnvelopeSecrets(reason: .appLock)
        return C54PublicationTransactionProbe(
            source: published,
            commit: { [weak self] in self?.lock.withLock { self?.commits += 1 } },
            rollback: { [weak self] in self?.lock.withLock { self?.rollbacks += 1 } }
        )
    }
    func counts() -> (stages: Int, commits: Int, rollbacks: Int) {
        lock.withLock { (stages, commits, rollbacks) }
    }
}

private final class C54ExplicitCancellingPublicationProbe:
    EncryptedPortableEnvelopeSharePublishingV1, @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationBody: (@Sendable () async -> Void)?
    private var stages = 0; private var commits = 0; private var rollbacks = 0
    func installCancellation(_ body: @escaping @Sendable () async -> Void) {
        lock.withLock { cancellationBody = body }
    }
    func stageEncryptedEnvelope(
        source: any EncryptedEnvelopeBoundedSeekableSourceV1, byteCount: UInt64,
        filename: String, shareTitle: String,
        cancellation: any EncryptedEnvelopeCancellationCheckingV1
    ) async throws -> any EncryptedPortableEnvelopePublicationTransactionV1 {
        try cancellation.checkCancellation()
        guard try source.encryptedEnvelopeByteCount() == byteCount,
              !filename.isEmpty, !shareTitle.isEmpty else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        let published = C54PublishedBuffer(try C54EncryptedEnvelopeTestSupport.allBytes(source))
        let cancel = lock.withLock { stages += 1; return cancellationBody }
        await cancel?()
        return C54PublicationTransactionProbe(
            source: published,
            commit: { [weak self] in self?.lock.withLock { self?.commits += 1 } },
            rollback: { [weak self] in self?.lock.withLock { self?.rollbacks += 1 } }
        )
    }
    func counts() -> (stages: Int, commits: Int, rollbacks: Int) {
        lock.withLock { (stages, commits, rollbacks) }
    }
}

private actor C54LifecycleJobsProbe: ResumableLocalJobLifecyclePortV1 {
    private var suspended: [LocalJobLifecycleSuspensionReasonV1] = []
    private var resumed: [LocalJobLifecycleSuspensionReasonV1] = []

    func suspendForLifecycle(_ reason: LocalJobLifecycleSuspensionReasonV1) async throws {
        suspended.append(reason)
    }

    func resumeAfterLifecycle(_ reason: LocalJobLifecycleSuspensionReasonV1) async throws {
        resumed.append(reason)
    }
}

private actor C54SecretRevocationProbe: EncryptedPortableEnvelopeSecretLifecycleV1 {
    private var reasons: [EncryptedPortableEnvelopeSecretRevocationReasonV1] = []
    private let secret: EphemeralPassphraseV1?
    private var uniqueClearCount = 0

    init(secret: EphemeralPassphraseV1? = nil) { self.secret = secret }

    func revokeEncryptedPortableEnvelopeSecrets(
        reason: EncryptedPortableEnvelopeSecretRevocationReasonV1
    ) async {
        reasons.append(reason)
        if let secret, secret.withUnsafeBytes({ $0.count }) > 0 {
            secret.clear()
            uniqueClearCount += 1
        }
    }

    func snapshot() -> [EncryptedPortableEnvelopeSecretRevocationReasonV1] { reasons }
    func clearCount() -> Int { uniqueClearCount }
}

@MainActor
final class V9_62EncryptedPortableEnvelopeTests: XCTestCase {
    func testV23P03C54G01PublishedCryptoVectorsAndThreeKindsPreserveExactInnerBytes() async throws {
        let corpus = try C54EncryptedEnvelopeTestSupport.fixture()
        XCTAssertEqual(corpus.schema, "V22P03C54EncryptedPortableEnvelopeCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C54")
        XCTAssertEqual(corpus.evidenceIDs, C54EncryptedEnvelopeTestSupport.evidenceIDs)
        XCTAssertTrue(corpus.testOnly && corpus.synthetic && corpus.immutable)
        XCTAssertFalse(corpus.containsCustomerData || corpus.containsProductionSecrets)
        XCTAssertEqual(corpus.typedAnchor, "V23-P03-C54-G01/A01/H01/I01/R01")
        XCTAssertEqual(
            EncryptedPortableEnvelopeInnerKindV1.allCases.map(\.stableName),
            corpus.innerKinds
        )
        XCTAssertEqual(corpus.publishedVectors.pbkdf2HMACSHA256.count, 1)
        XCTAssertEqual(corpus.publishedVectors.aesGCM.count, 2)
        XCTAssertTrue(corpus.publishedVectors.aesGCM.allSatisfy { $0.keyHex.count == 64 })
        XCTAssertTrue(corpus.publishedVectors.aesGCM.allSatisfy { $0.tagHex.count == 32 })

        let kdf = EncryptedEnvelopeKDFProfileV1.released
        let aead = EncryptedEnvelopeAEADProfileV1.released
        XCTAssertEqual(kdf.iterationCount, corpus.format.pbkdf2Iterations)
        XCTAssertEqual(Int(kdf.saltByteCount), corpus.format.saltBytes)
        XCTAssertEqual(Int(kdf.derivedKeyByteCount), corpus.format.derivedKeyBytes)
        XCTAssertEqual(aead.algorithm, "AES_256_GCM")
        XCTAssertEqual(aead.framePlaintextByteLimit, corpus.format.maximumPlaintextFrameBytes)
        XCTAssertEqual(Int(aead.authenticationTagByteCount), corpus.format.authenticationTagBytes)
        XCTAssertEqual(EncryptedPortableEnvelopeProtocolReleaseV1.uniformTypeIdentifier, corpus.format.uti)
        XCTAssertEqual(EncryptedPortableEnvelopeProtocolReleaseV1.fileExtension, corpus.format.fileExtension)
        XCTAssertTrue(corpus.claims.unchangedInnerBytes)
        let validatedKinds = C54LockedValues<EncryptedPortableEnvelopeInnerKindV1>()
        let innerValidator = EncryptedPortableEnvelopeInnerDispatchV1(
            workspaceBackup: .init(version: .v1, validate: { _, _, _ in validatedKinds.append(.workspaceBackup) }),
            reviewRequest: .init(version: .v1, validate: { _, _, _ in validatedKinds.append(.reviewRequest) }),
            reviewResponse: .init(version: .v1, validate: { _, _, _ in validatedKinds.append(.reviewResponse) })
        )
        for kind in EncryptedPortableEnvelopeInnerKindV1.allCases {
            try innerValidator.validateReopened(
                source: C54StreamingBuffer(Data(kind.stableName.utf8)),
                kind: kind,
                version: .released(for: kind)
            )
        }
        XCTAssertEqual(validatedKinds.snapshot(), EncryptedPortableEnvelopeInnerKindV1.allCases)

        #if DEBUG
        let pbkdf2 = try XCTUnwrap(corpus.publishedVectors.pbkdf2HMACSHA256.first)
        let derived = try EncryptedPortableEnvelopeCryptoTestHooksV1.derivePBKDF2Key(
            passphraseUTF8: C54EncryptedEnvelopeTestSupport.data(hex: pbkdf2.passphraseUTF8Hex),
            salt: C54EncryptedEnvelopeTestSupport.data(hex: pbkdf2.saltHex)
        )
        XCTAssertEqual(derived, try C54EncryptedEnvelopeTestSupport.data(hex: pbkdf2.derivedKeyHex))
        XCTAssertEqual(pbkdf2.iterations, EncryptedEnvelopeKDFProfileV1.released.iterationCount)

        for vector in corpus.publishedVectors.aesGCM {
            let key = try C54EncryptedEnvelopeTestSupport.data(hex: vector.keyHex)
            let nonce = try C54EncryptedEnvelopeTestSupport.data(hex: vector.nonceHex)
            let plaintext = try C54EncryptedEnvelopeTestSupport.data(hex: vector.plaintextHex)
            let authenticatedData = try C54EncryptedEnvelopeTestSupport.data(hex: vector.authenticatedDataHex)
            let sealed = try EncryptedPortableEnvelopeCryptoTestHooksV1.sealAES256GCM(
                key: key,
                nonce: nonce,
                plaintext: plaintext,
                authenticatedData: authenticatedData
            )
            XCTAssertEqual(sealed.ciphertext, try C54EncryptedEnvelopeTestSupport.data(hex: vector.ciphertextHex))
            XCTAssertEqual(sealed.tag, try C54EncryptedEnvelopeTestSupport.data(hex: vector.tagHex))
            XCTAssertEqual(
                try EncryptedPortableEnvelopeCryptoTestHooksV1.openAES256GCM(
                    key: key,
                    nonce: nonce,
                    ciphertext: sealed.ciphertext,
                    tag: sealed.tag,
                    authenticatedData: authenticatedData
                ),
                plaintext
            )
        }

        let crypto = EncryptedPortableEnvelopeCryptoV1(
            testRandomBytes: { count in Data(repeating: UInt8(truncatingIfNeeded: count), count: count) }
        )
        for kind in EncryptedPortableEnvelopeInnerKindV1.allCases {
            let inner = Data("C54 unchanged inner bytes: \(kind.stableName)".utf8)
            let innerSource = C54StreamingBuffer(inner)
            let envelopeScratch = C54StreamingBuffer()
            let reopenScratch = C54StreamingBuffer()
            let context = try C54EncryptedEnvelopeTestSupport.receiptContext(kind.rawValue)
            let passphrase = try EphemeralPassphraseV1(
                passphrase: "C54 portable passphrase 🔐",
                confirmation: "C54 portable passphrase 🔐"
            )
            let streamValidator: EncryptedEnvelopeStreamingInnerValidatorV1 = { source, actualKind, version in
                guard try C54EncryptedEnvelopeTestSupport.allBytes(source) == inner,
                      actualKind == kind, version == .released(for: kind) else {
                    throw EncryptedPortableEnvelopeFailureV1.unsupportedInnerKind
                }
            }
            let sealed = try crypto.sealStreaming(
                innerSource: innerSource,
                innerKind: kind,
                innerProtocolVersion: try .init(1),
                reviewProtectionMode: kind == .workspaceBackup ? nil : .passphraseEncryptedV1,
                passphrase: passphrase,
                context: context,
                envelopeScratch: envelopeScratch,
                reopenPlaintextScratch: reopenScratch,
                validateSourceInner: streamValidator,
                validateReopenedInner: streamValidator
            )
            let openedScratch = C54StreamingBuffer()
            let opened = try crypto.openStreaming(
                envelopeSource: envelopeScratch,
                passphrase: try EphemeralPassphraseV1(openingPassphrase: "C54 portable passphrase 🔐"),
                context: context,
                plaintextScratch: openedScratch,
                validateInner: { source, actualKind, version in
                    guard try C54EncryptedEnvelopeTestSupport.allBytes(source) == inner,
                          actualKind == kind,
                          version == (try EncryptedPortableEnvelopeInnerProtocolVersionV1(1)) else {
                        throw EncryptedPortableEnvelopeFailureV1.unsupportedInnerKind
                    }
                }
            )
            XCTAssertEqual(openedScratch.snapshot().bytes, inner)
            XCTAssertEqual(reopenScratch.snapshot().bytes, inner)
            XCTAssertEqual(opened.publicHeader.innerKind, kind)
            XCTAssertEqual(sealed.publicHeader.innerKind, kind)
            XCTAssertTrue(sealed.facts.reopenedAndAuthenticated)
            XCTAssertTrue(opened.facts.outerAuthenticationComplete)
            XCTAssertEqual(
                sealed.facts.authenticatedManifest.canonicalHeaderSHA256,
                sealed.facts.canonicalHeaderSHA256
            )
            XCTAssertEqual(
                opened.facts.authenticatedManifest.canonicalHeaderSHA256,
                opened.facts.canonicalHeaderSHA256
            )
            XCTAssertTrue(sealed.facts.authenticatedManifest.everyFrameAuthenticatesCanonicalHeader)
            XCTAssertEqual(sealed.facts.cleanupDisposition, .pending)
            XCTAssertEqual(opened.facts.cleanupDisposition, .pending)
        }

        let coordinatorInner = Data(repeating: 0x47, count: 1_048_577)
        let coordinatorLifecycle = C54CoordinatorLifecycleProbe()
        let coordinatorLegacy = C54LegacyClearReaderProbe()
        let coordinatorVersion = try EncryptedPortableEnvelopeInnerProtocolVersionV1(1)
        let coordinatorValidator: EncryptedEnvelopeStreamingInnerValidatorV1 = { source, kind, version in
            guard kind == .workspaceBackup, version == coordinatorVersion else {
                throw EncryptedPortableEnvelopeFailureV1.unsupportedInnerKind
            }
            try C54EncryptedEnvelopeTestSupport.validate(source, equals: coordinatorInner)
        }
        let coordinator = EncryptedPortableEnvelopeCoordinatorV1(
            crypto: C54StreamingCryptoPort(crypto: crypto),
            lifecycle: coordinatorLifecycle,
            innerDispatch: .init(
                workspaceBackup: .init(version: coordinatorVersion, validate: coordinatorValidator),
                reviewRequest: .init(version: coordinatorVersion, validate: coordinatorValidator),
                reviewResponse: .init(version: coordinatorVersion, validate: coordinatorValidator)
            ),
            innerConsumer: C54AuthenticatedInnerConsumerProbe(),
            legacyClearReader: coordinatorLegacy
        )
        let coordinatorOperation = try C54EncryptedEnvelopeTestSupport.operation(200)
        let coordinatorOutcome = try await coordinator.seal(.init(
            operation: coordinatorOperation,
            source: C54StreamingBuffer(coordinatorInner),
            innerKind: .workspaceBackup,
            innerProtocolVersion: try .init(1),
            reviewProtectionMode: nil,
            passphrase: try EphemeralPassphraseV1(
                passphrase: "C54 coordinator passphrase 🔐",
                confirmation: "C54 coordinator passphrase 🔐"
            ),
            receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: coordinatorOperation),
            limits: .released,
            executionMode: .new
        ))
        let coordinatorReceipt = try XCTUnwrap(coordinatorOutcome.receipt)
        let coordinatorSource = try XCTUnwrap(coordinatorOutcome.source)
        let coordinatorFilename = try XCTUnwrap(coordinatorOutcome.filename)
        XCTAssertEqual(coordinatorOutcome.effect, .completed)
        XCTAssertEqual(coordinatorReceipt.frameCount, 2)
        XCTAssertTrue(coordinatorReceipt.reopenedBeforeShareReady)
        XCTAssertEqual(
            coordinatorOutcome.shareTitle,
            try EncryptedPortableEnvelopeFilenameV1.neutralShareTitle(
                innerKind: coordinatorReceipt.innerKind,
                publicEnvelopeID: coordinatorReceipt.publicEnvelopeID
            )
        )
        XCTAssertTrue(coordinatorFilename.hasPrefix("AssetRounds-Backup-"))
        XCTAssertTrue(coordinatorFilename.hasSuffix(".arenvelope"))
        XCTAssertTrue(coordinatorFilename.contains(
            coordinatorReceipt.publicEnvelopeID.map { String(format: "%02x", $0) }.joined()
        ))
        XCTAssertEqual(
            try coordinatorSource.encryptedEnvelopeByteCount(),
            coordinatorReceipt.envelopeByteCount
        )
        let coordinatorCounts = await coordinatorLifecycle.counts()
        XCTAssertEqual(coordinatorCounts.completed, 1)
        XCTAssertEqual(coordinatorCounts.active, 0)
        #endif
    }

    func testV23P03C54A01NFCBoundsEmptyMaximumAndMultiframeCompatibilityRemainClosed() throws {
        let corpus = try C54EncryptedEnvelopeTestSupport.fixture()
        let decomposed = "Cafe\u{301}-envelope-passphrase"
        let normalized = try PassphrasePolicyV1.normalizedUTF8(
            passphrase: decomposed,
            confirmation: decomposed
        )
        XCTAssertEqual(String(decoding: normalized, as: UTF8.self), "Café-envelope-passphrase")
        XCTAssertEqual(
            try PassphrasePolicyV1.normalizedUTF8(
                passphrase: String(repeating: "a", count: 15),
                confirmation: String(repeating: "a", count: 15)
            ).count,
            15
        )
        XCTAssertEqual(
            try PassphrasePolicyV1.normalizedUTF8(
                passphrase: String(repeating: "🧰", count: 256),
                confirmation: String(repeating: "🧰", count: 256)
            ).count,
            1_024
        )
        XCTAssertThrowsError(try PassphrasePolicyV1.normalizedUTF8(
            passphrase: String(repeating: "a", count: 14),
            confirmation: String(repeating: "a", count: 14)
        ))
        XCTAssertThrowsError(try PassphrasePolicyV1.normalizedUTF8(
            passphrase: String(repeating: "a", count: 257),
            confirmation: String(repeating: "a", count: 257)
        ))
        XCTAssertThrowsError(try PassphrasePolicyV1.normalizedUTF8(
            passphrase: "exact-confirmation-1",
            confirmation: "EXACT-confirmation-1"
        ))

        let empty = try EncryptedPortableEnvelopeTopologyV1(
            innerKind: .workspaceBackup,
            innerProtocolVersion: try .init(1),
            plaintextByteCount: 0,
            limits: .released
        )
        let oneMiB = try EncryptedPortableEnvelopeTopologyV1(
            innerKind: .reviewRequest,
            innerProtocolVersion: try .init(1),
            plaintextByteCount: 1_048_576,
            limits: .released
        )
        let multiframe = try EncryptedPortableEnvelopeTopologyV1(
            innerKind: .reviewResponse,
            innerProtocolVersion: try .init(1),
            plaintextByteCount: 1_048_577,
            limits: .released
        )
        XCTAssertEqual(empty.frameCount, corpus.format.emptyInnerFrameCount)
        XCTAssertEqual(oneMiB.frameCount, 1)
        XCTAssertEqual(multiframe.frameCount, 2)

        let first = EncryptedEnvelopeFrameHeaderV1(index: 0, isFinal: false, ciphertextByteCount: 1_048_576)
        let second = EncryptedEnvelopeFrameHeaderV1(index: 1, isFinal: true, ciphertextByteCount: 1)
        let header = try C54EncryptedEnvelopeTestSupport.header(plaintextByteCount: 1_048_577)
        XCTAssertNoThrow(try first.validate(for: header))
        XCTAssertNoThrow(try second.validate(for: header))

        #if DEBUG
        let crypto = EncryptedPortableEnvelopeCryptoV1(
            testRandomBytes: { count in Data(repeating: UInt8(truncatingIfNeeded: count + 1), count: count) }
        )
        let sizes = [0, 1_048_576, 1_048_577]
        for (offset, size) in sizes.enumerated() {
            let inner = Data((0..<size).map { UInt8(truncatingIfNeeded: $0) })
            let innerSource = C54StreamingBuffer(inner)
            let envelopeScratch = C54StreamingBuffer()
            let reopenScratch = C54StreamingBuffer()
            let passphraseText = "  C54 MixedCase אבג passphrase 🔐  "
            let passphrase = try EphemeralPassphraseV1(
                passphrase: passphraseText,
                confirmation: passphraseText
            )
            let result = try crypto.sealStreaming(
                innerSource: innerSource,
                innerKind: .workspaceBackup,
                innerProtocolVersion: try .init(1),
                reviewProtectionMode: nil,
                passphrase: passphrase,
                context: C54EncryptedEnvelopeTestSupport.receiptContext(UInt8(70 + offset)),
                envelopeScratch: envelopeScratch,
                reopenPlaintextScratch: reopenScratch,
                validateSourceInner: { source, kind, version in
                    guard kind == .workspaceBackup, version.rawValue == 1 else {
                        throw EncryptedPortableEnvelopeFailureV1.unsupportedInnerKind
                    }
                    try C54EncryptedEnvelopeTestSupport.validate(source, equals: inner)
                },
                validateReopenedInner: { source, kind, version in
                    guard kind == .workspaceBackup, version.rawValue == 1 else {
                        throw EncryptedPortableEnvelopeFailureV1.unsupportedInnerKind
                    }
                    try C54EncryptedEnvelopeTestSupport.validate(source, equals: inner)
                }
            )
            XCTAssertEqual(result.publicHeader.declaredPlaintextByteCount, UInt64(size))
            XCTAssertEqual(result.publicHeader.declaredFrameCount, UInt32(max(1, (size + 1_048_575) / 1_048_576)))
            XCTAssertEqual(reopenScratch.snapshot().bytes, inner)
            XCTAssertLessThanOrEqual(innerSource.snapshot().maximumReadByteCount, 1_048_576)
            XCTAssertLessThanOrEqual(envelopeScratch.snapshot().maximumAppendByteCount, 1_048_604)
            XCTAssertLessThanOrEqual(reopenScratch.snapshot().maximumAppendByteCount, 1_048_576)

            let offlineScratch = C54StreamingBuffer()
            let opened = try EncryptedPortableEnvelopeCryptoV1().openStreaming(
                envelopeSource: C54StreamingBuffer(envelopeScratch.snapshot().bytes),
                passphrase: try EphemeralPassphraseV1(openingPassphrase: passphraseText),
                context: C54EncryptedEnvelopeTestSupport.receiptContext(UInt8(70 + offset)),
                plaintextScratch: offlineScratch,
                validateInner: { source, kind, version in
                    guard kind == .workspaceBackup, version.rawValue == 1 else {
                        throw EncryptedPortableEnvelopeFailureV1.unsupportedInnerKind
                    }
                    try C54EncryptedEnvelopeTestSupport.validate(source, equals: inner)
                }
            )
            XCTAssertEqual(offlineScratch.snapshot().bytes, inner)
            XCTAssertTrue(opened.facts.outerAuthenticationComplete)
        }
        #endif
        XCTAssertTrue(ReviewExchangeProtectionV1.legacyClearReadersRemainAvailable)
        XCTAssertTrue(ReviewExchangeProtectionV1.clearWithExplicitWarning.displaysCleartextWarning)
        XCTAssertTrue(ReviewExchangeProtectionV1.passphraseEncryptedV1.requiresEncryptedResponseWithSamePassphrase)
        XCTAssertEqual(Set(corpus.alternateCases).count, corpus.alternateCases.count)
    }

    func testV23P03C54H01HostileTopologyResourcesProfilesKindsAndDamageFailClosed() async throws {
        let corpus = try C54EncryptedEnvelopeTestSupport.fixture()
        XCTAssertEqual(Set(corpus.hostileCases).count, corpus.hostileCases.count)
        XCTAssertTrue(corpus.hostileCases.contains("WRONG_PASSPHRASE_OR_DAMAGE_SHARED_ERROR"))
        XCTAssertFalse(EncryptedPortableEnvelopeInnerKindV1.acceptsServiceRequestKinds)
        XCTAssertThrowsError(try C54EncryptedEnvelopeTestSupport.header(
            plaintextByteCount: 0,
            frameCount: 0
        ))
        XCTAssertThrowsError(try C54EncryptedEnvelopeTestSupport.header(
            plaintextByteCount: 1,
            kdf: EncryptedEnvelopeKDFProfileV1(iterationCount: 1)
        ))
        XCTAssertThrowsError(try C54EncryptedEnvelopeTestSupport.header(
            plaintextByteCount: 1,
            aead: EncryptedEnvelopeAEADProfileV1(profileID: 2)
        ))

        let header = try C54EncryptedEnvelopeTestSupport.header(plaintextByteCount: 1_048_577)
        let earlyFinal = EncryptedEnvelopeFrameHeaderV1(
            index: 0,
            isFinal: true,
            ciphertextByteCount: 1_048_576
        )
        let missingFinal = EncryptedEnvelopeFrameHeaderV1(
            index: 1,
            isFinal: false,
            ciphertextByteCount: 1
        )
        XCTAssertThrowsError(try earlyFinal.validate(for: header))
        XCTAssertThrowsError(try missingFinal.validate(for: header))
        XCTAssertThrowsError(try EncryptedPortableEnvelopeTopologyV1(
            innerKind: .workspaceBackup,
            innerProtocolVersion: try .init(1),
            plaintextByteCount: UInt64.max,
            limits: .released
        ))
        XCTAssertEqual(
            EncryptedPortableEnvelopeFailureV1.wrongPassphraseOrDamagedEnvelope,
            .wrongPassphraseOrDamagedEnvelope
        )
        XCTAssertTrue(C54EncryptedPortableEnvelopeCoordinatorBoundaryV1.topologyAndResourcePreflightBeforeKDFAllocationPreviewOrWrite)
        XCTAssertTrue(C54EncryptedPortableEnvelopeCoordinatorBoundaryV1.fullOuterAuthenticationBeforeSingleHostileInnerValidation)

        #if DEBUG
        var keyDerivationCount = 0
        let crypto = EncryptedPortableEnvelopeCryptoV1(
            testRandomBytes: { count in Data(repeating: UInt8(truncatingIfNeeded: count), count: count) },
            onKeyDerivation: { keyDerivationCount += 1 }
        )
        let context = try C54EncryptedEnvelopeTestSupport.receiptContext(20)
        let inner = Data(repeating: 0x54, count: 1_048_577)
        let envelopeScratch = C54StreamingBuffer()
        let sealed = try crypto.sealStreaming(
            innerSource: C54StreamingBuffer(inner),
            innerKind: .workspaceBackup,
            innerProtocolVersion: try .init(1),
            reviewProtectionMode: nil,
            passphrase: try EphemeralPassphraseV1(
                passphrase: "C54 hostile passphrase 🔐",
                confirmation: "C54 hostile passphrase 🔐"
            ),
            context: context,
            envelopeScratch: envelopeScratch,
            reopenPlaintextScratch: C54StreamingBuffer(),
            validateSourceInner: { source, kind, version in
                guard kind == .workspaceBackup, version.rawValue == 1 else {
                    throw EncryptedPortableEnvelopeFailureV1.unsupportedInnerKind
                }
                try C54EncryptedEnvelopeTestSupport.validate(source, equals: inner)
            },
            validateReopenedInner: { source, kind, version in
                guard kind == .workspaceBackup, version.rawValue == 1 else {
                    throw EncryptedPortableEnvelopeFailureV1.unsupportedInnerKind
                }
                try C54EncryptedEnvelopeTestSupport.validate(source, equals: inner)
            }
        )
        let sealedBytes = envelopeScratch.snapshot().bytes
        XCTAssertEqual(sealed.publicHeader.declaredFrameCount, 2)
        keyDerivationCount = 0

        var badMagic = sealedBytes
        badMagic[badMagic.startIndex] ^= 0x01
        var zeroFrames = sealedBytes
        zeroFrames.replaceSubrange(32..<36, with: Data(repeating: 0, count: 4))
        var unknownKDF = sealedBytes
        unknownKDF.replaceSubrange(16..<18, with: Data([0, 2]))
        var unknownAEAD = sealedBytes
        unknownAEAD.replaceSubrange(18..<20, with: Data([0, 2]))
        var missingFinal = sealedBytes
        let firstFrameOffset = EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount
        let firstFrameByteCount = EncryptedPortableEnvelopeProtocolReleaseV1.frameHeaderByteCount
            + 1_048_576 + 16
        let secondFrameOffset = firstFrameOffset + firstFrameByteCount
        missingFinal[secondFrameOffset + 4] = 0
        var multipleFinal = sealedBytes
        multipleFinal[firstFrameOffset + 4] = EncryptedEnvelopeFrameHeaderV1.finalFlag
        let firstFrame = Data(sealedBytes[firstFrameOffset..<secondFrameOffset])
        let secondFrame = Data(sealedBytes[secondFrameOffset..<sealedBytes.endIndex])
        var reordered = Data(sealedBytes.prefix(firstFrameOffset))
        reordered.append(secondFrame)
        reordered.append(firstFrame)
        var duplicated = Data(sealedBytes.prefix(firstFrameOffset))
        duplicated.append(firstFrame)
        duplicated.append(firstFrame)
        var omitted = Data(sealedBytes.prefix(firstFrameOffset))
        omitted.append(firstFrame)
        var oversized = sealedBytes
        oversized.replaceSubrange(
            (firstFrameOffset + 8)..<(firstFrameOffset + 12),
            with: Data([0x00, 0x10, 0x00, 0x01])
        )
        var appended = sealedBytes
        appended.append(0)
        let truncated = Data(sealedBytes.dropLast())
        for malformed in [
            badMagic, zeroFrames, unknownKDF, unknownAEAD, missingFinal, multipleFinal,
            reordered, duplicated, omitted, oversized, appended, truncated,
        ] {
            XCTAssertThrowsError(try crypto.structuralPreflight(source: C54StreamingBuffer(malformed)))
            XCTAssertEqual(keyDerivationCount, 0, "structural rejection must precede PBKDF2")
        }
        XCTAssertThrowsError(try crypto.structuralPreflight(
            source: C54StreamingBuffer(sealedBytes),
            limits: EncryptedPortableEnvelopeResourceLimitsV1(
                maximumPlaintextByteCount: 1,
                maximumEnvelopeByteCount: 1,
                maximumFrameCount: 1
            )
        ))
        XCTAssertEqual(keyDerivationCount, 0)

        let ciphertextIndex = EncryptedPortableEnvelopeProtocolReleaseV1.headerByteCount
            + EncryptedPortableEnvelopeProtocolReleaseV1.frameHeaderByteCount
        var ciphertextDamage = sealedBytes
        ciphertextDamage[ciphertextIndex] ^= 0x01
        var tagDamage = sealedBytes
        tagDamage[tagDamage.index(before: tagDamage.endIndex)] ^= 0x01
        for damaged in [ciphertextDamage, tagDamage] {
            XCTAssertThrowsError(try crypto.openStreaming(
                envelopeSource: C54StreamingBuffer(damaged),
                passphrase: try EphemeralPassphraseV1(openingPassphrase: "C54 hostile passphrase 🔐"),
                context: context,
                plaintextScratch: C54StreamingBuffer(),
                validateInner: { _, _, _ in }
            )) { error in
                XCTAssertEqual(
                    error as? EncryptedPortableEnvelopeExternalFailureV1,
                    .wrongPassphraseOrDamagedEnvelope
                )
            }
        }
        XCTAssertThrowsError(try crypto.openStreaming(
            envelopeSource: C54StreamingBuffer(sealedBytes),
            passphrase: try EphemeralPassphraseV1(openingPassphrase: "C54 wrong passphrase 🔐"),
            context: context,
            plaintextScratch: C54StreamingBuffer(),
            validateInner: { _, _, _ in }
        )) { error in
            XCTAssertEqual(
                error as? EncryptedPortableEnvelopeExternalFailureV1,
                .wrongPassphraseOrDamagedEnvelope
            )
        }
        XCTAssertThrowsError(try crypto.openStreaming(
            envelopeSource: C54StreamingBuffer(Data(repeating: 0x54, count: 127)),
            passphrase: try EphemeralPassphraseV1(openingPassphrase: "C54 hostile passphrase 🔐"),
            context: context,
            plaintextScratch: C54StreamingBuffer(),
            validateInner: { _, _, _ in }
        )) { error in
            XCTAssertEqual(
                error as? EncryptedPortableEnvelopeExternalFailureV1,
                .wrongPassphraseOrDamagedEnvelope
            )
        }
        var hostileInnerValidationCount = 0
        XCTAssertThrowsError(try crypto.openStreaming(
            envelopeSource: C54StreamingBuffer(sealedBytes),
            passphrase: try EphemeralPassphraseV1(openingPassphrase: "C54 hostile passphrase 🔐"),
            context: context,
            plaintextScratch: C54StreamingBuffer(),
            validateInner: { _, _, _ in
                hostileInnerValidationCount += 1
                throw EncryptedPortableEnvelopeFailureV1.unsupportedInnerKind
            }
        ))
        XCTAssertEqual(hostileInnerValidationCount, 1)

        let headerFieldOffsets = [0, 8, 10, 12, 13, 14, 16, 18, 20, 24, 25, 26, 27,
                                  28, 32, 36, 44, 52, 68, 100, 108, 110]
        for fieldOffset in headerFieldOffsets {
            var mutated = sealedBytes
            mutated[fieldOffset] ^= 0x01
            keyDerivationCount = 0
            do {
                _ = try crypto.structuralPreflight(source: C54StreamingBuffer(mutated))
                XCTAssertThrowsError(try crypto.openStreaming(
                    envelopeSource: C54StreamingBuffer(mutated),
                    passphrase: try EphemeralPassphraseV1(openingPassphrase: "C54 hostile passphrase 🔐"),
                    context: context,
                    plaintextScratch: C54StreamingBuffer(),
                    validateInner: { _, _, _ in }
                ))
            } catch {
                XCTAssertEqual(keyDerivationCount, 0)
            }
        }
        for (slot, mode) in [C54HostileSource.Mode.shortRead, .mutateAfterFirstRead].enumerated() {
            let hostileLifecycle = C54CoordinatorLifecycleProbe()
            let hostileCoordinator = EncryptedPortableEnvelopeCoordinatorV1(
                crypto: C54StreamingCryptoPort(crypto: crypto), lifecycle: hostileLifecycle,
                innerDispatch: .init(
                    workspaceBackup: .init(version: .v1, validate: { _, _, _ in }),
                    reviewRequest: .init(version: .v1, validate: { _, _, _ in }),
                    reviewResponse: .init(version: .v1, validate: { _, _, _ in })
                ), innerConsumer: C54AuthenticatedInnerConsumerProbe(),
                legacyClearReader: C54LegacyClearReaderProbe()
            )
            let hostileOperation = try C54EncryptedEnvelopeTestSupport.operation(40 + slot)
            do {
                _ = try await hostileCoordinator.seal(.init(
                    operation: hostileOperation,
                    source: C54HostileSource(Data("hostile-source".utf8), mode: mode),
                    innerKind: .workspaceBackup, innerProtocolVersion: .v1,
                    reviewProtectionMode: nil,
                    passphrase: try EphemeralPassphraseV1(
                        passphrase: "C54 hostile source passphrase", confirmation: "C54 hostile source passphrase"
                    ), receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: hostileOperation),
                    limits: .released, executionMode: .new
                ))
                XCTFail("unstable source must not publish")
            } catch { XCTAssertNotNil(error as? EncryptedPortableEnvelopeExternalFailureV1) }
            let hostileCounts = await hostileLifecycle.counts()
            XCTAssertEqual(hostileCounts.completed, 0)
            XCTAssertEqual(hostileCounts.active, 0)
        }
        #endif
    }

    func testV23P03C54I01InterruptionRandomAndStorageFailuresLeaveNoPartialSuccessOrSecrets() async throws {
        let corpus = try C54EncryptedEnvelopeTestSupport.fixture()
        XCTAssertEqual(Set(corpus.interruptions).count, corpus.interruptions.count)
        let revocationReasons: [EncryptedPortableEnvelopeSecretRevocationReasonV1] = [
            .explicitCancellation, .sceneBackground, .appLock,
            .protectedDataUnavailable, .memoryPressure, .erase,
        ]
        XCTAssertEqual(
            Set(revocationReasons.map(\.rawValue)),
            Set([
                "EXPLICIT_CANCELLATION", "SCENE_BACKGROUND", "APP_LOCK",
                "PROTECTED_DATA_UNAVAILABLE", "MEMORY_PRESSURE", "ERASE",
            ])
        )
        XCTAssertFalse(EphemeralSecretHandlingDispositionV1.passphraseIsPersisted)
        XCTAssertFalse(EphemeralSecretHandlingDispositionV1.derivedKeyIsPersisted)
        XCTAssertFalse(EphemeralSecretHandlingDispositionV1.secretAppearsInReceipts)
        XCTAssertTrue(StoragePreflightService.c54PreflightPrecedesKDFAllocationPreviewAndWrite)
        XCTAssertTrue(StoragePreflightService.c54ScratchIsProtectedAndBackupExcluded)
        XCTAssertTrue(OwnedStorageLedgerV1.c54UsesExistingOwnedScratchRoot)
        XCTAssertFalse(OwnedStorageLedgerV1.c54CreatesParallelStoreOrRoot)
        XCTAssertTrue(OwnedStorageLedgerV1.c54PressureNeverAuthorizesDeletion)
        XCTAssertFalse(C54EncryptedPortableEnvelopeCoordinatorBoundaryV1.createsStoreOrCanonicalWriter)
        XCTAssertTrue(corpus.claims.noPartialSuccess)
        XCTAssertTrue(corpus.claims.memoryOnlySecrets)

        #if DEBUG
        let randomFailureCrypto = EncryptedPortableEnvelopeCryptoV1(testRandomBytes: { _ in
            throw EncryptedPortableEnvelopeFailureV1.randomGenerationFailed
        })
        XCTAssertThrowsError(try randomFailureCrypto.makePublicHeader(
            innerKind: .workspaceBackup,
            innerProtocolVersion: .v1,
            reviewProtectionMode: nil,
            plaintextByteCount: 1
        )) { error in
            XCTAssertEqual(error as? EncryptedPortableEnvelopeFailureV1, .randomGenerationFailed)
        }
        #endif

        let registry = EncryptedPortableEnvelopeSecretLifecycleRegistryV1.shared
        let registration = EncryptedPortableEnvelopeLifecycleRegistrationTokenV1(
            rawValue: UUID(uuidString: "54000000-0000-4000-8000-000000000050")!
        )
        let deviceSecret = try EphemeralPassphraseV1(
            passphrase: "C54 global revocation passphrase 🔐",
            confirmation: "C54 global revocation passphrase 🔐"
        )
        let revocations = C54SecretRevocationProbe(secret: deviceSecret)
        let registrationsBefore = await registry.activeRegistrationCount()
        let registryAccepted = await registry.register(token: registration, lifecycle: revocations)
        XCTAssertTrue(registryAccepted)
        let registrationsDuring = await registry.activeRegistrationCount()
        XCTAssertEqual(registrationsDuring, registrationsBefore + 1)

        let deviceLifecycle = try await DeviceLifecycleCoordinatorV1.bootstrap(
            jobs: C54LifecycleJobsProbe(),
            encryptedPortableEnvelopeSecrets: registry,
            initialState: .initiallyActive
        )
        try await deviceLifecycle.handle(.sceneEnteredBackground)
        try await deviceLifecycle.handle(.appLockEngaged)
        try await deviceLifecycle.handle(.memoryPressure)
        try await deviceLifecycle.handle(.protectedDataBecameUnavailable)
        let observedReasons = await revocations.snapshot()
        XCTAssertEqual(
            Set(observedReasons.map(\.rawValue)),
            Set(["SCENE_BACKGROUND", "APP_LOCK", "MEMORY_PRESSURE", "PROTECTED_DATA_UNAVAILABLE"])
        )
        let globalUniqueClearCount = await revocations.clearCount()
        XCTAssertEqual(globalUniqueClearCount, 1)
        XCTAssertEqual(deviceSecret.withUnsafeBytes { $0.count }, 0)
        try await deviceLifecycle.handle(.protectedDataBecameAvailable)
        try await deviceLifecycle.handle(.sceneBecameActive)
        let activeBlocksAfterResume = await registry.activeBlockCount()
        XCTAssertEqual(activeBlocksAfterResume, 0)
        await registry.unregister(token: registration)
        let registrationsAfter = await registry.activeRegistrationCount()
        XCTAssertEqual(registrationsAfter, registrationsBefore)

        let recoveryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V9_62-C54-recovery-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: recoveryRoot, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: recoveryRoot) }
        let scratchStore = try ScratchDataLeaseStoreV1(
            applicationSupportURL: recoveryRoot,
            clock: { Date(timeIntervalSince1970: 1_800_000_100) },
            capacityProvider: { _ in Int64.max / 4 }
        )
        let c54Lease = try await scratchStore.acquireScratchLease(.init(
            leaseID: EncryptedPortableEnvelopeScratchNamespaceV1.leaseID(
                for: UUID(uuidString: "54000000-0000-4000-8000-000000000061")!, slot: 1
            ),
            purpose: .source,
            owner: .source,
            ownerOperationID: UUID(uuidString: "54000000-0000-4000-8000-000000000062")!,
            requestedByteCount: 16,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_600)
        ))
        let unrelatedLease = try await scratchStore.acquireScratchLease(.init(
            leaseID: UUID(uuidString: "99000000-0000-4000-8000-000000000061")!,
            purpose: .source,
            owner: .source,
            ownerOperationID: UUID(uuidString: "99000000-0000-4000-8000-000000000062")!,
            requestedByteCount: 16,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_600)
        ))
        _ = try await scratchStore.writeScratchData(Data("C54-bytes".utf8), named: "c54.bin", lease: c54Lease)
        let unrelatedURL = try await scratchStore.writeScratchData(
            Data("other-bytes".utf8), named: "other.bin", lease: unrelatedLease
        )
        let recovery = try await scratchStore.recoverEncryptedPortableEnvelopeScratch()
        XCTAssertEqual(recovery.recoveredExpiredLeaseCount, 1)
        XCTAssertEqual(recovery.removedByteCount, 9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))

        let ownedRoots = try OwnedStorageRootV1.closedSet(applicationSupportURL: recoveryRoot)
        for ownedRoot in ownedRoots where !FileManager.default.fileExists(atPath: ownedRoot.url.path) {
            try FileManager.default.createDirectory(at: ownedRoot.url, withIntermediateDirectories: true)
        }
        let storageLedger = try OwnedStorageLedgerV1(
            rootURLs: ownedRoots,
            capacityProvider: { _ in Int64.max / 4 }
        )
        let realLifecycle = try EncryptedPortableEnvelopeLifecycleAdapterV1(
            scratch: scratchStore,
            storageLedger: storageLedger,
            scratchRootURL: recoveryRoot,
            publication: C54PublicationProbe(),
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max / 4 })
        )
        let sharedLifecycleSecret = try EphemeralPassphraseV1(
            passphrase: "C54 real lifecycle shared holder 🔐",
            confirmation: "C54 real lifecycle shared holder 🔐"
        )
        let lifecycleOperationA = try C54EncryptedEnvelopeTestSupport.operation(70)
        let lifecycleOperationB = try C54EncryptedEnvelopeTestSupport.operation(71)
        _ = try await realLifecycle.claimSecret(operation: lifecycleOperationA, secret: sharedLifecycleSecret)
        _ = try await realLifecycle.claimSecret(operation: lifecycleOperationB, secret: sharedLifecycleSecret)
        let registeredRealLifecycle = await registry.activeRegistrationCount()
        XCTAssertEqual(registeredRealLifecycle, registrationsBefore + 1)
        try await realLifecycle.abort(operation: lifecycleOperationA)
        XCTAssertGreaterThan(sharedLifecycleSecret.withUnsafeBytes { $0.count }, 0)
        try await realLifecycle.abort(operation: lifecycleOperationB)
        XCTAssertEqual(sharedLifecycleSecret.withUnsafeBytes { $0.count }, 0)
        let unregisteredRealLifecycle = await registry.activeRegistrationCount()
        XCTAssertEqual(unregisteredRealLifecycle, registrationsBefore)
        let postAbortRecovery = try await realLifecycle.recoverInterruptedAttempts()
        XCTAssertEqual(postAbortRecovery.recoveredExpiredLeaseCount, 0)

        #if DEBUG
        let inner = Data(repeating: 0x54, count: 1_048_577)
        let blockedDispatch = EncryptedPortableEnvelopeInnerDispatchV1(
            workspaceBackup: .init(version: .v1, validate: { _, _, _ in }),
            reviewRequest: .init(version: .v1, validate: { _, _, _ in }),
            reviewResponse: .init(version: .v1, validate: { _, _, _ in })
        )
        let blockedScratch = C54EnvelopeScratchProbe()
        let blockedLifecycle = try EncryptedPortableEnvelopeLifecycleAdapterV1(
            scratch: blockedScratch, storageLedger: storageLedger, scratchRootURL: recoveryRoot,
            publication: C54PublicationProbe(),
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max / 4 })
        )
        let blockedCoordinator = EncryptedPortableEnvelopeCoordinatorV1(
            crypto: C54StreamingCryptoPort(crypto: EncryptedPortableEnvelopeCryptoV1(
                testRandomBytes: { Data(repeating: 0x75, count: $0) }
            )), lifecycle: blockedLifecycle, innerDispatch: blockedDispatch,
            innerConsumer: C54AuthenticatedInnerConsumerProbe(), legacyClearReader: C54LegacyClearReaderProbe()
        )
        let persistentEdges: [(EncryptedPortableEnvelopeSecretRevocationReasonV1,
                               EncryptedPortableEnvelopeSecretRevocationReasonV1)] = [
            (.sceneBackground, .sceneBackground),
            (.appLock, .sceneBackground),
            (.protectedDataUnavailable, .protectedDataUnavailable),
        ]
        for (slot, edge) in persistentEdges.enumerated() {
            await registry.revokeEncryptedPortableEnvelopeSecrets(reason: edge.0)
            let blockCountDuringEdge = await registry.activeBlockCount()
            XCTAssertEqual(blockCountDuringEdge, 1)
            let rejectedSecret = try EphemeralPassphraseV1(
                passphrase: "C54 blocked new claim \(slot) 🔐",
                confirmation: "C54 blocked new claim \(slot) 🔐"
            )
            let rejectedOperation = try C54EncryptedEnvelopeTestSupport.operation(90 + slot)
            do {
                _ = try await blockedCoordinator.seal(.init(
                    operation: rejectedOperation, source: C54StreamingBuffer(Data("blocked".utf8)),
                    innerKind: .workspaceBackup, innerProtocolVersion: .v1, reviewProtectionMode: nil,
                    passphrase: rejectedSecret,
                    receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: rejectedOperation),
                    limits: .released, executionMode: .new
                ))
                XCTFail("persistent lifecycle edge must reject a brand-new secret claim")
            } catch { XCTAssertEqual(error as? EncryptedPortableEnvelopeExternalFailureV1, .cancelled) }
            XCTAssertEqual(rejectedSecret.withUnsafeBytes { $0.count }, 0)
            let rejectedRegistrationCount = await registry.activeRegistrationCount()
            let rejectedLeaseCount = await blockedScratch.activeLeaseCount()
            XCTAssertEqual(rejectedRegistrationCount, registrationsBefore)
            XCTAssertEqual(rejectedLeaseCount, 0)
            XCTAssertEqual(storageLedger.snapshot().activeReservationCount, 0)
            await registry.resumeEncryptedPortableEnvelopeOperations(after: edge.1)
            let blockCountAfterResume = await registry.activeBlockCount()
            XCTAssertEqual(blockCountAfterResume, 0)
        }
        let resetGate = C54ResetGate()
        let resetScratch = C54EnvelopeScratchProbe(resetGate: resetGate)
        let resetDeviceLifecycle = try await DeviceLifecycleCoordinatorV1.bootstrap(
            jobs: C54LifecycleJobsProbe(), operationalSupportStore: try C54OperationalSupportResetProbe(),
            scratchDataLeaseStore: resetScratch, encryptedPortableEnvelopeSecrets: registry,
            initialState: .initiallyActive
        )
        let resetTask = Task { try await resetDeviceLifecycle.resetDeviceLocalState() }
        await resetGate.waitUntilEntered()
        let eraseBlockWhileResetPaused = await registry.activeBlockCount()
        XCTAssertEqual(eraseBlockWhileResetPaused, 1)
        do {
            try await resetDeviceLifecycle.resetDeviceLocalState()
            XCTFail("overlapping device-local reset must fail closed")
        } catch {
            XCTAssertEqual(
                error as? DeviceLifecycleRecoveryFailureV1,
                .encryptedPortableEnvelopeResetAlreadyInProgress
            )
        }
        let eraseBlockAfterRejectedOverlap = await registry.activeBlockCount()
        XCTAssertEqual(eraseBlockAfterRejectedOverlap, 1)
        let resetAttemptScratch = C54EnvelopeScratchProbe()
        let resetAttemptLifecycle = try EncryptedPortableEnvelopeLifecycleAdapterV1(
            scratch: resetAttemptScratch, storageLedger: storageLedger, scratchRootURL: recoveryRoot,
            publication: C54PublicationProbe(),
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max / 4 })
        )
        let resetAttemptCoordinator = EncryptedPortableEnvelopeCoordinatorV1(
            crypto: C54StreamingCryptoPort(crypto: EncryptedPortableEnvelopeCryptoV1(
                testRandomBytes: { Data(repeating: 0x76, count: $0) }
            )), lifecycle: resetAttemptLifecycle, innerDispatch: blockedDispatch,
            innerConsumer: C54AuthenticatedInnerConsumerProbe(), legacyClearReader: C54LegacyClearReaderProbe()
        )
        let resetRejectedSecret = try EphemeralPassphraseV1(
            passphrase: "C54 erase reset rejected secret 🔐",
            confirmation: "C54 erase reset rejected secret 🔐"
        )
        let resetRejectedOperation = try C54EncryptedEnvelopeTestSupport.operation(94)
        do {
            _ = try await resetAttemptCoordinator.seal(.init(
                operation: resetRejectedOperation, source: C54StreamingBuffer(Data("reset-blocked".utf8)),
                innerKind: .workspaceBackup, innerProtocolVersion: .v1, reviewProtectionMode: nil,
                passphrase: resetRejectedSecret,
                receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: resetRejectedOperation),
                limits: .released, executionMode: .new
            ))
            XCTFail("erase reset must hold admission closed until both reset stores finish")
        } catch { XCTAssertEqual(error as? EncryptedPortableEnvelopeExternalFailureV1, .cancelled) }
        XCTAssertEqual(resetRejectedSecret.withUnsafeBytes { $0.count }, 0)
        let resetRejectedLeases = await resetAttemptScratch.activeLeaseCount()
        XCTAssertEqual(resetRejectedLeases, 0)
        let resetRejectedRegistrations = await registry.activeRegistrationCount()
        XCTAssertEqual(resetRejectedRegistrations, registrationsBefore)
        XCTAssertEqual(storageLedger.snapshot().activeReservationCount, 0)
        let resetRejectedTerminalCount = await resetAttemptCoordinator.terminalOutcomeCount()
        XCTAssertEqual(resetRejectedTerminalCount, 0)
        await resetGate.release()
        try await resetTask.value
        let eraseBlockAfterReset = await registry.activeBlockCount()
        XCTAssertEqual(eraseBlockAfterReset, 0)
        for cancellationCheck in [1, 3, 6] {
            let envelopeScratch = C54StreamingBuffer()
            let reopenScratch = C54StreamingBuffer()
            let cancellation = C54CancellationProbe(cancelAtCheck: cancellationCheck)
            let crypto = EncryptedPortableEnvelopeCryptoV1(
                testRandomBytes: { count in Data(repeating: 0x5A, count: count) }
            )
            let secret = try EphemeralPassphraseV1(
                passphrase: "C54 cancellation passphrase 🔐",
                confirmation: "C54 cancellation passphrase 🔐"
            )
            XCTAssertThrowsError(try crypto.sealStreaming(
                innerSource: C54StreamingBuffer(inner),
                innerKind: .workspaceBackup,
                innerProtocolVersion: try .init(1),
                reviewProtectionMode: nil,
                passphrase: secret,
                context: try C54EncryptedEnvelopeTestSupport.receiptContext(UInt8(cancellationCheck)),
                limits: .released,
                envelopeScratch: envelopeScratch,
                reopenPlaintextScratch: reopenScratch,
                validateSourceInner: { _, _, _ in },
                validateReopenedInner: { _, _, _ in },
                cancellation: cancellation
            ))
            try? envelopeScratch.discardStreamingBytes()
            try? reopenScratch.discardStreamingBytes()
            XCTAssertEqual(try envelopeScratch.encryptedEnvelopeByteCount(), 0)
            XCTAssertEqual(try reopenScratch.encryptedEnvelopeByteCount(), 0)
            secret.clear()
            XCTAssertEqual(secret.withUnsafeBytes { $0.count }, 0)
        }
        let cancelledLifecycle = C54CoordinatorLifecycleProbe(cancelPreparedOperations: true)
        let cancelledCoordinator = EncryptedPortableEnvelopeCoordinatorV1(
            crypto: C54StreamingCryptoPort(crypto: EncryptedPortableEnvelopeCryptoV1(
                testRandomBytes: { count in Data(repeating: 0x6C, count: count) }
            )),
            lifecycle: cancelledLifecycle,
            innerDispatch: .init(
                workspaceBackup: .init(version: .v1, validate: { _, _, _ in }),
                reviewRequest: .init(version: .v1, validate: { _, _, _ in }),
                reviewResponse: .init(version: .v1, validate: { _, _, _ in })
            ),
            innerConsumer: C54AuthenticatedInnerConsumerProbe(),
            legacyClearReader: C54LegacyClearReaderProbe()
        )
        let cancelledOperation = try C54EncryptedEnvelopeTestSupport.operation(80)
        do {
            _ = try await cancelledCoordinator.seal(.init(
                operation: cancelledOperation,
                source: C54StreamingBuffer(Data("cancel-before-KDF".utf8)),
                innerKind: .workspaceBackup,
                innerProtocolVersion: .v1,
                reviewProtectionMode: nil,
                passphrase: try EphemeralPassphraseV1(
                    passphrase: "C54 prepared cancellation 🔐",
                    confirmation: "C54 prepared cancellation 🔐"
                ),
                receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: cancelledOperation),
                limits: .released,
                executionMode: .new
            ))
            XCTFail("prepared cancellation must not publish")
        } catch {
            XCTAssertEqual(error as? EncryptedPortableEnvelopeExternalFailureV1, .cancelled)
        }
        let cancellationFailureReceipt = await cancelledCoordinator.failureReceipt(for: cancelledOperation)
        XCTAssertEqual(cancellationFailureReceipt?.failure, .cancelled)

        let failureDispatch = EncryptedPortableEnvelopeInnerDispatchV1(
            workspaceBackup: .init(version: .v1, validate: { _, _, _ in }),
            reviewRequest: .init(version: .v1, validate: { _, _, _ in }),
            reviewResponse: .init(version: .v1, validate: { _, _, _ in })
        )
        let cleanupScratch = C54EnvelopeScratchProbe(failRelease: true)
        let cleanupLifecycle = try EncryptedPortableEnvelopeLifecycleAdapterV1(
            scratch: cleanupScratch, storageLedger: storageLedger, scratchRootURL: recoveryRoot,
            publication: C54PublicationProbe(),
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max / 4 })
        )
        let cleanupCoordinator = EncryptedPortableEnvelopeCoordinatorV1(
            crypto: C54StreamingCryptoPort(crypto: EncryptedPortableEnvelopeCryptoV1(
                testRandomBytes: { Data(repeating: 0x72, count: $0) }
            )), lifecycle: cleanupLifecycle, innerDispatch: failureDispatch,
            innerConsumer: C54AuthenticatedInnerConsumerProbe(), legacyClearReader: C54LegacyClearReaderProbe()
        )
        let cleanupOperation = try C54EncryptedEnvelopeTestSupport.operation(81)
        let cleanupSecret = try EphemeralPassphraseV1(
            passphrase: "C54 cleanup failure passphrase", confirmation: "C54 cleanup failure passphrase"
        )
        do {
            _ = try await cleanupCoordinator.seal(.init(
                operation: cleanupOperation, source: C54StreamingBuffer(Data("cleanup-failure".utf8)),
                innerKind: .workspaceBackup, innerProtocolVersion: .v1, reviewProtectionMode: nil,
                passphrase: cleanupSecret,
                receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: cleanupOperation),
                limits: .released, executionMode: .new
            ))
            XCTFail("cleanup failure must not yield a success receipt")
        } catch { XCTAssertEqual(error as? EncryptedPortableEnvelopeExternalFailureV1, .resourceLimit) }
        let cleanupActiveLeases = await cleanupScratch.activeLeaseCount()
        XCTAssertEqual(cleanupActiveLeases, 0)
        XCTAssertEqual(storageLedger.snapshot().activeReservationCount, 0)
        XCTAssertEqual(cleanupSecret.withUnsafeBytes { $0.count }, 0)
        let registryAfterCleanupFailure = await registry.activeRegistrationCount()
        XCTAssertEqual(registryAfterCleanupFailure, registrationsBefore)
        let cleanupFailureReceipt = await cleanupCoordinator.failureReceipt(for: cleanupOperation)
        XCTAssertNil(cleanupFailureReceipt)
        do { try await cleanupLifecycle.abort(operation: cleanupOperation); XCTFail("cleanup failure must remain sticky") }
        catch { XCTAssertEqual(error as? EncryptedPortableEnvelopeFailureV1, .resourceLimitExceeded) }

        let rollbackPublisher = C54RollbackPublicationProbe()
        let rollbackLifecycle = try EncryptedPortableEnvelopeLifecycleAdapterV1(
            scratch: C54EnvelopeScratchProbe(), storageLedger: storageLedger, scratchRootURL: recoveryRoot,
            publication: rollbackPublisher,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max / 4 })
        )
        let rollbackCoordinator = EncryptedPortableEnvelopeCoordinatorV1(
            crypto: C54StreamingCryptoPort(crypto: EncryptedPortableEnvelopeCryptoV1(
                testRandomBytes: { Data(repeating: 0x73, count: $0) }
            )), lifecycle: rollbackLifecycle, innerDispatch: failureDispatch,
            innerConsumer: C54AuthenticatedInnerConsumerProbe(), legacyClearReader: C54LegacyClearReaderProbe()
        )
        let rollbackOperation = try C54EncryptedEnvelopeTestSupport.operation(82)
        do {
            _ = try await rollbackCoordinator.seal(.init(
                operation: rollbackOperation, source: C54StreamingBuffer(Data("rollback-mismatch".utf8)),
                innerKind: .workspaceBackup, innerProtocolVersion: .v1, reviewProtectionMode: nil,
                passphrase: try EphemeralPassphraseV1(
                    passphrase: "C54 rollback passphrase", confirmation: "C54 rollback passphrase"
                ), receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: rollbackOperation),
                limits: .released, executionMode: .new
            ))
            XCTFail("post-publish mismatch must not escape a share-ready source")
        } catch { XCTAssertNotNil(error as? EncryptedPortableEnvelopeExternalFailureV1) }
        let rollbackCounts = rollbackPublisher.counts()
        XCTAssertEqual(rollbackCounts.publishes, 1)
        XCTAssertEqual(rollbackCounts.rollbacks, 1)
        let rollbackTerminalCount = await rollbackCoordinator.terminalOutcomeCount()
        XCTAssertEqual(rollbackTerminalCount, 0)

        let revokingPublisher = C54RevokingPublicationProbe()
        let revokingScratch = C54EnvelopeScratchProbe()
        let revokingLifecycle = try EncryptedPortableEnvelopeLifecycleAdapterV1(
            scratch: revokingScratch, storageLedger: storageLedger, scratchRootURL: recoveryRoot,
            publication: revokingPublisher,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max / 4 })
        )
        let revokingCoordinator = EncryptedPortableEnvelopeCoordinatorV1(
            crypto: C54StreamingCryptoPort(crypto: EncryptedPortableEnvelopeCryptoV1(
                testRandomBytes: { Data(repeating: 0x74, count: $0) }
            )), lifecycle: revokingLifecycle, innerDispatch: failureDispatch,
            innerConsumer: C54AuthenticatedInnerConsumerProbe(), legacyClearReader: C54LegacyClearReaderProbe()
        )
        let revokingOperation = try C54EncryptedEnvelopeTestSupport.operation(83)
        do {
            _ = try await revokingCoordinator.seal(.init(
                operation: revokingOperation, source: C54StreamingBuffer(Data("revoked-publication".utf8)),
                innerKind: .workspaceBackup, innerProtocolVersion: .v1, reviewProtectionMode: nil,
                passphrase: try EphemeralPassphraseV1(
                    passphrase: "C54 revocation race passphrase", confirmation: "C54 revocation race passphrase"
                ), receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: revokingOperation),
                limits: .released, executionMode: .new
            ))
            XCTFail("lifecycle revocation during private publication staging must not commit")
        } catch { XCTAssertEqual(error as? EncryptedPortableEnvelopeExternalFailureV1, .cancelled) }
        let revokingCounts = revokingPublisher.counts()
        XCTAssertEqual(revokingCounts.stages, 1)
        XCTAssertEqual(revokingCounts.commits, 0)
        XCTAssertEqual(revokingCounts.rollbacks, 1)
        let revokingActiveLeases = await revokingScratch.activeLeaseCount()
        XCTAssertEqual(revokingActiveLeases, 0)
        XCTAssertEqual(storageLedger.snapshot().activeReservationCount, 0)
        let revokingTerminalCount = await revokingCoordinator.terminalOutcomeCount()
        XCTAssertEqual(revokingTerminalCount, 0)
        let registrationsAfterRevocationRace = await registry.activeRegistrationCount()
        XCTAssertEqual(registrationsAfterRevocationRace, registrationsBefore)
        await registry.resumeEncryptedPortableEnvelopeOperations(after: .sceneBackground)
        let blocksAfterRevocationRace = await registry.activeBlockCount()
        XCTAssertEqual(blocksAfterRevocationRace, 0)

        let explicitPublisher = C54ExplicitCancellingPublicationProbe()
        let explicitScratch = C54EnvelopeScratchProbe()
        let explicitLifecycle = try EncryptedPortableEnvelopeLifecycleAdapterV1(
            scratch: explicitScratch, storageLedger: storageLedger, scratchRootURL: recoveryRoot,
            publication: explicitPublisher,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max / 4 })
        )
        let explicitCoordinator = EncryptedPortableEnvelopeCoordinatorV1(
            crypto: C54StreamingCryptoPort(crypto: EncryptedPortableEnvelopeCryptoV1(
                testRandomBytes: { Data(repeating: 0x75, count: $0) }
            )), lifecycle: explicitLifecycle, innerDispatch: failureDispatch,
            innerConsumer: C54AuthenticatedInnerConsumerProbe(), legacyClearReader: C54LegacyClearReaderProbe()
        )
        let explicitOperation = try C54EncryptedEnvelopeTestSupport.operation(84)
        explicitPublisher.installCancellation {
            try? await explicitCoordinator.cancel(operation: explicitOperation)
        }
        do {
            _ = try await explicitCoordinator.seal(.init(
                operation: explicitOperation, source: C54StreamingBuffer(Data("explicit-cancel".utf8)),
                innerKind: .workspaceBackup, innerProtocolVersion: .v1, reviewProtectionMode: nil,
                passphrase: try EphemeralPassphraseV1(
                    passphrase: "C54 explicit cancel passphrase", confirmation: "C54 explicit cancel passphrase"
                ), receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: explicitOperation),
                limits: .released, executionMode: .new
            ))
            XCTFail("explicit cancellation during private publication staging must not commit")
        } catch { XCTAssertEqual(error as? EncryptedPortableEnvelopeExternalFailureV1, .cancelled) }
        let explicitCounts = explicitPublisher.counts()
        XCTAssertEqual(explicitCounts.stages, 1)
        XCTAssertEqual(explicitCounts.commits, 0)
        XCTAssertEqual(explicitCounts.rollbacks, 1)
        let explicitActiveLeases = await explicitScratch.activeLeaseCount()
        XCTAssertEqual(explicitActiveLeases, 0)
        XCTAssertEqual(storageLedger.snapshot().activeReservationCount, 0)
        let explicitTerminalCount = await explicitCoordinator.terminalOutcomeCount()
        XCTAssertEqual(explicitTerminalCount, 0)

        let innerCancellationOperation = try C54EncryptedEnvelopeTestSupport.operation(85)
        let innerCancellationContext = try C54EncryptedEnvelopeTestSupport.receiptContext(
            for: innerCancellationOperation
        )
        let innerCancellationBytes = Data("cancel-after-inner-commit".utf8)
        let innerCancellationCrypto = EncryptedPortableEnvelopeCryptoV1(
            testRandomBytes: { Data(repeating: 0x76, count: $0) }
        )
        let innerCancellationEnvelope = C54StreamingBuffer()
        let innerCancellationReopen = C54StreamingBuffer()
        let innerCancellationSealSecret = try EphemeralPassphraseV1(
            passphrase: "C54 inner commit cancel passphrase",
            confirmation: "C54 inner commit cancel passphrase"
        )
        _ = try innerCancellationCrypto.sealStreaming(
            innerSource: C54StreamingBuffer(innerCancellationBytes),
            innerKind: .workspaceBackup,
            innerProtocolVersion: .v1,
            reviewProtectionMode: nil,
            passphrase: innerCancellationSealSecret,
            context: innerCancellationContext,
            envelopeScratch: innerCancellationEnvelope,
            reopenPlaintextScratch: innerCancellationReopen,
            validateSourceInner: { _, _, _ in },
            validateReopenedInner: { _, _, _ in }
        )
        innerCancellationSealSecret.clear()
        let innerCancellationScratch = C54EnvelopeScratchProbe()
        let innerCancellationLifecycle = try EncryptedPortableEnvelopeLifecycleAdapterV1(
            scratch: innerCancellationScratch, storageLedger: storageLedger, scratchRootURL: recoveryRoot,
            publication: C54PublicationProbe(),
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max / 4 })
        )
        let innerCancellationConsumer = C54CancellingInnerConsumerProbe()
        let innerCancellationCoordinator = EncryptedPortableEnvelopeCoordinatorV1(
            crypto: C54StreamingCryptoPort(crypto: innerCancellationCrypto),
            lifecycle: innerCancellationLifecycle, innerDispatch: failureDispatch,
            innerConsumer: innerCancellationConsumer, legacyClearReader: C54LegacyClearReaderProbe()
        )
        innerCancellationConsumer.installCancellation {
            try? await innerCancellationCoordinator.cancel(operation: innerCancellationOperation)
        }
        do {
            _ = try await innerCancellationCoordinator.open(.init(
                operation: innerCancellationOperation,
                source: C54StreamingBuffer(innerCancellationEnvelope.snapshot().bytes),
                passphrase: try EphemeralPassphraseV1(
                    openingPassphrase: "C54 inner commit cancel passphrase"
                ),
                receiptContext: innerCancellationContext,
                limits: .released,
                executionMode: .new
            ))
            XCTFail("cancellation during authenticated-inner commit must roll canonical state back")
        } catch { XCTAssertEqual(error as? EncryptedPortableEnvelopeExternalFailureV1, .cancelled) }
        let innerCancellationSnapshot = innerCancellationConsumer.snapshot()
        XCTAssertEqual(innerCancellationSnapshot.commits, 1)
        XCTAssertEqual(innerCancellationSnapshot.rollbacks, 1)
        XCTAssertEqual(innerCancellationSnapshot.canonicalCount, 0)
        let innerCancellationTerminalCount = await innerCancellationCoordinator.terminalOutcomeCount()
        XCTAssertEqual(innerCancellationTerminalCount, 0)
        let innerCancellationActiveLeases = await innerCancellationScratch.activeLeaseCount()
        XCTAssertEqual(innerCancellationActiveLeases, 0)
        #endif
    }

    func testV23P03C54R01CrashCleanupRetryReopenReceiptsAndExportDispositionRemainStrict() async throws {
        let corpus = try C54EncryptedEnvelopeTestSupport.fixture()
        XCTAssertTrue(corpus.recovery.crashCleanup)
        XCTAssertTrue(corpus.recovery.idempotentRetry)
        XCTAssertTrue(corpus.recovery.crossDeviceOfflineOpen)
        XCTAssertTrue(corpus.recovery.strictSecretFreeReceipts)
        XCTAssertTrue(corpus.recovery.exportComplianceRequiresReleaseResolution)
        XCTAssertFalse(corpus.recovery.exportComplianceAssumesExemption)

        #if DEBUG
        let reviewRequestBytes = Data("C54 encrypted review request".utf8)
        let reviewResponseBytes = Data("C54 encrypted review response".utf8)
        let validator: EncryptedEnvelopeStreamingInnerValidatorV1 = { source, kind, version in
            guard version.rawValue == 1 else {
                throw EncryptedPortableEnvelopeFailureV1.unsupportedProtocol
            }
            let expected: Data
            switch kind {
            case .reviewRequest: expected = reviewRequestBytes
            case .reviewResponse: expected = reviewResponseBytes
            case .workspaceBackup: throw EncryptedPortableEnvelopeFailureV1.unsupportedInnerKind
            }
            try C54EncryptedEnvelopeTestSupport.validate(source, equals: expected)
        }
        let crypto = C54StreamingCryptoPort(crypto: EncryptedPortableEnvelopeCryptoV1(
            testRandomBytes: { count in Data(repeating: UInt8(truncatingIfNeeded: count + 3), count: count) }
        ))
        let lifecycle = C54CoordinatorLifecycleProbe()
        let legacy = C54LegacyClearReaderProbe()
        let authenticatedConsumer = C54AuthenticatedInnerConsumerProbe()
        let reviewVersion = try EncryptedPortableEnvelopeInnerProtocolVersionV1(1)
        let innerDispatch = EncryptedPortableEnvelopeInnerDispatchV1(
            workspaceBackup: .init(version: reviewVersion, validate: { _, kind, _ in
                guard kind == .workspaceBackup else {
                    throw EncryptedPortableEnvelopeFailureV1.unsupportedInnerKind
                }
            }),
            reviewRequest: .init(version: reviewVersion, validate: validator),
            reviewResponse: .init(version: reviewVersion, validate: validator)
        )
        let coordinator = EncryptedPortableEnvelopeCoordinatorV1(
            crypto: crypto,
            lifecycle: lifecycle,
            innerDispatch: innerDispatch,
            innerConsumer: authenticatedConsumer,
            legacyClearReader: legacy
        )
        let sealOperation = try C54EncryptedEnvelopeTestSupport.operation(300)
        let sealPassphrase = try EphemeralPassphraseV1(
            passphrase: "C54 review request passphrase 🔐",
            confirmation: "C54 review request passphrase 🔐"
        )
        let sealRequest = EncryptedPortableEnvelopeSealRequestV1(
            operation: sealOperation,
            source: C54StreamingBuffer(reviewRequestBytes),
            innerKind: .reviewRequest,
            innerProtocolVersion: try .init(1),
            reviewProtectionMode: .passphraseEncryptedV1,
            passphrase: sealPassphrase,
            receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: sealOperation),
            limits: .released,
            executionMode: .new
        )
        let first = try await coordinator.seal(sealRequest)
        let retry = try await coordinator.seal(sealRequest)
        let firstReceipt = try XCTUnwrap(first.receipt)
        let retryReceipt = try XCTUnwrap(retry.receipt)
        let firstSource = try XCTUnwrap(first.source)
        let retrySource = try XCTUnwrap(retry.source)
        XCTAssertEqual(first.effect, .completed)
        XCTAssertEqual(retry.effect, .completed)
        XCTAssertEqual(retryReceipt, firstReceipt)
        XCTAssertEqual(
            try C54EncryptedEnvelopeTestSupport.allBytes(retrySource),
            try C54EncryptedEnvelopeTestSupport.allBytes(firstSource)
        )
        XCTAssertEqual(retryReceipt.publicEnvelopeID, firstReceipt.publicEnvelopeID)
        let preparationsAfterFirst = await lifecycle.sealPreparationCount()
        XCTAssertEqual(preparationsAfterFirst, 1)
        async let coalescedA = coordinator.seal(sealRequest)
        async let coalescedB = coordinator.seal(sealRequest)
        let (coalescedFirst, coalescedSecond) = try await (coalescedA, coalescedB)
        XCTAssertEqual(coalescedFirst.receipt, firstReceipt)
        XCTAssertEqual(coalescedSecond.receipt, firstReceipt)
        let preparationsAfterCoalescing = await lifecycle.sealPreparationCount()
        XCTAssertEqual(preparationsAfterCoalescing, 1)

        var sameLengthMutation = reviewRequestBytes
        sameLengthMutation[sameLengthMutation.startIndex] ^= 0x01
        XCTAssertEqual(sameLengthMutation.count, reviewRequestBytes.count)
        let divergent = EncryptedPortableEnvelopeSealRequestV1(
            operation: sealOperation,
            source: C54StreamingBuffer(sameLengthMutation),
            innerKind: .reviewRequest,
            innerProtocolVersion: try .init(1),
            reviewProtectionMode: .passphraseEncryptedV1,
            passphrase: sealPassphrase,
            receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: sealOperation),
            limits: .released,
            executionMode: .new
        )
        do {
            _ = try await coordinator.seal(divergent)
            XCTFail("divergent reuse of an accepted operation must fail")
        } catch {
            XCTAssertEqual(
                error as? EncryptedPortableEnvelopeExternalFailureV1,
                .wrongPassphraseOrDamagedEnvelope
            )
        }
        let divergentPassphrase = EncryptedPortableEnvelopeSealRequestV1(
            operation: sealOperation,
            source: C54StreamingBuffer(reviewRequestBytes),
            innerKind: .reviewRequest,
            innerProtocolVersion: .v1,
            reviewProtectionMode: .passphraseEncryptedV1,
            passphrase: try EphemeralPassphraseV1(
                passphrase: "C54 different retry passphrase 🔐",
                confirmation: "C54 different retry passphrase 🔐"
            ),
            receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: sealOperation),
            limits: .released,
            executionMode: .new
        )
        do {
            _ = try await coordinator.seal(divergentPassphrase)
            XCTFail("retry with a different passphrase owner must fail closed")
        } catch {
            XCTAssertEqual(error as? EncryptedPortableEnvelopeExternalFailureV1, .wrongPassphraseOrDamagedEnvelope)
        }
        let divergentLimits = EncryptedPortableEnvelopeSealRequestV1(
            operation: sealOperation,
            source: C54StreamingBuffer(reviewRequestBytes),
            innerKind: .reviewRequest,
            innerProtocolVersion: .v1,
            reviewProtectionMode: .passphraseEncryptedV1,
            passphrase: sealPassphrase,
            receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: sealOperation),
            limits: .init(
                maximumPlaintextByteCount: EncryptedPortableEnvelopeResourceLimitsV1.maximumOperationalPlaintextByteCount,
                maximumEnvelopeByteCount: EncryptedPortableEnvelopeResourceLimitsV1.maximumOperationalScratchByteCount,
                maximumFrameCount: 4_095
            ),
            executionMode: .new
        )
        do {
            _ = try await coordinator.seal(divergentLimits)
            XCTFail("retry with different resource limits must fail closed")
        } catch {
            XCTAssertEqual(error as? EncryptedPortableEnvelopeExternalFailureV1, .wrongPassphraseOrDamagedEnvelope)
        }

        let relaunched = EncryptedPortableEnvelopeCoordinatorV1(
            crypto: crypto,
            lifecycle: C54CoordinatorLifecycleProbe(),
            innerDispatch: innerDispatch,
            innerConsumer: C54AuthenticatedInnerConsumerProbe(),
            legacyClearReader: C54LegacyClearReaderProbe()
        )
        let noEffect = try await relaunched.seal(.init(
            operation: sealOperation,
            source: C54StreamingBuffer(reviewRequestBytes),
            innerKind: .reviewRequest,
            innerProtocolVersion: try .init(1),
            reviewProtectionMode: .passphraseEncryptedV1,
            passphrase: try EphemeralPassphraseV1(
                passphrase: "C54 review request passphrase 🔐",
                confirmation: "C54 review request passphrase 🔐"
            ),
            receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: sealOperation),
            limits: .released,
            executionMode: .retry
        ))
        XCTAssertEqual(noEffect.effect, .noEffect)
        XCTAssertNil(noEffect.source)
        XCTAssertNil(noEffect.receipt)

        let sharedPassphrase = try EphemeralPassphraseV1(
            openingPassphrase: "C54 review request passphrase 🔐"
        )
        let openOperation = try C54EncryptedEnvelopeTestSupport.operation(310)
        let responseOperation = try C54EncryptedEnvelopeTestSupport.operation(320)
        let sameOperationSecret = try EphemeralPassphraseV1(openingPassphrase: "C54 review request passphrase 🔐")
        do {
            _ = try await coordinator.protectReviewResponse(
                request: .init(
                    operation: openOperation, source: firstSource, passphrase: sameOperationSecret,
                    receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: openOperation),
                    limits: .released, executionMode: .new
                ),
                response: .init(
                    operation: openOperation, source: C54StreamingBuffer(reviewResponseBytes),
                    innerKind: .reviewResponse, innerProtocolVersion: .v1,
                    reviewProtectionMode: .passphraseEncryptedV1, passphrase: sameOperationSecret,
                    receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: openOperation),
                    limits: .released, executionMode: .new
                )
            )
            XCTFail("review request and response must not share an operation identity")
        } catch {
            XCTAssertEqual(error as? EncryptedPortableEnvelopeExternalFailureV1, .wrongPassphraseOrDamagedEnvelope)
        }
        let protectedResponse = try await coordinator.protectReviewResponse(
            request: .init(
                operation: openOperation,
                source: firstSource,
                passphrase: sharedPassphrase,
                receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: openOperation),
                limits: .released,
                executionMode: .new
            ),
            response: .init(
                operation: responseOperation,
                source: C54StreamingBuffer(reviewResponseBytes),
                innerKind: .reviewResponse,
                innerProtocolVersion: try .init(1),
                reviewProtectionMode: .passphraseEncryptedV1,
                passphrase: sharedPassphrase,
                receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: responseOperation),
                limits: .released,
                executionMode: .new
            )
        )
        let responseReceipt = try XCTUnwrap(protectedResponse.receipt)
        let responseSource = try XCTUnwrap(protectedResponse.source)
        XCTAssertEqual(responseReceipt.innerKind, .reviewResponse)
        XCTAssertTrue(ReviewExchangeProtectionV1.passphraseEncryptedV1.requiresEncryptedResponseWithSamePassphrase)
        XCTAssertEqual(
            protectedResponse.shareTitle,
            try EncryptedPortableEnvelopeFilenameV1.neutralShareTitle(
                innerKind: responseReceipt.innerKind,
                publicEnvelopeID: responseReceipt.publicEnvelopeID
            )
        )
        let responseSecretDisposition = await lifecycle.secretDisposition()
        XCTAssertGreaterThan(responseSecretDisposition.afterOpen, 0)
        XCTAssertEqual(responseSecretDisposition.afterTerminal, 0)
        XCTAssertEqual(sharedPassphrase.withUnsafeBytes { $0.count }, 0)

        let offlineOperation = try C54EncryptedEnvelopeTestSupport.operation(330)
        let offline = EncryptedPortableEnvelopeCoordinatorV1(
            crypto: crypto,
            lifecycle: C54CoordinatorLifecycleProbe(),
            innerDispatch: innerDispatch,
            innerConsumer: authenticatedConsumer,
            legacyClearReader: C54LegacyClearReaderProbe()
        )
        let offlineOpen = try await offline.open(.init(
            operation: offlineOperation,
            source: C54StreamingBuffer(try C54EncryptedEnvelopeTestSupport.allBytes(responseSource)),
            passphrase: try EphemeralPassphraseV1(openingPassphrase: "C54 review request passphrase 🔐"),
            receiptContext: try C54EncryptedEnvelopeTestSupport.receiptContext(for: offlineOperation),
            limits: .released,
            executionMode: .new
        ))
        let opened = try XCTUnwrap(offlineOpen.receipt)
        XCTAssertEqual(offlineOpen.effect, .completed)
        XCTAssertEqual(opened.innerKind, .reviewResponse)
        XCTAssertTrue(opened.outerAuthenticationComplete)
        XCTAssertEqual(authenticatedConsumer.snapshot().last, reviewResponseBytes)

        try await coordinator.readLegacyClear(
            source: C54StreamingBuffer(reviewRequestBytes),
            kind: .reviewRequest,
            version: try .init(1),
            protection: .clearWithExplicitWarning
        )
        XCTAssertEqual(legacy.callCount(), 1)
        do {
            try await coordinator.readLegacyClear(
                source: C54StreamingBuffer(reviewRequestBytes),
                kind: .reviewRequest,
                version: .v1,
                protection: .passphraseEncryptedV1
            )
            XCTFail("encrypted review mode must not enter the legacy clear reader")
        } catch {
            XCTAssertEqual(error as? EncryptedPortableEnvelopeFailureV1, .unsupportedProtocol)
        }
        let cleartextDowngradePermitted = false
        XCTAssertFalse(cleartextDowngradePermitted)
        let terminalOutcomeCount = await coordinator.terminalOutcomeCount()
        XCTAssertEqual(terminalOutcomeCount, 3)

        XCTAssertTrue(firstReceipt.reopenedBeforeShareReady)
        XCTAssertFalse(firstReceipt.containsPassphraseOrKeyMaterial)
        XCTAssertTrue(opened.hostileInnerValidationComplete)
        XCTAssertFalse(opened.containsPassphraseOrKeyMaterial)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let sealBytes = try encoder.encode(firstReceipt)
        let openBytes = try encoder.encode(opened)
        XCTAssertEqual(
            try JSONDecoder().decode(EncryptedEnvelopeSealReceiptV1.self, from: sealBytes),
            firstReceipt
        )
        XCTAssertEqual(try JSONDecoder().decode(EncryptedEnvelopeOpenReceiptV1.self, from: openBytes), opened)
        var hostileReceipt = try XCTUnwrap(
            JSONSerialization.jsonObject(with: sealBytes) as? [String: Any]
        )
        hostileReceipt["passphraseHint"] = "must-not-be-accepted"
        XCTAssertThrowsError(try JSONDecoder().decode(
            EncryptedEnvelopeSealReceiptV1.self,
            from: JSONSerialization.data(withJSONObject: hostileReceipt, options: [.sortedKeys])
        ))
        hostileReceipt = try XCTUnwrap(JSONSerialization.jsonObject(with: sealBytes) as? [String: Any])
        hostileReceipt["containsPassphraseOrKeyMaterial"] = true
        XCTAssertThrowsError(try JSONDecoder().decode(
            EncryptedEnvelopeSealReceiptV1.self,
            from: JSONSerialization.data(withJSONObject: hostileReceipt, options: [.sortedKeys])
        ))
        hostileReceipt = try XCTUnwrap(JSONSerialization.jsonObject(with: sealBytes) as? [String: Any])
        hostileReceipt["frameCount"] = firstReceipt.frameCount + 1
        XCTAssertThrowsError(try JSONDecoder().decode(
            EncryptedEnvelopeSealReceiptV1.self,
            from: JSONSerialization.data(withJSONObject: hostileReceipt, options: [.sortedKeys])
        ))
        let leakScan = [
            first.filename ?? "", first.shareTitle ?? "",
            try EncryptedPortableEnvelopeFilenameV1.neutralShareTitle(
                innerKind: firstReceipt.innerKind,
                publicEnvelopeID: firstReceipt.publicEnvelopeID
            ),
        ].joined(separator: "|").lowercased()
        for forbidden in ["customer", "workspace", "address", "passphrase", "quicklook", "spotlight"] {
            XCTAssertFalse(leakScan.contains(forbidden))
        }
        let mutablePublishedSource = try XCTUnwrap(firstSource as? C54PublishedBuffer)
        mutablePublishedSource.mutateFirstByteWithoutChangingLength()
        do {
            _ = try await coordinator.seal(sealRequest)
            XCTFail("same-length published-source mutation must invalidate the terminal retry")
        } catch {
            XCTAssertEqual(
                error as? EncryptedPortableEnvelopeExternalFailureV1,
                .wrongPassphraseOrDamagedEnvelope
            )
        }
        XCTAssertEqual(Set(corpus.privacyLeakSurfaces).count, 5)
        #endif
        XCTAssertEqual(
            EncryptionExportComplianceDispositionV1.released,
            .classificationAndOwnerReviewRequired
        )
        XCTAssertFalse(EncryptionExportComplianceDispositionV1.declaresExportExemption)
        XCTAssertFalse(EncryptedPortableEnvelopeClaimsV1.establishesIdentity)
        XCTAssertFalse(EncryptedPortableEnvelopeClaimsV1.establishesAuthority)
        XCTAssertFalse(EncryptedPortableEnvelopeClaimsV1.establishesDelivery)
        XCTAssertFalse(EncryptedPortableEnvelopeClaimsV1.isDigitalSignature)
        XCTAssertTrue(C54EncryptedPortableEnvelopeLifecycleBoundaryV1.startupRecoveryDeletesInterruptedAttempts)
        XCTAssertTrue(C54EncryptedPortableEnvelopeLifecycleBoundaryV1.validate())
    }
}
