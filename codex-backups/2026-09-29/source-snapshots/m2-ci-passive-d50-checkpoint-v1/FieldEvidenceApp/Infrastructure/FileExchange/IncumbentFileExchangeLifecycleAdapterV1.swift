import Foundation

/// The file exchange codec is deliberately small and closed.  It accepts only
/// the UTF-8, delimiter, header, version, and budget described by the selected
/// release; it never infers a profile from input bytes.
enum IncumbentDelimitedTextCodecV1 {
    static func decode(
        input: IncumbentFileInputV1,
        release: IncumbentFileProfileReleaseV1
    ) throws -> (detection: IncumbentFileDetectionV1, rows: [IncumbentFileRowV1]) {
        try release.validate()
        guard release.encoding == .utf8,
              UInt64(input.bytes.count) <= release.budget.maximumByteCount else {
            throw IncumbentFileContractFailureV1.budgetExceeded
        }
        let parsed = try IncumbentDelimitedTextSafetyV1.validateInputBytes(
            input.bytes,
            release: release
        )
        guard let header = parsed.first, header == release.orderedHeaders else {
            throw IncumbentFileContractFailureV1.headerMismatch
        }
        let dataRows = Array(parsed.dropFirst())
        guard dataRows.count <= release.budget.maximumRowCount else {
            throw IncumbentFileContractFailureV1.budgetExceeded
        }

        guard let versionIndex = release.orderedHeaders.firstIndex(of: release.versionHeader) else {
            throw IncumbentFileContractFailureV1.unsupportedVersion
        }
        var rows: [IncumbentFileRowV1] = []
        rows.reserveCapacity(dataRows.count)
        for (offset, values) in dataRows.enumerated() {
            guard values.count == release.orderedHeaders.count else {
                throw IncumbentFileContractFailureV1.headerMismatch
            }
            guard values[versionIndex] == release.versionValue else {
                throw IncumbentFileContractFailureV1.unsupportedVersion
            }
            let cells = try zip(release.mappingManifest.mappings, values).map { mapping, value in
                try validateInboundText(value, maximumScalars: release.budget.maximumScalarCountPerCell)
                return try IncumbentFileCellV1(
                    field: mapping.canonicalField,
                    value: value,
                    maximumScalars: release.budget.maximumScalarCountPerCell
                )
            }
            rows.append(try IncumbentFileRowV1(
                ordinal: offset + 1,
                cells: cells,
                release: release
            ))
        }
        let detection = try IncumbentFileDetectionV1(
            release: release,
            inputSHA256: input.byteSHA256,
            observedHeaders: header,
            observedVersion: release.versionValue,
            rowCount: rows.count
        )
        return (detection, rows)
    }

    static func encode(
        rows: [IncumbentFileRowV1],
        scope: IncumbentExchangeScopeV1,
        release: IncumbentFileProfileReleaseV1
    ) throws -> Data {
        try release.validate()
        guard release.encoding == .utf8,
              release.direction.permitsExport,
              scope.releaseID == release.releaseID,
              scope.releaseSHA256 == release.releaseSHA256,
              rows.count <= release.budget.maximumRowCount else {
            throw IncumbentFileContractFailureV1.budgetExceeded
        }

        let mappings = release.mappingManifest.mappings
        for (offset, row) in rows.enumerated() {
            try row.validate(release: release)
            guard row.ordinal == offset + 1 else {
                throw IncumbentFileContractFailureV1.invalidValue
            }
        }

        var lines: [String] = []
        lines.reserveCapacity(rows.count + 1)
        lines.append(release.orderedHeaders.map {
            escape($0, delimiter: release.delimiter.scalar)
        }.joined(separator: String(release.delimiter.scalar)))
        for row in rows {
            let byField = Dictionary(uniqueKeysWithValues: row.cells.map { ($0.field, $0.value) })
            let values = try mappings.map { mapping -> String in
                guard scope.allowedCanonicalFields.contains(mapping.canonicalField) else {
                    return ""
                }
                guard let value = byField[mapping.canonicalField] else {
                    throw IncumbentFileContractFailureV1.headerMismatch
                }
                try validateInboundText(value, maximumScalars: release.budget.maximumScalarCountPerCell)
                return formulaSafe(value)
            }
            lines.append(values.map {
                escape($0, delimiter: release.delimiter.scalar)
            }.joined(separator: String(release.delimiter.scalar)))
        }
        let data = Data(lines.joined(separator: "\n").appending("\n").utf8)
        guard UInt64(data.count) <= release.budget.maximumByteCount else {
            throw IncumbentFileContractFailureV1.budgetExceeded
        }
        // Keep the inherited safety parser as a second, independent formula
        // and control check.  The apostrophe added by formulaSafe is intentional.
        try IncumbentDelimitedTextSafetyV1.validateRenderedBytes(
            data,
            release: release,
            expectedDataRows: rows.count
        )
        return data
    }

    private static func validateInboundText(_ value: String, maximumScalars: Int) throws {
        guard value.precomposedStringWithCanonicalMapping == value,
              value.unicodeScalars.count <= maximumScalars,
              value.unicodeScalars.allSatisfy({ scalar in
                  scalar.value >= 0x20 || scalar.value == 0x09
                      || scalar.value == 0x0a || scalar.value == 0x0d
              }),
              !value.unicodeScalars.contains(where: {
                  [0x202a, 0x202b, 0x202c, 0x202d, 0x202e,
                   0x2066, 0x2067, 0x2068, 0x2069].contains($0.value)
              }) else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
    }

    private static func formulaSafe(_ value: String) -> String {
        let trimmed = value.drop(while: { $0.isWhitespace })
        guard let first = trimmed.first, "=+-@".contains(first) else {
            return value
        }
        return "'" + value
    }

    private static func escape(_ value: String, delimiter: UnicodeScalar) -> String {
        guard value.contains(where: {
            $0 == Character(String(delimiter)) || $0 == "\"" || $0 == "\n" || $0 == "\r"
        }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func parse(_ text: String, delimiter: UnicodeScalar) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var justClosedQuote = false
        var index = text.startIndex

        func finishField() {
            row.append(field.precomposedStringWithCanonicalMapping)
            field.removeAll(keepingCapacity: true)
        }

        func finishRow() {
            finishField()
            rows.append(row)
            row.removeAll(keepingCapacity: true)
        }

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if quoted {
                if character == "\"" {
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                    } else {
                        quoted = false
                        justClosedQuote = true
                        index = next
                    }
                } else {
                    field.append(character)
                    index = next
                }
                continue
            }

            if justClosedQuote {
                if character.unicodeScalars.count == 1,
                   character.unicodeScalars.first == delimiter {
                    finishField()
                    justClosedQuote = false
                    index = next
                    continue
                }
                if character == "\n" {
                    finishRow()
                    justClosedQuote = false
                    index = next
                    continue
                }
                if character == "\r" {
                    guard next < text.endIndex, text[next] == "\n" else {
                        throw IncumbentFileContractFailureV1.headerMismatch
                    }
                    finishRow()
                    justClosedQuote = false
                    index = text.index(after: next)
                    continue
                }
                throw IncumbentFileContractFailureV1.headerMismatch
            }

            if character == "\"" {
                guard field.isEmpty else {
                    throw IncumbentFileContractFailureV1.headerMismatch
                }
                quoted = true
                index = next
                continue
            }
            if character.unicodeScalars.count == 1,
               character.unicodeScalars.first == delimiter {
                finishField()
                index = next
                continue
            }
            if character == "\n" {
                finishRow()
                index = next
                continue
            }
            if character == "\r" {
                guard next < text.endIndex, text[next] == "\n" else {
                    throw IncumbentFileContractFailureV1.headerMismatch
                }
                finishRow()
                index = text.index(after: next)
                continue
            }
            field.append(character)
            index = next
        }

        guard !quoted, !justClosedQuote else {
            throw IncumbentFileContractFailureV1.headerMismatch
        }
        // A final line ending has already finished its row.  Do not invent a
        // second empty data row, but preserve an explicit empty field/row.
        if !field.isEmpty || !row.isEmpty {
            finishRow()
        }
        return rows
    }
}

struct IncumbentDelimitedTextAdapterV1: IncumbentFileAdapterV1, Sendable {
    let release: IncumbentFileProfileReleaseV1

    init(release: IncumbentFileProfileReleaseV1) throws {
        try release.validate()
        self.release = release
    }

    func detect(_ input: IncumbentFileInputV1) throws -> IncumbentFileDetectionV1 {
        try IncumbentDelimitedTextCodecV1.decode(input: input, release: release).detection
    }

    func parse(
        _ input: IncumbentFileInputV1,
        detection: IncumbentFileDetectionV1
    ) throws -> [IncumbentFileRowV1] {
        try detection.validate(input: input, release: release)
        let decoded = try IncumbentDelimitedTextCodecV1.decode(input: input, release: release)
        guard decoded.detection == detection else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
        return decoded.rows
    }

    func render(rows: [IncumbentFileRowV1], scope: IncumbentExchangeScopeV1) throws -> Data {
        try IncumbentDelimitedTextCodecV1.encode(rows: rows, scope: scope, release: release)
    }
}

struct IncumbentFileExchangeScratchLeaseV1: Equatable, Sendable {
    let operationID: UUID
    let scopeSHA256: String
    let releaseSHA256: String
    let inputSHA256: String
    let exportManifestSHA256: String?
    let requestedByteCount: UInt64
    let lease: ScratchDataLeaseV1

    var isImportBinding: Bool {
        lease.request.purpose == .importData && lease.request.owner == .importData
    }

    var isExportBinding: Bool {
        lease.request.purpose == .supportExport && lease.request.owner == .supportExport
    }

    init(
        request: ScratchDataLeaseRequestV1,
        input: IncumbentFileInputV1,
        scope: IncumbentExchangeScopeV1,
        lease: ScratchDataLeaseV1
    ) throws {
        try IncumbentFileContractV1.requireID(request.ownerOperationID)
        try IncumbentFileContractV1.requireDigest(input.byteSHA256)
        try IncumbentFileContractV1.requireDigest(scope.scopeSHA256)
        try IncumbentFileContractV1.requireDigest(scope.releaseSHA256)
        guard request.ownerOperationID == scope.operationID,
              request.purpose == .importData,
              request.owner == .importData,
              request.requestedByteCount == UInt64(input.bytes.count),
              request.backupPolicy == .excluded,
              lease.request == request else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        operationID = request.ownerOperationID
        scopeSHA256 = scope.scopeSHA256
        releaseSHA256 = scope.releaseSHA256
        inputSHA256 = input.byteSHA256
        exportManifestSHA256 = nil
        requestedByteCount = request.requestedByteCount
        self.lease = lease
    }

    init(
        request: ScratchDataLeaseRequestV1,
        output: Data,
        scope: IncumbentExchangeScopeV1,
        release: IncumbentFileProfileReleaseV1,
        manifest: IncumbentFileExportManifestV1,
        lease: ScratchDataLeaseV1
    ) throws {
        try release.validate()
        try scope.validate(release: release)
        try manifest.validate(scope: scope, release: release, output: output)
        try IncumbentDelimitedTextSafetyV1.validateRenderedBytes(
            output,
            release: release,
            expectedDataRows: manifest.rowCount
        )
        try IncumbentFileContractV1.requireID(request.ownerOperationID)
        let outputSHA256 = CanonicalJSONV1.sha256(output)
        try IncumbentFileContractV1.requireDigest(outputSHA256)
        try IncumbentFileContractV1.requireDigest(scope.scopeSHA256)
        try IncumbentFileContractV1.requireDigest(scope.releaseSHA256)
        guard !output.isEmpty,
              request.ownerOperationID == scope.operationID,
              request.purpose == .supportExport,
              request.owner == .supportExport,
              request.requestedByteCount == UInt64(output.count),
              request.backupPolicy == .excluded,
              lease.request == request else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        operationID = request.ownerOperationID
        scopeSHA256 = scope.scopeSHA256
        releaseSHA256 = scope.releaseSHA256
        inputSHA256 = outputSHA256
        exportManifestSHA256 = manifest.manifestSHA256
        requestedByteCount = request.requestedByteCount
        self.lease = lease
    }
}

struct IncumbentFileExchangeScratchLifecycleReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let operationID: UUID
    let scopeSHA256: String
    let releaseSHA256: String
    let inputSHA256: String
    let leaseID: UUID
    let exportManifestSHA256: String?
    let scratchPurpose: ScratchDataPurposeV1
    let scratchOwner: ScratchDataOwnerV1
    let outcome: IncumbentExchangeOutcomeV1
    let externalAvailability: IncumbentExternalAvailabilityV1
    let canonicalEffectOccurred: Bool
    let scratchDeleted: Bool
    let scratchTerminal: ScratchDataLeaseTerminalV1
    let occurredAt: Date
    let receiptSHA256: String

    init(
        binding: IncumbentFileExchangeScratchLeaseV1,
        outcome: IncumbentExchangeOutcomeV1,
        externalAvailability: IncumbentExternalAvailabilityV1,
        scratchTerminal: ScratchDataLeaseTerminalV1,
        occurredAt: Date
    ) throws {
        try IncumbentFileContractV1.requireID(binding.operationID)
        try IncumbentFileContractV1.requireDigest(binding.scopeSHA256)
        try IncumbentFileContractV1.requireDigest(binding.releaseSHA256)
        try IncumbentFileContractV1.requireDigest(binding.inputSHA256)
        if let exportManifestSHA256 = binding.exportManifestSHA256 {
            try IncumbentFileContractV1.requireDigest(exportManifestSHA256)
        }
        let expectedTerminal = Self.expectedScratchTerminal(
            outcome: outcome,
            externalAvailability: externalAvailability
        )
        let ownershipMatchesOutcome: Bool
        switch outcome {
        case .previewedZeroWrite, .importedCanonical:
            ownershipMatchesOutcome = binding.isImportBinding
        case .exportedLocalFile, .exportAvailabilityUnknown:
            ownershipMatchesOutcome = binding.isExportBinding
        case .cancelled, .quarantined, .failedNoEffect:
            ownershipMatchesOutcome = binding.isImportBinding || binding.isExportBinding
        }
        let manifestBindingMatchesOutcome: Bool
        switch outcome {
        case .previewedZeroWrite, .importedCanonical:
            manifestBindingMatchesOutcome = binding.exportManifestSHA256 == nil
        case .exportedLocalFile, .exportAvailabilityUnknown:
            manifestBindingMatchesOutcome = binding.exportManifestSHA256 != nil
        case .cancelled, .quarantined, .failedNoEffect:
            manifestBindingMatchesOutcome = binding.isExportBinding == (binding.exportManifestSHA256 != nil)
        }
        guard binding.lease.request.ownerOperationID == binding.operationID,
              ownershipMatchesOutcome,
              manifestBindingMatchesOutcome,
              binding.lease.request.backupPolicy == .excluded,
              scratchTerminal == expectedTerminal,
              Self.externalAvailabilityMatches(
                  outcome: outcome,
                  externalAvailability: externalAvailability
              ),
              occurredAt.timeIntervalSinceReferenceDate.isFinite,
              outcome != .exportedLocalFile || externalAvailability == .fileCreatedLocally else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        operationID = binding.operationID
        scopeSHA256 = binding.scopeSHA256
        releaseSHA256 = binding.releaseSHA256
        inputSHA256 = binding.inputSHA256
        leaseID = binding.lease.request.leaseID
        exportManifestSHA256 = binding.exportManifestSHA256
        scratchPurpose = binding.lease.request.purpose
        scratchOwner = binding.lease.request.owner
        self.outcome = outcome
        self.externalAvailability = externalAvailability
        canonicalEffectOccurred = outcome == .importedCanonical
        scratchDeleted = true
        self.scratchTerminal = scratchTerminal
        self.occurredAt = occurredAt
        receiptSHA256 = try IncumbentFileContractV1.digest(Basis(
            schemaVersion: Self.schemaVersion,
            operationID: operationID,
            scopeSHA256: scopeSHA256,
            releaseSHA256: releaseSHA256,
            inputSHA256: inputSHA256,
            leaseID: leaseID,
            exportManifestSHA256: exportManifestSHA256,
            scratchPurpose: scratchPurpose,
            scratchOwner: scratchOwner,
            outcome: outcome,
            externalAvailability: externalAvailability,
            canonicalEffectOccurred: canonicalEffectOccurred,
            scratchDeleted: true,
            scratchTerminal: scratchTerminal,
            occurredAt: occurredAt
        ))
    }

    func validate() throws {
        try IncumbentFileContractV1.requireID(operationID)
        try IncumbentFileContractV1.requireID(leaseID)
        try IncumbentFileContractV1.requireDigest(scopeSHA256)
        try IncumbentFileContractV1.requireDigest(releaseSHA256)
        try IncumbentFileContractV1.requireDigest(inputSHA256)
        if let exportManifestSHA256 {
            try IncumbentFileContractV1.requireDigest(exportManifestSHA256)
        }
        let expectedTerminal = Self.expectedScratchTerminal(
            outcome: outcome,
            externalAvailability: externalAvailability
        )
        let ownershipMatchesOutcome: Bool
        switch outcome {
        case .previewedZeroWrite, .importedCanonical:
            ownershipMatchesOutcome = scratchPurpose == .importData && scratchOwner == .importData
        case .exportedLocalFile, .exportAvailabilityUnknown:
            ownershipMatchesOutcome = scratchPurpose == .supportExport && scratchOwner == .supportExport
        case .cancelled, .quarantined, .failedNoEffect:
            ownershipMatchesOutcome = (scratchPurpose == .importData && scratchOwner == .importData)
                || (scratchPurpose == .supportExport && scratchOwner == .supportExport)
        }
        let manifestBindingMatchesOutcome: Bool
        switch outcome {
        case .previewedZeroWrite, .importedCanonical:
            manifestBindingMatchesOutcome = exportManifestSHA256 == nil
        case .exportedLocalFile, .exportAvailabilityUnknown:
            manifestBindingMatchesOutcome = exportManifestSHA256 != nil
        case .cancelled, .quarantined, .failedNoEffect:
            manifestBindingMatchesOutcome = (scratchPurpose == .supportExport
                && scratchOwner == .supportExport) == (exportManifestSHA256 != nil)
        }
        let expectedReceiptSHA256 = try IncumbentFileContractV1.digest(Basis(
            schemaVersion: Self.schemaVersion,
            operationID: operationID,
            scopeSHA256: scopeSHA256,
            releaseSHA256: releaseSHA256,
            inputSHA256: inputSHA256,
            leaseID: leaseID,
            exportManifestSHA256: exportManifestSHA256,
            scratchPurpose: scratchPurpose,
            scratchOwner: scratchOwner,
            outcome: outcome,
            externalAvailability: externalAvailability,
            canonicalEffectOccurred: canonicalEffectOccurred,
            scratchDeleted: scratchDeleted,
            scratchTerminal: scratchTerminal,
            occurredAt: occurredAt
        ))
        guard schemaVersion == Self.schemaVersion,
              scratchTerminal == expectedTerminal,
              ownershipMatchesOutcome,
              manifestBindingMatchesOutcome,
              Self.externalAvailabilityMatches(
                  outcome: outcome,
                  externalAvailability: externalAvailability
              ),
              canonicalEffectOccurred == (outcome == .importedCanonical),
              scratchDeleted,
              occurredAt.timeIntervalSinceReferenceDate.isFinite,
              outcome != .exportedLocalFile || externalAvailability == .fileCreatedLocally,
              receiptSHA256 == expectedReceiptSHA256 else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
    }

    private static func expectedScratchTerminal(
        outcome: IncumbentExchangeOutcomeV1,
        externalAvailability: IncumbentExternalAvailabilityV1
    ) -> ScratchDataLeaseTerminalV1 {
        switch outcome {
        case .cancelled:
            return .cancelled
        case .exportAvailabilityUnknown:
            return .failed
        case .previewedZeroWrite, .exportedLocalFile, .importedCanonical:
            return .completed
        case .quarantined, .failedNoEffect:
            return .failed
        }
    }

    private static func externalAvailabilityMatches(
        outcome: IncumbentExchangeOutcomeV1,
        externalAvailability: IncumbentExternalAvailabilityV1
    ) -> Bool {
        switch outcome {
        case .cancelled:
            return externalAvailability == .notAttempted
        case .exportedLocalFile:
            return externalAvailability == .fileCreatedLocally
        case .exportAvailabilityUnknown:
            return externalAvailability == .unknownAfterCallbackLoss
        case .previewedZeroWrite, .quarantined, .failedNoEffect, .importedCanonical:
            return externalAvailability == .notAttempted
        }
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let operationID: UUID
        let scopeSHA256: String
        let releaseSHA256: String
        let inputSHA256: String
        let leaseID: UUID
        let exportManifestSHA256: String?
        let scratchPurpose: ScratchDataPurposeV1
        let scratchOwner: ScratchDataOwnerV1
        let outcome: IncumbentExchangeOutcomeV1
        let externalAvailability: IncumbentExternalAvailabilityV1
        let canonicalEffectOccurred: Bool
        let scratchDeleted: Bool
        let scratchTerminal: ScratchDataLeaseTerminalV1
        let occurredAt: Date
    }

}

struct IncumbentFileExchangeQuarantineLifecycleResultV1: Codable, Equatable, Sendable {
    let quarantine: IncumbentFileQuarantineReceiptV1
    let lifecycle: IncumbentFileExchangeScratchLifecycleReceiptV1
}

enum IncumbentFileExchangeExternalAvailabilityBoundaryV1 {
    static let unknownAfterCallbackLossCode = "EXTERNAL_AVAILABILITY_UNKNOWN"

    static func resolve(
        userCancelled: Bool,
        callbackConfirmedLocalFile: Bool
    ) -> IncumbentExternalAvailabilityV1 {
        if userCancelled { return .notAttempted }
        return callbackConfirmedLocalFile ? .fileCreatedLocally : .unknownAfterCallbackLoss
    }
}

/// Real source lifecycle owner. It uses the shared noncanonical scratch-data
/// authority and never owns a canonical writer, persistent profile, report, or
/// search record.  Every terminal path calls cleanup through `finish`.
actor IncumbentFileExchangeLifecycleAdapterV1 {
    private struct ActiveLease: Sendable {
        let binding: IncumbentFileExchangeScratchLeaseV1
    }

    static let maximumActiveOperationCount = 128
    private let scratch: any ScratchDataLeasePortV1
    private var active: [UUID: ActiveLease] = [:]
    private var terminals: [UUID: IncumbentFileExchangeScratchLifecycleReceiptV1] = [:]
    private var terminalOrder: [UUID] = []

    init(scratch: any ScratchDataLeasePortV1) {
        self.scratch = scratch
    }

    private static func validateExportArtifact(
        output: Data,
        manifest: IncumbentFileExportManifestV1,
        release: IncumbentFileProfileReleaseV1,
        scope: IncumbentExchangeScopeV1
    ) throws {
        try release.validate()
        try scope.validate(release: release)
        try manifest.validate(scope: scope, release: release, output: output)
        try IncumbentDelimitedTextSafetyV1.validateRenderedBytes(
            output,
            release: release,
            expectedDataRows: manifest.rowCount
        )
        guard !output.isEmpty,
              manifest.operationID == scope.operationID,
              manifest.scopeSHA256 == scope.scopeSHA256,
              manifest.releaseSHA256 == release.releaseSHA256,
              manifest.outputSHA256 == CanonicalJSONV1.sha256(output),
              manifest.outputByteCount == UInt64(output.count) else {
            throw IncumbentFileContractFailureV1.invalidDigest
        }
    }

    func acquire(
        input: IncumbentFileInputV1,
        scope: IncumbentExchangeScopeV1,
        createdAt: Date,
        expiresAt: Date,
        leaseID: UUID = UUID()
    ) async throws -> IncumbentFileExchangeScratchLeaseV1 {
        try IncumbentFileContractV1.requireID(scope.operationID)
        try IncumbentFileContractV1.requireDigest(scope.scopeSHA256)
        guard scope.direction.permitsImport,
              active[scope.operationID] == nil,
              terminals[scope.operationID] == nil,
              active.count < Self.maximumActiveOperationCount else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        let request = try ScratchDataLeaseRequestV1(
            leaseID: leaseID,
            purpose: .importData,
            owner: .importData,
            ownerOperationID: scope.operationID,
            requestedByteCount: max(1, UInt64(input.bytes.count)),
            createdAt: createdAt,
            expiresAt: expiresAt
        )
        do {
            let lease = try await scratch.acquireScratchLease(request)
            guard lease.request == request else {
                try await scratch.releaseScratchLease(lease, terminal: .failed)
                throw IncumbentFileContractFailureV1.invalidValue
            }
            let binding = try IncumbentFileExchangeScratchLeaseV1(
                request: request,
                input: input,
                scope: scope,
                lease: lease
            )
            active[scope.operationID] = ActiveLease(binding: binding)
            return binding
        } catch {
            // If acquire failed before a lease existed there is nothing to
            // delete.  The port owns any partial cleanup in that case.
            throw error
        }
    }

    func acquireExport(
        output: Data,
        manifest: IncumbentFileExportManifestV1,
        release: IncumbentFileProfileReleaseV1,
        scope: IncumbentExchangeScopeV1,
        createdAt: Date,
        expiresAt: Date,
        leaseID: UUID = UUID()
    ) async throws -> IncumbentFileExchangeScratchLeaseV1 {
        try Self.validateExportArtifact(
            output: output,
            manifest: manifest,
            release: release,
            scope: scope
        )
        try IncumbentFileContractV1.requireID(scope.operationID)
        try IncumbentFileContractV1.requireDigest(scope.scopeSHA256)
        guard scope.direction.permitsExport,
              !output.isEmpty,
              UInt64(output.count) <= ScratchDataPurposeV1.supportExport.maximumByteCount,
              active[scope.operationID] == nil,
              terminals[scope.operationID] == nil,
              active.count < Self.maximumActiveOperationCount else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        let request = try ScratchDataLeaseRequestV1(
            leaseID: leaseID,
            purpose: .supportExport,
            owner: .supportExport,
            ownerOperationID: scope.operationID,
            requestedByteCount: UInt64(output.count),
            createdAt: createdAt,
            expiresAt: expiresAt
        )
        let lease = try await scratch.acquireScratchLease(request)
        guard lease.request == request else {
            try await scratch.releaseScratchLease(lease, terminal: .failed)
            throw IncumbentFileContractFailureV1.invalidValue
        }
        let binding = try IncumbentFileExchangeScratchLeaseV1(
            request: request,
            output: output,
            scope: scope,
            release: release,
            manifest: manifest,
            lease: lease
        )
        active[scope.operationID] = ActiveLease(binding: binding)
        return binding
    }

    func stage(
        input: IncumbentFileInputV1,
        binding: IncumbentFileExchangeScratchLeaseV1
    ) async throws -> URL {
        guard let current = active[binding.operationID], current.binding == binding else {
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
        guard input.byteSHA256 == binding.inputSHA256 else {
            _ = try await quarantine(
                binding: binding,
                reason: .sourceChanged,
                at: Date()
            )
            throw IncumbentFileContractFailureV1.invalidDigest
        }
        do {
            // The name is fixed and path-free.  The lease directory is the
            // operation-scoped security scope; no external path is retained.
            return try await scratch.writeScratchData(
                input.bytes,
                named: "source.dat",
                lease: binding.lease
            )
        } catch let stagingError {
            _ = try await finish(
                binding: binding,
                outcome: .failedNoEffect,
                externalAvailability: .notAttempted,
                occurredAt: Date()
            )
            throw stagingError
        }
    }

    func stageExport(
        output: Data,
        manifest: IncumbentFileExportManifestV1,
        release: IncumbentFileProfileReleaseV1,
        scope: IncumbentExchangeScopeV1,
        binding: IncumbentFileExchangeScratchLeaseV1
    ) async throws -> URL {
        try Self.validateExportArtifact(
            output: output,
            manifest: manifest,
            release: release,
            scope: scope
        )
        guard let current = active[binding.operationID], current.binding == binding,
              binding.isExportBinding,
              binding.operationID == scope.operationID,
              binding.scopeSHA256 == scope.scopeSHA256,
              binding.releaseSHA256 == release.releaseSHA256,
              binding.releaseSHA256 == manifest.releaseSHA256,
              binding.inputSHA256 == manifest.outputSHA256,
              binding.exportManifestSHA256 == manifest.manifestSHA256 else {
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
        do {
            return try await scratch.writeScratchData(
                output,
                named: "export.dat",
                lease: binding.lease
            )
        } catch let stagingError {
            _ = try await finish(
                binding: binding,
                outcome: .failedNoEffect,
                externalAvailability: .notAttempted,
                occurredAt: Date()
            )
            throw stagingError
        }
    }

    func preview(
        input: IncumbentFileInputV1,
        scope: IncumbentExchangeScopeV1,
        coordinator: IncumbentFileExchangeCoordinatorV1,
        at date: Date,
        createdAt: Date,
        expiresAt: Date,
        leaseID: UUID = UUID()
    ) async throws -> (
        rows: [IncumbentFileRowV1],
        preview: IncumbentMappingPreviewV1,
        lifecycle: IncumbentFileExchangeScratchLifecycleReceiptV1
    ) {
        let binding = try await acquire(
            input: input,
            scope: scope,
            createdAt: createdAt,
            expiresAt: expiresAt,
            leaseID: leaseID
        )
        do {
            _ = try await stage(input: input, binding: binding)
            let result = try coordinator.preview(input: input, scope: scope, at: date)
            let lifecycle = try await finish(
                binding: binding,
                outcome: .previewedZeroWrite,
                externalAvailability: .notAttempted,
                occurredAt: date
            )
            return (result.rows, result.preview, lifecycle)
        } catch let previewError {
            if active[binding.operationID] != nil {
                _ = try await quarantine(
                    binding: binding,
                    reason: Self.quarantineReason(for: previewError),
                    at: date
                )
            }
            throw previewError
        }
    }

    func finish(
        binding: IncumbentFileExchangeScratchLeaseV1,
        outcome: IncumbentExchangeOutcomeV1,
        externalAvailability: IncumbentExternalAvailabilityV1,
        occurredAt: Date
    ) async throws -> IncumbentFileExchangeScratchLifecycleReceiptV1 {
        try await finishValidated(
            binding: binding,
            outcome: outcome,
            externalAvailability: externalAvailability,
            occurredAt: occurredAt,
            allowExportOutcome: false,
            expectedExportManifestSHA256: binding.exportManifestSHA256
        )
    }

    private func finishValidated(
        binding: IncumbentFileExchangeScratchLeaseV1,
        outcome: IncumbentExchangeOutcomeV1,
        externalAvailability: IncumbentExternalAvailabilityV1,
        occurredAt: Date,
        allowExportOutcome: Bool,
        expectedExportManifestSHA256: String?
    ) async throws -> IncumbentFileExchangeScratchLifecycleReceiptV1 {
        guard allowExportOutcome || (outcome != .exportedLocalFile
            && outcome != .exportAvailabilityUnknown) else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        if let terminal = terminals[binding.operationID] {
            guard terminal.leaseID == binding.lease.request.leaseID,
                  terminal.scopeSHA256 == binding.scopeSHA256,
                  terminal.releaseSHA256 == binding.releaseSHA256,
                  terminal.inputSHA256 == binding.inputSHA256,
                  terminal.exportManifestSHA256 == binding.exportManifestSHA256,
                  terminal.scratchPurpose == binding.lease.request.purpose,
                  terminal.scratchOwner == binding.lease.request.owner,
                  terminal.outcome == outcome,
                  terminal.externalAvailability == externalAvailability,
                  terminal.exportManifestSHA256 == expectedExportManifestSHA256 else {
                throw IncumbentFileContractFailureV1.divergentRecovery
            }
            return terminal
        }
        guard active[binding.operationID]?.binding == binding,
              Self.ownershipMatchesOutcome(binding: binding, outcome: outcome),
              occurredAt.timeIntervalSinceReferenceDate.isFinite,
              Self.externalAvailabilityMatches(
                  outcome: outcome,
                  externalAvailability: externalAvailability
              ) else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        let scratchTerminal = Self.scratchTerminal(for: outcome)
        try await scratch.releaseScratchLease(
            binding.lease,
            terminal: scratchTerminal
        )
        let receipt = try IncumbentFileExchangeScratchLifecycleReceiptV1(
            binding: binding,
            outcome: outcome,
            externalAvailability: externalAvailability,
            scratchTerminal: scratchTerminal,
            occurredAt: occurredAt
        )
        active.removeValue(forKey: binding.operationID)
        terminals[binding.operationID] = receipt
        terminalOrder.append(binding.operationID)
        if terminalOrder.count > Self.maximumActiveOperationCount {
            let evicted = terminalOrder.removeFirst()
            terminals.removeValue(forKey: evicted)
        }
        return receipt
    }

    func quarantine(
        binding: IncumbentFileExchangeScratchLeaseV1,
        reason: IncumbentQuarantineReasonV1,
        at date: Date
    ) async throws -> IncumbentFileExchangeQuarantineLifecycleResultV1 {
        let quarantine = try IncumbentFileQuarantineReceiptV1(
            operationID: binding.operationID,
            inputSHA256: binding.inputSHA256,
            releaseSHA256: binding.releaseSHA256,
            reason: reason,
            quarantinedAt: date
        )
        let lifecycle = try await finish(
            binding: binding,
            outcome: .quarantined,
            externalAvailability: .notAttempted,
            occurredAt: date
        )
        return IncumbentFileExchangeQuarantineLifecycleResultV1(
            quarantine: quarantine,
            lifecycle: lifecycle
        )
    }

    func cancel(
        binding: IncumbentFileExchangeScratchLeaseV1,
        at date: Date
    ) async throws -> IncumbentFileExchangeScratchLifecycleReceiptV1 {
        try await finish(
            binding: binding,
            outcome: .cancelled,
            externalAvailability: .notAttempted,
            occurredAt: date
        )
    }

    func finishExport(
        binding: IncumbentFileExchangeScratchLeaseV1,
        output: Data,
        manifest: IncumbentFileExportManifestV1,
        release: IncumbentFileProfileReleaseV1,
        scope: IncumbentExchangeScopeV1,
        userCancelled: Bool,
        callbackConfirmedLocalFile: Bool,
        at date: Date
    ) async throws -> IncumbentFileExchangeScratchLifecycleReceiptV1 {
        try Self.validateExportArtifact(
            output: output,
            manifest: manifest,
            release: release,
            scope: scope
        )
        guard binding.isExportBinding,
              binding.operationID == scope.operationID,
              binding.scopeSHA256 == scope.scopeSHA256,
              binding.releaseSHA256 == release.releaseSHA256,
              binding.releaseSHA256 == manifest.releaseSHA256,
              binding.inputSHA256 == manifest.outputSHA256,
              binding.exportManifestSHA256 == manifest.manifestSHA256 else {
            throw IncumbentFileContractFailureV1.invalidValue
        }
        let availability = IncumbentFileExchangeExternalAvailabilityBoundaryV1.resolve(
            userCancelled: userCancelled,
            callbackConfirmedLocalFile: callbackConfirmedLocalFile
        )
        let outcome: IncumbentExchangeOutcomeV1
        if userCancelled {
            outcome = .cancelled
        } else if availability == .fileCreatedLocally {
            outcome = .exportedLocalFile
        } else if availability == .unknownAfterCallbackLoss {
            outcome = .exportAvailabilityUnknown
        } else {
            outcome = .failedNoEffect
        }
        return try await finishValidated(
            binding: binding,
            outcome: outcome,
            externalAvailability: availability,
            occurredAt: date,
            allowExportOutcome: true,
            expectedExportManifestSHA256: manifest.manifestSHA256
        )
    }

    /// Reconciles a lease that is still owned by this actor.  This is an
    /// in-process path only; a cold start must use `recoverColdStart` and may
    /// not reconstruct a lease binding from caller-supplied bytes.
    func recoverInProcess(
        binding: IncumbentFileExchangeScratchLeaseV1,
        coordinator: IncumbentFileExchangeCoordinatorV1,
        plan: IncumbentExchangeRecoveryPlanV1,
        observedSourceSHA256: String,
        canonicalReceipt: MutationReceiptV1?,
        at date: Date
    ) async throws -> (
        recovery: IncumbentExchangeRecoveryReceiptV1,
        lifecycle: IncumbentFileExchangeScratchLifecycleReceiptV1?
    ) {
        try plan.validate()
        try IncumbentFileContractV1.requireDigest(observedSourceSHA256)
        let canonicalMutation = try canonicalReceipt.map {
            try C50IncumbentMutationReceiptBoundaryV1.reference($0, plan: plan)
        }
        guard binding.isImportBinding else {
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
        guard let current = active[binding.operationID],
              current.binding == binding else {
            // Same-process recovery rehydrates only ephemeral cleanup; it
            // never restores a binding after relaunch.
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
        guard plan.operationID == binding.operationID,
              plan.scopeSHA256 == binding.scopeSHA256,
              plan.sourceSHA256 == binding.inputSHA256 else {
            let quarantine = try await quarantine(
                binding: binding,
                reason: .divergentRecovery,
                at: date
            )
            let recovery = try coordinator.recover(
                plan: plan,
                observedSourceSHA256: observedSourceSHA256,
                canonicalMutation: canonicalMutation,
                cleanup: nil
            )
            return (recovery, quarantine.lifecycle)
        }
        let recovery = try coordinator.recover(
            plan: plan,
            observedSourceSHA256: observedSourceSHA256,
            canonicalMutation: canonicalMutation,
            cleanup: nil
        )
        guard recovery.canonicalReapplyOccurred == false,
              recovery.disposition != .cleanupOnly else {
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
        guard canonicalMutation != nil else {
            if recovery.disposition == .divergentQuarantined {
                let quarantine = try await quarantine(
                    binding: binding,
                    reason: .divergentRecovery,
                    at: date
                )
                return (recovery, quarantine.lifecycle)
            }
            guard recovery.disposition == .beforeCanonicalEffect else {
                throw IncumbentFileContractFailureV1.divergentRecovery
            }
            return (recovery, try await finish(
                binding: binding,
                outcome: .failedNoEffect,
                externalAvailability: .notAttempted,
                occurredAt: date
            ))
        }
        guard recovery.disposition == .appliedMatchingReceipt else {
            let quarantine = try await quarantine(
                binding: binding,
                reason: .divergentRecovery,
                at: date
            )
            return (recovery, quarantine.lifecycle)
        }
        let lifecycle = try await finish(
            binding: binding,
            outcome: .importedCanonical,
            externalAvailability: .notAttempted,
            occurredAt: date
        )
        let cleanup = try IncumbentCleanupEvidenceV1(
            operationID: plan.operationID,
            sourceSHA256: plan.sourceSHA256,
            cleanupIdentitySHA256: plan.cleanupIdentitySHA256,
            cleanedAt: date
        )
        let completedRecovery = try coordinator.recover(
            plan: plan,
            observedSourceSHA256: observedSourceSHA256,
            canonicalMutation: canonicalMutation,
            cleanup: cleanup
        )
        guard completedRecovery.disposition == .cleanupOnly,
              completedRecovery.canonicalReapplyOccurred == false else {
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
        return (completedRecovery, lifecycle)
    }

    /// Performs nonpersistent cold-start reconciliation from the durable
    /// recovery authority and the aggregate scratch authority only.  A
    /// cold-start path deliberately has no lease binding and creates no
    /// per-lease lifecycle receipt.
    func recoverColdStart(
        coordinator: IncumbentFileExchangeCoordinatorV1,
        plan: IncumbentExchangeRecoveryPlanV1,
        observedSourceSHA256: String,
        canonicalReceipt: MutationReceiptV1?
    ) async throws -> (
        recovery: IncumbentExchangeRecoveryReceiptV1,
        scratchRecovery: ScratchDataLeaseRecoverySummaryV1
    ) {
        let scratchRecovery = try await scratch.recoverScratchLeases()
        active.removeAll()
        terminals.removeAll()
        terminalOrder.removeAll()
        try plan.validate()
        try IncumbentFileContractV1.requireDigest(observedSourceSHA256)
        let canonicalMutation = try canonicalReceipt.map {
            try C50IncumbentMutationReceiptBoundaryV1.reference($0, plan: plan)
        }
        let recovery = try coordinator.recover(
            plan: plan,
            observedSourceSHA256: observedSourceSHA256,
            canonicalMutation: canonicalMutation,
            cleanup: nil
        )
        guard recovery.canonicalReapplyOccurred == false else {
            throw IncumbentFileContractFailureV1.divergentRecovery
        }
        return (recovery, scratchRecovery)
    }

    func invalidateForPlanChange(
        binding: IncumbentFileExchangeScratchLeaseV1,
        plan: IncumbentExchangeRecoveryPlanV1,
        at date: Date
    ) async throws -> IncumbentFileExchangeQuarantineLifecycleResultV1 {
        try plan.validate()
        guard plan.operationID == binding.operationID,
              plan.scopeSHA256 == binding.scopeSHA256,
              plan.sourceSHA256 == binding.inputSHA256 else {
            return try await quarantine(binding: binding, reason: .divergentRecovery, at: date)
        }
        throw IncumbentFileContractFailureV1.invalidValue
    }

    func recoverAfterInterruption() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        let summary = try await scratch.recoverScratchLeases()
        active.removeAll()
        return summary
    }

    private static func scratchTerminal(
        for outcome: IncumbentExchangeOutcomeV1
    ) -> ScratchDataLeaseTerminalV1 {
        switch outcome {
        case .cancelled: return .cancelled
        case .exportAvailabilityUnknown, .failedNoEffect: return .failed
        case .previewedZeroWrite, .exportedLocalFile, .importedCanonical: return .completed
        case .quarantined: return .failed
        }
    }

    private static func ownershipMatchesOutcome(
        binding: IncumbentFileExchangeScratchLeaseV1,
        outcome: IncumbentExchangeOutcomeV1
    ) -> Bool {
        switch outcome {
        case .previewedZeroWrite, .importedCanonical:
            return binding.isImportBinding
        case .exportedLocalFile, .exportAvailabilityUnknown:
            return binding.isExportBinding
        case .cancelled, .quarantined, .failedNoEffect:
            return binding.isImportBinding || binding.isExportBinding
        }
    }

    private static func externalAvailabilityMatches(
        outcome: IncumbentExchangeOutcomeV1,
        externalAvailability: IncumbentExternalAvailabilityV1
    ) -> Bool {
        switch outcome {
        case .cancelled:
            return externalAvailability == .notAttempted
        case .exportedLocalFile:
            return externalAvailability == .fileCreatedLocally
        case .exportAvailabilityUnknown:
            return externalAvailability == .unknownAfterCallbackLoss
        case .previewedZeroWrite, .quarantined, .failedNoEffect, .importedCanonical:
            return externalAvailability == .notAttempted
        }
    }

    private static func quarantineReason(for error: Error) -> IncumbentQuarantineReasonV1 {
        guard let failure = error as? IncumbentFileContractFailureV1 else {
            return .sourceChanged
        }
        switch failure {
        case .unsupportedVersion:
            return .unsupportedVersion
        case .headerMismatch:
            return .headerMismatch
        case .budgetExceeded:
            return .budgetExceeded
        case .privacyApprovalRequired, .fieldNotAllowed:
            return .privacyViolation
        case .quarantined, .divergentRecovery, .staleSelection:
            return .divergentRecovery
        case .invalidDigest:
            return .sourceChanged
        case .invalidValue, .noSelectedProfile, .multipleSelectedProfiles:
            return .encodingRejected
        }
    }
}

/// Cross-surface C50 disclosure boundary.  These constants are consumed by
/// reporting, search, diagnostics, and localization lanes; no lane may turn
/// scratch input into report truth or a durable search record.
enum C50IncumbentFileExchangeLifecycleBoundaryV1 {
    static let profileContractSchemaVersion = IncumbentFileProfileReleaseV1.schemaVersion
    static let selectionContractSchemaVersion = IncumbentSelectionReceiptV1.schemaVersion
    static let closedCanonicalFields = Set(IncumbentCanonicalFieldV1.allCases)
    static let supportedProjectionKindCount = 2
    static let adapterIdentityComesFromRelease = true
    static let registrySelectionIsSoleCurrentEvidence = true
    static let historicReleaseLookupRequiresExactIDAndDigest = true
    static let directCostProjectionIsAbsent = !IncumbentCanonicalFieldV1.allCases
        .map(\.rawValue).contains("workResource.directCost")
    static let sourceBytesAreScratchOnly = true
    static let quarantineBytesAreScratchOnly = true
    static let scratchExcludedFromBackup = true
    static let scratchDeletedAfterOutcome = true
    static let noPersistentSelectionOrSession = true
    static let noExternalKeysOrPathsPersisted = true
    static let noNetworkOrProviderState = true
    static let reportsUseCanonicalProjectionOnly = true
    static let searchIndexesCanonicalMetadataOnly = true
    static let diagnosticsExcludeCustomerRowsAndSourceBytes = true
    static let formulaAndControlSafeDelimitedOutput = true
    static let deterministicRepeatRender = true
    static let securityScopeIsOperationScoped = true
    static let importedCanonicalRequiresExistingWriter = true
    static let canonicalReapplyOccurred = false

    static func validate() -> Bool {
        profileContractSchemaVersion == 1
            && selectionContractSchemaVersion == 1
            && !closedCanonicalFields.isEmpty
            && supportedProjectionKindCount == 2
            && adapterIdentityComesFromRelease
            && registrySelectionIsSoleCurrentEvidence
            && historicReleaseLookupRequiresExactIDAndDigest
            && directCostProjectionIsAbsent
            && sourceBytesAreScratchOnly
            && quarantineBytesAreScratchOnly
            && scratchExcludedFromBackup
            && scratchDeletedAfterOutcome
            && noPersistentSelectionOrSession
            && noExternalKeysOrPathsPersisted
            && noNetworkOrProviderState
            && importedCanonicalRequiresExistingWriter
            && !canonicalReapplyOccurred
    }

    static let privacyApprovalFieldName = "privacyApproval"
    static let allowedCanonicalFieldsFieldName = "allowedCanonicalFields"
    static let omittedFieldsFieldName = "omittedFields"
    static let previewOutcomeCode = "PREVIEWED_ZERO_WRITE"
    static let sourceChangedCode = "SOURCE_CHANGED"
    static let unsupportedVersionCode = "UNSUPPORTED_VERSION"
    static let headerMismatchCode = "HEADER_MISMATCH"
    static let externalAvailabilityUnknownCode = "EXTERNAL_AVAILABILITY_UNKNOWN"
}
