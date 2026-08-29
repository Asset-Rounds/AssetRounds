import Foundation

/// C46 lifecycle truth: the durable intent is purpose-separated operational
/// metadata. Backup/restore may preserve it; clone/fork rebound it as historic
/// and non-executable; delete/Erase remove it. Export/search never disclose a
/// raw destination, and replay never repeats a platform presentation outcome.
enum C46OperationalContactLifecycleBoundaryV1 {
    static let purposeSeparatedFromMarketing = true
    static let backupAndRestorePreserveDurableIntent = true
    static let cloneAndForkAreHistoricOnly = true
    static let deleteAndEraseRemoveIntent = true
    static let exportAndSearchExcludeRawDestination = true
    static let replayRepeatsSystemHandoff = false
}

enum OperationalContactCoordinatorFailureV1: Error, Equatable {
    case invalidRoute
    case targetMissing
    case targetStale
    case targetInvalid
    case intentMissing
    case writerReceiptMismatch
    case invalidImport
    case importAuthorityUnavailable
    case previewMismatch
    case cancelled
}

struct OperationalContactIntentReviewV1: Equatable, Sendable {
    let intent: SystemHandoffIntentV1
    let receipt: OperationalContactMutationReceiptV1
}

/// Ephemeral, bounded PARTY_CONTACTS_V1 review material. It is deliberately
/// non-Codable so raw contact values and source bytes cannot become route,
/// backup, journal, search, diagnostics, or marketing state.
struct PartyContactsImportPreviewV1: Equatable, Sendable {
    static let csvHeader = [
        "row_index", "contact_point_id", "party_id", "kind", "label",
        "display_value", "preferred", "effective_at", "retired_at", "revision",
    ]
    static let dateFormat = "RFC3339_UTC_MILLISECONDS"

    let sourceSet: ImportSourceSetV1
    let rows: [PartyContactCSVRowV1]
    let previewSHA256: String

    init(sourceSet: ImportSourceSetV1, rows: [PartyContactCSVRowV1]) throws {
        let ordered = rows.sorted { $0.rowIndex < $1.rowIndex }
        guard !ordered.isEmpty,
              ordered.count <= OperationalContactLimitsV1.maximumMutationContacts,
              ordered.map(\.rowIndex) == Array(1...ordered.count),
              Set(ordered.map(\.contactPointID)).count == ordered.count,
              PartyContactsCSVContractV1.valuePrivacyClass == .restrictedContactValue,
              !PartyContactsCSVContractV1.defaultExportEnabled else {
            throw OperationalContactCoordinatorFailureV1.invalidImport
        }
        self.sourceSet = sourceSet
        self.rows = ordered
        self.previewSHA256 = try OperationalContactCanonicalCodecV1.sha256(
            DigestBasis(sourceSet: sourceSet, rows: ordered)
        )
    }

    func validate() throws {
        let rebuilt = try Self(sourceSet: sourceSet, rows: rows)
        guard rebuilt.previewSHA256 == previewSHA256 else {
            throw OperationalContactCoordinatorFailureV1.previewMismatch
        }
    }

    private struct DigestBasis: Codable {
        let sourceSet: ImportSourceSetV1
        let rows: [PartyContactCSVRowV1]
    }
}

enum PartyContactsImportCancellationDispositionV1: Equatable, Sendable {
    case cancelledNoMutation
}

/// Records the user's reviewed, stable-ID-only intent through the canonical
/// workspace writer. It does not present a system UI and records no claim that
/// a call, message, email, or directions request succeeded.
@MainActor
final class OperationalContactCoordinatorV1 {
    private static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
    private let query: any OperationalContactHandoffQueryingV1
    private let writer: any OperationalContactCanonicalWorkspaceWritingV1
    private let importQuery: (any OperationalContactImportQueryingV1)?
    private let system: any SystemHandoffPortV1
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource

    init(
        query: any OperationalContactHandoffQueryingV1,
        writer: any OperationalContactCanonicalWorkspaceWritingV1,
        system: any SystemHandoffPortV1,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource,
        importQuery: (any OperationalContactImportQueryingV1)? = nil
    ) {
        self.query = query
        self.writer = writer
        self.system = system
        self.clock = clock
        self.idSource = idSource
        self.importQuery = importQuery
    }

    func reviewIntent(
        workspaceID: WorkspaceID,
        route: OperationalContactHandoffRouteV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) async throws -> OperationalContactIntentReviewV1 {
        guard expectedRevision.workspaceID == workspaceID,
              route.targetID != Self.zeroUUID,
              let target = try await query.currentTargetReference(
                workspaceID: workspaceID,
                route: route
              ) else {
            throw OperationalContactCoordinatorFailureV1.targetMissing
        }
        guard target.workspaceID == workspaceID,
              target.targetID == route.targetID,
              target.kind == route.targetKind else {
            throw OperationalContactCoordinatorFailureV1.targetInvalid
        }

        let intentID = idSource.makeID()
        guard intentID != Self.zeroUUID else {
            throw OperationalContactCoordinatorFailureV1.invalidRoute
        }
        let intent = try SystemHandoffIntentV1(
            intentID: intentID,
            workspaceID: workspaceID,
            kind: route.kind,
            target: target,
            reviewedAt: clock.now(),
            revision: 1,
            mutationID: mutationID
        )
        let identity = try WorkspaceEntityIdentityV1(
            kind: .systemHandoffIntent,
            id: intentID
        )
        guard expectedRevision.entityRevisions.contains(where: {
            $0.identity == identity && $0.revision == 0
        }) else {
            throw OperationalContactCoordinatorFailureV1.targetStale
        }
        let mutation = try OperationalContactMutationV1(
            workspaceID: workspaceID,
            mutationID: mutationID,
            expectedRevision: expectedRevision,
            handoffIntents: [intent]
        )
        let receipt = try await writer.commitOperationalContact(mutation)
        guard receipt.mutationSHA256 == (try OperationalContactCanonicalCodecV1.sha256(mutation)),
              receipt.affectedIdentities.contains(identity) else {
            throw OperationalContactCoordinatorFailureV1.writerReceiptMismatch
        }
        return OperationalContactIntentReviewV1(intent: intent, receipt: receipt)
    }

    /// Parses all declared files in source order. It requires an exact header,
    /// canonical UTF-8/NFC values, RFC3339 UTC milliseconds, contiguous global
    /// row indexes, exact byte counts/digests, and the core aggregate bounds.
    /// No preview or raw source byte is persisted.
    func previewPartyContacts(
        sourceSet: ImportSourceSetV1,
        fileBytesByName: [String: Data]
    ) async throws -> PartyContactsImportPreviewV1 {
        guard !Task.isCancelled else {
            throw OperationalContactCoordinatorFailureV1.cancelled
        }
        guard fileBytesByName.count == sourceSet.files.count,
              Set(fileBytesByName.keys) == Set(sourceSet.files.map(\.fileName)) else {
            throw OperationalContactCoordinatorFailureV1.invalidImport
        }
        var rows: [PartyContactCSVRowV1] = []
        for file in sourceSet.files {
            guard !Task.isCancelled else {
                throw OperationalContactCoordinatorFailureV1.cancelled
            }
            guard file.schemaID == PartyContactsCSVContractV1.schemaID,
                  file.schemaVersion == PartyContactsCSVContractV1.schemaVersion,
                  let data = fileBytesByName[file.fileName],
                  Int64(data.count) == file.byteCount,
                  KernelCanonicalHashV1.sha256(data) == file.sha256 else {
                throw OperationalContactCoordinatorFailureV1.invalidImport
            }
            rows.append(contentsOf: try Self.parsePartyContactsCSV(data))
            guard rows.count <= OperationalContactLimitsV1.maximumMutationContacts else {
                throw OperationalContactFailureV1.limitExceeded
            }
        }
        return try PartyContactsImportPreviewV1(sourceSet: sourceSet, rows: rows)
    }

    /// Cancelling a preview is a local disposal operation. There is no writer
    /// call, no row state, and no partial success to recover.
    func cancelPartyContactsImport(
        _ preview: PartyContactsImportPreviewV1
    ) throws -> PartyContactsImportCancellationDispositionV1 {
        try preview.validate()
        return .cancelledNoMutation
    }

    /// Explicit acceptance re-queries all affected parties and complete
    /// contact scopes at one bound revision, constructs every successor and
    /// preferred scope in memory, then invokes the canonical writer exactly
    /// once. Any error or cancellation before that call writes nothing.
    func acceptPartyContactsImport(
        preview: PartyContactsImportPreviewV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1
    ) async throws -> OperationalContactMutationReceiptV1 {
        try preview.validate()
        guard !Task.isCancelled else {
            throw OperationalContactCoordinatorFailureV1.cancelled
        }
        guard expectedRevision.workspaceID == preview.sourceSet.workspaceID,
              let importQuery else {
            throw OperationalContactCoordinatorFailureV1.importAuthorityUnavailable
        }
        let partyIDs = Array(Set(preview.rows.map(\.partyID))).sorted {
            $0.uuidString < $1.uuidString
        }
        let state = try await importQuery.currentImportState(
            workspaceID: preview.sourceSet.workspaceID,
            partyIDs: partyIDs
        )
        guard !Task.isCancelled else {
            throw OperationalContactCoordinatorFailureV1.cancelled
        }
        let parties = Dictionary(uniqueKeysWithValues: state.parties.map {
            ($0.partyID, $0)
        })
        guard Set(parties.keys) == Set(partyIDs),
              parties.values.allSatisfy({
                $0.workspaceID == preview.sourceSet.workspaceID && $0.state == .effective
              }),
              state.contacts.allSatisfy({
                $0.workspaceID == preview.sourceSet.workspaceID
                    && partyIDs.contains($0.party.partyID)
              }) else {
            throw OperationalContactCoordinatorFailureV1.invalidImport
        }
        let current = Dictionary(uniqueKeysWithValues: state.contacts.map {
            ($0.contactPointID, $0)
        })
        var predecessors: [ServiceContactPointV1] = []
        var successors: [ServiceContactPointV1] = []
        for row in preview.rows {
            guard let party = parties[row.partyID] else {
                throw OperationalContactCoordinatorFailureV1.invalidImport
            }
            let predecessor = current[row.contactPointID]
            if let predecessor { predecessors.append(predecessor) }
            let lifecycle: ServiceContactLifecycleV1 =
                row.retiredAt == nil ? .effective : .retired
            successors.append(try ServiceContactPointV1(
                contactPointID: row.contactPointID,
                workspaceID: preview.sourceSet.workspaceID,
                party: party,
                kind: row.kind,
                label: row.label,
                displayValue: row.displayValue,
                preferred: lifecycle == .effective && row.preferred,
                provenance: .importedExternalEvidence,
                importSourceSetSHA256: preview.sourceSet.sourceSetSHA256,
                lifecycle: lifecycle,
                effectiveAt: row.effectiveAt,
                retiredAt: row.retiredAt,
                revision: row.revision,
                supersedes: try predecessor?.revisionReference,
                mutationID: mutationID
            ))
        }
        let scopes = try Self.preferredScopes(
            current: state.contacts,
            successors: successors
        )
        let mutation = try OperationalContactMutationV1(
            workspaceID: preview.sourceSet.workspaceID,
            mutationID: mutationID,
            expectedRevision: expectedRevision,
            predecessors: predecessors,
            successors: successors,
            preferredScopes: scopes,
            importSourceSet: preview.sourceSet
        )
        guard !Task.isCancelled else {
            throw OperationalContactCoordinatorFailureV1.cancelled
        }
        let receipt = try await writer.commitOperationalContact(mutation)
        guard receipt.mutationSHA256 == (try OperationalContactCanonicalCodecV1.sha256(mutation)) else {
            throw OperationalContactCoordinatorFailureV1.writerReceiptMismatch
        }
        return receipt
    }

    /// Executes only an already-durable intent, re-reading both the intent and
    /// its target at tap time. Cancellation is checked before resolution and
    /// again before the sole OS handoff call.
    func handOff(
        workspaceID: WorkspaceID,
        intentID: UUID
    ) async throws -> SystemHandoffResultV1 {
        guard intentID != Self.zeroUUID else {
            throw OperationalContactCoordinatorFailureV1.invalidRoute
        }
        if Task.isCancelled {
            return try result(intentID, .cancelledBeforeHandoff)
        }
        let intent: SystemHandoffIntentV1
        do {
            guard let current = try await query.handoffIntent(
                workspaceID: workspaceID,
                intentID: intentID
            ) else {
                return try result(intentID, .targetMissing)
            }
            try current.validate()
            guard current.workspaceID == workspaceID,
                  current.intentID == intentID,
                  current.disposition == .activeSourceWorkspace else {
                return try result(intentID, .targetInvalid)
            }
            intent = current
        } catch {
            return try result(intentID, .targetInvalid)
        }

        if Task.isCancelled {
            return try result(intentID, .cancelledBeforeHandoff)
        }
        switch await query.resolveForHandoff(intent) {
        case .targetMissing:
            return try result(intentID, .targetMissing)
        case .targetStale:
            return try result(intentID, .targetStale)
        case .targetInvalid:
            return try result(intentID, .targetInvalid)
        case let .resolved(request):
            if Task.isCancelled {
                return try result(
                    intentID,
                    .cancelledBeforeHandoff,
                    revision: request.currentTarget.expectedRevision
                )
            }
            return await system.handOff(request)
        }
    }

    private func result(
        _ intentID: UUID,
        _ disposition: SystemHandoffDispositionV1,
        revision: UInt64? = nil
    ) throws -> SystemHandoffResultV1 {
        try SystemHandoffResultV1(
            intentID: intentID,
            disposition: disposition,
            evaluatedAt: clock.now(),
            resolvedTargetRevision: revision
        )
    }

    private static func preferredScopes(
        current: [ServiceContactPointV1],
        successors: [ServiceContactPointV1]
    ) throws -> [ServiceContactPreferredScopeV1] {
        let affected = Set(successors.map {
            "\($0.party.partyID.uuidString):\($0.kind.rawValue)"
        })
        var final = Dictionary(uniqueKeysWithValues: current.map {
            ($0.contactPointID, $0)
        })
        for successor in successors { final[successor.contactPointID] = successor }
        return try affected.sorted().map { key in
            guard let sample = successors.first(where: {
                "\($0.party.partyID.uuidString):\($0.kind.rawValue)" == key
            }) else { throw OperationalContactCoordinatorFailureV1.invalidImport }
            let active = final.values.filter {
                $0.party.partyID == sample.party.partyID
                    && $0.kind == sample.kind && $0.lifecycle == .effective
            }.sorted { $0.contactPointID.uuidString < $1.contactPointID.uuidString }
            let preferred = active.filter(\.preferred)
            guard preferred.count <= 1 else {
                throw OperationalContactFailureV1.preferredConflict
            }
            return try ServiceContactPreferredScopeV1(
                partyID: sample.party.partyID,
                kind: sample.kind,
                activeContactPointIDs: active.map(\.contactPointID),
                preferredContactPointID: preferred.first?.contactPointID
            )
        }
    }

    private static func parsePartyContactsCSV(
        _ data: Data
    ) throws -> [PartyContactCSVRowV1] {
        guard let decoded = String(data: data, encoding: .utf8),
              decoded == decoded.precomposedStringWithCanonicalMapping,
              !decoded.contains("\r") || !decoded.replacingOccurrences(
                of: "\r\n", with: ""
              ).contains("\r") else {
            throw OperationalContactCoordinatorFailureV1.invalidImport
        }
        var lines = decoded.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if lines.last == "" { lines.removeLast() }
        guard let header = lines.first,
              try csvFields(header) == PartyContactsImportPreviewV1.csvHeader else {
            throw OperationalContactCoordinatorFailureV1.invalidImport
        }
        return try lines.dropFirst().map { line in
            let fields = try csvFields(line)
            guard fields.count == PartyContactsImportPreviewV1.csvHeader.count,
                  let rowIndex = Int(fields[0]),
                  let contactID = UUID(uuidString: fields[1]),
                  let partyID = UUID(uuidString: fields[2]),
                  let kind = ServiceContactKindV1(rawValue: fields[3]),
                  let label = ServiceContactLabelV1(rawValue: fields[4]),
                  let preferred = parseBoolean(fields[6]),
                  let effectiveAt = parseDate(fields[7]),
                  let revision = UInt64(fields[9]) else {
                throw OperationalContactCoordinatorFailureV1.invalidImport
            }
            let retiredAt: Date?
            if fields[8].isEmpty { retiredAt = nil }
            else if let value = parseDate(fields[8]) { retiredAt = value }
            else { throw OperationalContactCoordinatorFailureV1.invalidImport }
            return try PartyContactCSVRowV1(
                rowIndex: rowIndex,
                contactPointID: contactID,
                partyID: partyID,
                kind: kind,
                label: label,
                displayValue: fields[5],
                preferred: preferred,
                effectiveAt: effectiveAt,
                retiredAt: retiredAt,
                revision: revision
            )
        }
    }

    private static func csvFields(_ line: String) throws -> [String] {
        let characters = Array(line)
        var fields: [String] = []
        var field = ""
        var quoted = false
        var closedQuote = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"", index + 1 < characters.count,
                   characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 2
                    continue
                }
                if character == "\"" {
                    quoted = false
                    closedQuote = true
                } else {
                    field.append(character)
                }
            } else if character == "," {
                fields.append(field)
                field = ""
                closedQuote = false
            } else if character == "\"", field.isEmpty, !closedQuote {
                quoted = true
            } else {
                guard !closedQuote else {
                    throw OperationalContactCoordinatorFailureV1.invalidImport
                }
                field.append(character)
            }
            index += 1
        }
        guard !quoted else {
            throw OperationalContactCoordinatorFailureV1.invalidImport
        }
        fields.append(field)
        return fields
    }

    private static func parseBoolean(_ value: String) -> Bool? {
        switch value {
        case "TRUE": return true
        case "FALSE": return false
        default: return nil
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        guard value.hasSuffix("Z") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = formatter.date(from: value),
              formatter.string(from: date) == value else { return nil }
        return date
    }
}
