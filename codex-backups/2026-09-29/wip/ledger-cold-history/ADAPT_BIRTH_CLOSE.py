from pathlib import Path
p=Path('.codex-temp/cold-ledger-continuation-successor-v1/candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift');s=p.read_text()
a='''        case publication(PublicationSessionV1)
    }

    private final class C16SemanticSessionV1'''
b='''        case publication(PublicationSessionV1)
        case captureBornSource(path: String, bytes: Data, fullFact: String)
    }

    private final class C16SemanticSessionV1''';assert a in s;s=s.replace(a,b,1)
a='        private var failurePublicationIndex = 0\n'
s=s.replace(a,a+'''        private var captureAuthorized = false
        var nextCapture: (path: String, bytes: Data, fullFact: String)? {
            guard case let .captureBornSource(path, bytes, fullFact)? = pending.last else { return nil }
            return (path, bytes, fullFact)
        }
        func authorizeCaptureAdvance() throws {
            guard borrowed, nextCapture != nil, !captureAuthorized else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            captureAuthorized = true
        }
''',1)
a='''            case let .publication(publication):
                if try publication.advance() { pending.append(.publication(publication)) }
            }
'''
b='''            case let .publication(publication):
                if try publication.advance() { pending.append(.publication(publication)) }
            case .captureBornSource:
                guard borrowed, captureAuthorized else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                captureAuthorized = false
            }
''';assert a in s;s=s.replace(a,b,1)
a='''                try requireOriginalEraseC16Cut()
                let outcome = Result { try session.advance() }'''
b='''                try requireOriginalEraseC16Cut()
                if let capture = session.nextCapture {
                    guard let permit = originalEraseColdPermit else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    try permit.requireHeld()
                    try permit.captureBornSource(path: capture.path, bytes: capture.bytes, fullFact: capture.fullFact)
                    try permit.requireHeld()
                    try permit.requireTransferredSource(path: capture.path, bytes: capture.bytes, fullFact: capture.fullFact)
                    try requireOriginalEraseC16Cut()
                    try session.authorizeCaptureAdvance()
                }
                let outcome = Result { try session.advance() }''';assert a in s;s=s.replace(a,b,1)
# Replace one return in c16PublicationSteps only.
a='''        return [.publication(try PublicationSessionV1(store: self, data: data,
            finalName: file.lastPathComponent, parent: ingressControlDescriptor(),
            directoryURL: file.deletingLastPathComponent(), finalURL: file,
            leaseName: nil, atomicExclusiveRename: atomicExclusiveRename,
            authorityCheck: { _ = try self.protectedIngressReceiptDirectory() },
            borrowedOperationID: originalEraseOperationID))]
    }
'''
b='''        var work: [C16SemanticStepV1] = [.publication(try PublicationSessionV1(store: self, data: data,
            finalName: file.lastPathComponent, parent: ingressControlDescriptor(),
            directoryURL: file.deletingLastPathComponent(), finalURL: file,
            leaseName: nil, atomicExclusiveRename: atomicExclusiveRename,
            authorityCheck: { _ = try self.protectedIngressReceiptDirectory() },
            borrowedOperationID: originalEraseOperationID))]
        if originalEraseBorrowedExclusiveCheck != nil { work += c16CaptureBornSourceSteps(data, at: file) }
        return work
    }

    private func c16CaptureBornSourceSteps(_ bytes: Data, at file: URL) -> [C16SemanticStepV1] {
        [.plan { [self] _ in
            guard originalEraseBorrowedExclusiveCheck != nil,
                  file.deletingLastPathComponent() == (try protectedIngressReceiptDirectory()),
                  bytes.count <= Self.originalEraseC16SourceMaximum(name: file.lastPathComponent),
                  let leaf = try readOriginalErasePublicationLeaf(named: file.lastPathComponent,
                    parent: ingressControlDescriptor(), maximumBytes: bytes.count),
                  leaf.0.st_nlink == 1, leaf.1 == bytes else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try verifySourceReadPolicy(.temporaryFile, at: file)
            let fact = Self.originalEraseSourceFullFact(leaf.0)
            if let initial = originalEraseC16SourceInputs[file.lastPathComponent],
               initial.bytes == bytes, initial.fullFact == fact { return [] }
            return [.captureBornSource(path: "ProtectedIngressReceiptsV1/" + file.lastPathComponent,
                bytes: bytes, fullFact: fact)]
        }]
    }
''';assert a in s;s=s.replace(a,b,1)
# Capture finalizing rename's genuine replacement source after exact readback.
a='''            return steps
        }]
    }

    private struct C16ValidatedIngressSnapshotV1'''
b='''            if originalEraseBorrowedExclusiveCheck != nil {
                steps += c16CaptureBornSourceSteps(try CompatibilityCanonicalV1.encode(finalized), at: file)
            }
            return steps
        }]
    }

    private struct C16ValidatedIngressSnapshotV1''';assert a in s;s=s.replace(a,b,1)
# Checked close is actor-local and proof-bracketed per descriptor. The old
# ordinary/original-source checked close API remains present unchanged.
anchor='    /// A failed postimage proof cannot allow deinit to silently close a live\n'
addition='''    @MainActor func closeCheckedForSchema2BorrowedScope(
        verifyBeforeClose: Bool, rootName: String,
        requireHeld: @MainActor () throws -> Void
    ) throws {
        guard !rootCloseAttempted, !operationsCloseAttempted,
              rootDescriptor >= 0, operationsDescriptor >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try requireHeld()
        if verifyBeforeClose { try verify(rootName: rootName) }
        try requireHeld()
        let root = rootDescriptor
        rootCloseAttempted = true
        let rootAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(root)
        let rootResult = Darwin.close(root)
        // The retired numeric alias is never inspected or retried, including
        // a close whose result is ambiguous. Quarantine retains its receipt.
        rootDescriptor = -1
        guard rootResult == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        ScratchUncertainCloseQuarantineV1.shared.complete(rootAttempt)
        try requireHeld()
        let operations = operationsDescriptor
        operationsCloseAttempted = true
        let operationsAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(operations)
        try requireHeld()
        let operationsResult = Darwin.close(operations)
        operationsDescriptor = -1
        guard operationsResult == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        ScratchUncertainCloseQuarantineV1.shared.complete(operationsAttempt)
        try requireHeld()
    }

'''
assert anchor in s;s=s.replace(anchor,addition+anchor,1)
a='''    func verify(rootName: String) throws {
        var operations = stat()'''
s=s.replace(a,'''    func verify(rootName: String) throws {
        guard !rootCloseAttempted, !operationsCloseAttempted,
              rootDescriptor >= 0, operationsDescriptor >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var operations = stat()''',1)
a='''                    try control.closeCheckedForExclusiveOriginalEraseRead(
                        verifyBeforeClose:
                            !store.originalEraseControlRemovalProved,
                        rootName: "ProtectedIngressReceiptsV1")'''
b='''                    try control.closeCheckedForSchema2BorrowedScope(
                        verifyBeforeClose: !store.originalEraseControlRemovalProved,
                        rootName: "ProtectedIngressReceiptsV1", requireHeld: { try permit.requireHeld() })''';assert a in s;s=s.replace(a,b,1)
a='''                try store.authority.closeCheckedForExclusiveOriginalEraseRead(
                    verifyBeforeClose:
                        !store.originalEraseRootRemovalProved)'''
b='''                try store.authority.closeCheckedForSchema2BorrowedScope(
                    verifyBeforeClose: !store.originalEraseRootRemovalProved,
                    rootName: "ScratchDataV1", requireHeld: { try permit.requireHeld() })
                try permit.requireHeld()''';assert a in s;s=s.replace(a,b,1)
p.write_text(s)
