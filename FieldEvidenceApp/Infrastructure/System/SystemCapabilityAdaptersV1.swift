import Foundation
import UIKit

actor SystemCapabilityRuntimeAdapterV1: CapabilityRuntimePortV1 {
    typealias StateProbe = @Sendable () async -> CapabilityStateV1
    typealias PermissionRequester = @Sendable () async throws -> CapabilityStateV1

    private let probes: [CapabilityIDV1: StateProbe]
    private let requesters: [CapabilityIDV1: PermissionRequester]

    init(
        probes: [CapabilityIDV1: StateProbe],
        requesters: [CapabilityIDV1: PermissionRequester]
    ) throws {
        guard Set(probes.keys) == Set(CapabilityIDV1.allCases),
              Set(requesters.keys).isSubset(of: Set(probes.keys)) else {
            throw CapabilityContractFailureV1.duplicateCapability
        }
        self.probes = probes
        self.requesters = requesters
    }

    func state(for capabilityID: CapabilityIDV1) async throws -> CapabilityStateV1 {
        guard let probe = probes[capabilityID] else {
            throw CapabilityContractFailureV1.unknownCapability
        }
        return await probe()
    }

    func requestPermission(
        for capabilityID: CapabilityIDV1,
        boundary: PermissionRequestBoundaryV1
    ) async throws -> CapabilityStateV1 {
        guard boundary.capabilityID == capabilityID,
              let requester = requesters[capabilityID] else {
            throw CapabilityContractFailureV1.permissionRequestNotUserInitiated
        }
        return try await requester()
    }
}

struct NoOpHapticRuntimeAdapterV1: HapticRuntimePortV1 {
    func isAvailable() async -> Bool { false }
    func emitSuccess() async {}
    func emitWarning() async {}
}

struct PreparedDisabledOCRProposalExtractorV1: OCRProposalExtractingV1 {
    func extract(_ request: OCRExtractionRequestV1) async throws -> [OCRProposalEvidenceV1] {
        try request.validate()
        throw OCRProposalFailureV1.capabilityUnavailable
    }
}

struct UIKitHapticRuntimeAdapterV1: HapticRuntimePortV1 {
    func isAvailable() async -> Bool { true }

    func emitSuccess() async {
        await MainActor.run {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func emitWarning() async {
        await MainActor.run {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}

actor CapabilityScratchLeaseAdapterV1: CapabilityScratchLeasePortV1 {
    private struct PendingFinish {
        let lease: CapabilityScratchLeaseV1
        let disposition: ScratchPublicationDispositionV1
        let immutableContentReceiptDigest: String?
        let task: Task<ScratchPublicationLinkageReceiptV1, Error>
    }

    static let maximumActiveLeaseCount = 128
    private let scratch: any ScratchDataLeasePortV1
    private var active: [UUID: ScratchDataLeaseV1] = [:]
    private var acquiring: Set<UUID> = []
    private var writing: Set<UUID> = []
    private var finishing: [UUID: PendingFinish] = [:]
    private var recoveryGeneration: UInt64 = 0
    private var recoveryInProgress = false
    private var terminals: [UUID: (CapabilityScratchLeaseV1, ScratchPublicationLinkageReceiptV1)] = [:]
    private var terminalOrder: [UUID] = []

    init(scratch: any ScratchDataLeasePortV1) {
        self.scratch = scratch
    }

    func acquire(
        _ request: CapabilityScratchLeaseRequestV1
    ) async throws -> CapabilityScratchLeaseV1 {
        guard !recoveryInProgress,
              active.count + acquiring.count < Self.maximumActiveLeaseCount,
              active[request.leaseID] == nil,
              !acquiring.contains(request.leaseID),
              finishing[request.leaseID] == nil,
              terminals[request.leaseID] == nil else {
            throw CapabilityContractFailureV1.invalidScratchLinkage
        }
        acquiring.insert(request.leaseID)
        defer { acquiring.remove(request.leaseID) }
        let observedRecoveryGeneration = recoveryGeneration
        let mapped = try ScratchDataLeaseRequestV1(
            leaseID: request.leaseID,
            purpose: try purpose(request.purpose),
            owner: try owner(request.purpose),
            ownerOperationID: request.operationID,
            requestedByteCount: request.requestedByteCount,
            createdAt: request.createdAt,
            expiresAt: request.expiresAt,
            protection: .complete,
            backupPolicy: .excluded
        )
        let lease = try await scratch.acquireScratchLease(mapped)
        guard observedRecoveryGeneration == recoveryGeneration else {
            try await scratch.releaseScratchLease(lease, terminal: .recoveredExpired)
            throw CapabilityContractFailureV1.invalidScratchLinkage
        }
        active[request.leaseID] = lease
        return CapabilityScratchLeaseV1(
            leaseID: request.leaseID,
            purpose: request.purpose,
            relativeDirectory: lease.relativeDirectory
        )
    }

    func write(
        _ data: Data,
        named: String,
        lease: CapabilityScratchLeaseV1
    ) async throws -> URL {
        guard !recoveryInProgress,
              let backing = active[lease.leaseID],
              !writing.contains(lease.leaseID),
              finishing[lease.leaseID] == nil,
              backing.relativeDirectory == lease.relativeDirectory,
              backing.request.purpose == (try purpose(lease.purpose)) else {
            throw CapabilityContractFailureV1.invalidScratchLinkage
        }
        writing.insert(lease.leaseID)
        defer { writing.remove(lease.leaseID) }
        return try await scratch.writeScratchData(data, named: named, lease: backing)
    }

    func finish(
        lease: CapabilityScratchLeaseV1,
        disposition: ScratchPublicationDispositionV1,
        immutableContentReceiptDigest: String?
    ) async throws -> ScratchPublicationLinkageReceiptV1 {
        guard !recoveryInProgress else {
            throw CapabilityContractFailureV1.invalidScratchLinkage
        }
        if let prior = terminals[lease.leaseID] {
            guard prior.0 == lease,
                  prior.1.disposition == disposition,
                  prior.1.immutableContentReceiptDigest == immutableContentReceiptDigest else {
                throw CapabilityContractFailureV1.invalidScratchLinkage
            }
            return prior.1
        }
        let pending: PendingFinish
        if let existing = finishing[lease.leaseID] {
            guard existing.lease == lease,
                  existing.disposition == disposition,
                  existing.immutableContentReceiptDigest == immutableContentReceiptDigest else {
                throw CapabilityContractFailureV1.invalidScratchLinkage
            }
            pending = existing
        } else {
            guard let backing = active[lease.leaseID],
                  !writing.contains(lease.leaseID),
                  backing.relativeDirectory == lease.relativeDirectory else {
                throw CapabilityContractFailureV1.invalidScratchLinkage
            }
            let terminal: ScratchDataLeaseTerminalV1
            switch disposition {
            case .acceptedIntoImmutableContent: terminal = .completed
            case .rejected, .cancelled: terminal = .cancelled
            case .expired: terminal = .recoveredExpired
            case .failed: terminal = .failed
            }
            let receipt = try ScratchPublicationLinkageReceiptV1(
                operationID: backing.request.ownerOperationID,
                leaseID: lease.leaseID,
                purpose: lease.purpose,
                disposition: disposition,
                immutableContentReceiptDigest: immutableContentReceiptDigest,
                scratchDeleted: true
            )
            let task = Task { [scratch] in
                try await scratch.releaseScratchLease(backing, terminal: terminal)
                return receipt
            }
            let created = PendingFinish(
                lease: lease,
                disposition: disposition,
                immutableContentReceiptDigest: immutableContentReceiptDigest,
                task: task
            )
            finishing[lease.leaseID] = created
            pending = created
        }
        do {
            let receipt = try await pending.task.value
            recordFinished(lease: lease, receipt: receipt)
            return receipt
        } catch {
            finishing.removeValue(forKey: lease.leaseID)
            throw error
        }
    }

    func recoverAfterInterruption() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        guard !recoveryInProgress,
              acquiring.isEmpty,
              writing.isEmpty,
              finishing.isEmpty else {
            throw CapabilityContractFailureV1.invalidScratchLinkage
        }
        recoveryInProgress = true
        recoveryGeneration &+= 1
        defer { recoveryInProgress = false }
        let summary = try await scratch.recoverScratchLeases()
        active.removeAll()
        finishing.removeAll()
        return summary
    }

    private func recordFinished(
        lease: CapabilityScratchLeaseV1,
        receipt: ScratchPublicationLinkageReceiptV1
    ) {
        if terminals[lease.leaseID] == nil {
            active.removeValue(forKey: lease.leaseID)
            terminals[lease.leaseID] = (lease, receipt)
            terminalOrder.append(lease.leaseID)
            if terminalOrder.count > Self.maximumActiveLeaseCount {
                let expiredID = terminalOrder.removeFirst()
                terminals.removeValue(forKey: expiredID)
            }
        }
        finishing.removeValue(forKey: lease.leaseID)
    }

    private func purpose(_ value: CapabilityScratchPurposeV1) throws -> ScratchDataPurposeV1 {
        switch value {
        case .capture: return .capture
        case .importData: return .importData
        case .source: return .source
        case .supportExport: return .supportExport
        case .none: throw CapabilityContractFailureV1.invalidScratchLinkage
        }
    }

    private func owner(_ value: CapabilityScratchPurposeV1) throws -> ScratchDataOwnerV1 {
        switch value {
        case .capture: return .capture
        case .importData: return .importData
        case .source: return .source
        case .supportExport: return .supportExport
        case .none: throw CapabilityContractFailureV1.invalidScratchLinkage
        }
    }
}
