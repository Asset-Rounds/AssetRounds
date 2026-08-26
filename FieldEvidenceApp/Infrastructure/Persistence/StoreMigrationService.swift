import Darwin
import Foundation

/// Descriptor-pinned storage for the one active schema-migration journal and
/// immutable activation manifests. All artifacts are operational evidence and
/// therefore use the backup-excluded journal policy from P01-C02.
@MainActor
final class StoreMigrationJournalStoreV1 {
    private struct PreparedMigrationEnvelopeV1: Codable, Equatable {
        let schemaVersion: Int
        let journal: StoreMigrationJournalV1
        let journalDigest: String
        let sourceManifest: StoreGenerationManifestV1
        let sourceManifestDigest: String
        let journalWasPresent: Bool
        let sourceManifestWasPresent: Bool

        init(
            journal: StoreMigrationJournalV1,
            sourceManifest: StoreGenerationManifestV1,
            journalWasPresent: Bool,
            sourceManifestWasPresent: Bool
        ) throws {
            schemaVersion = 1
            self.journal = journal
            journalDigest = try journal.canonicalSHA256()
            self.sourceManifest = sourceManifest
            sourceManifestDigest = try sourceManifest.canonicalSHA256()
            self.journalWasPresent = journalWasPresent
            self.sourceManifestWasPresent = sourceManifestWasPresent
            try validate()
        }

        func validate() throws {
            try journal.validate()
            try sourceManifest.validate()
            let exactJournalDigest = try journal.canonicalSHA256()
            let exactManifestDigest = try sourceManifest.canonicalSHA256()
            guard schemaVersion == 1,
                  journal.phase == .prepared,
                  journalDigest == exactJournalDigest,
                  sourceManifestDigest == exactManifestDigest,
                  sourceManifestDigest == journal.sourceManifestDigest,
                  sourceManifest.generationID == journal.sourceGenerationID,
                  sourceManifest.migrationID == journal.migrationID,
                  sourceManifest.storeSchemaRelease == journal.sourceRelease,
                  sourceManifest.frozenIdentityDigest
                    == journal.frozenIdentityDigest,
                  !sourceManifest.files.isEmpty else {
                throw StoreMigrationFailure.invalidContract
            }
            try sourceManifest.files.forEach { try $0.validate() }
        }

        func canonicalData() throws -> Data {
            try validate()
            return try StoreMigrationCanonicalJSONV1.encode(self)
        }

        static func decodeCanonical(from data: Data) throws -> Self {
            try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
                Self.self,
                from: data,
                validate: { try $0.validate() }
            )
        }
    }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        let linkCount: nlink_t
        let type: mode_t

        init(_ information: stat) {
            device = information.st_dev
            inode = information.st_ino
            linkCount = information.st_nlink
            type = information.st_mode & S_IFMT
        }
    }

    private struct FileSnapshot: Equatable {
        let identity: Identity
        let byteCount: off_t
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64

        init(_ information: stat) {
            identity = Identity(information)
            byteCount = information.st_size
            modifiedSeconds = Int64(information.st_mtimespec.tv_sec)
            modifiedNanoseconds = Int64(information.st_mtimespec.tv_nsec)
            changedSeconds = Int64(information.st_ctimespec.tv_sec)
            changedNanoseconds = Int64(information.st_ctimespec.tv_nsec)
        }
    }

    private static let operationsName = "FieldEvidenceOperations"
    private static let migrationName = "schema-migration"
    private static let journalName = "journal.json"
    private static let journalTemporaryName = "journal.next.json"
    private static let preparedEnvelopeName = "prepared-migration.json"
    private static let preparedEnvelopeTemporaryName =
        "prepared-migration.next.json"
    private static let deletionSuffix = ".deleting"
    private static let maximumOwnedArtifactByteCount = 4 * 1024 * 1024

    private let applicationSupportURL: URL
    private let operationsURL: URL
    private let migrationURL: URL
    private let applicationSupportDescriptor: Int32
    private let operationsDescriptor: Int32
    private let migrationDescriptor: Int32
    private let applicationSupportIdentity: Identity
    private let operationsIdentity: Identity
    private let migrationIdentity: Identity

    init(applicationSupportURL: URL) throws {
        let root = applicationSupportURL.standardizedFileURL
        guard root.isFileURL else {
            throw StoreMigrationFailure.invalidPath
        }

        let rootDescriptor = Darwin.open(
            root.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard rootDescriptor >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }

        var retained = [rootDescriptor]
        var succeeded = false
        defer {
            if !succeeded {
                retained.reversed().forEach { _ = Darwin.close($0) }
            }
        }
        do {
            let rootIdentity = try Self.directoryIdentity(rootDescriptor)
            let operationsDescriptor = try Self.openOrCreateDirectory(
                parent: rootDescriptor,
                name: Self.operationsName
            )
            retained.append(operationsDescriptor)
            let operationsIdentity = try Self.directoryIdentity(
                operationsDescriptor
            )
            let migrationDescriptor = try Self.openOrCreateDirectory(
                parent: operationsDescriptor,
                name: Self.migrationName
            )
            retained.append(migrationDescriptor)
            let migrationIdentity = try Self.directoryIdentity(
                migrationDescriptor
            )

            self.applicationSupportURL = root
            self.operationsURL = root.appendingPathComponent(
                Self.operationsName,
                isDirectory: true
            )
            self.migrationURL = self.operationsURL.appendingPathComponent(
                Self.migrationName,
                isDirectory: true
            )
            self.applicationSupportDescriptor = rootDescriptor
            self.operationsDescriptor = operationsDescriptor
            self.migrationDescriptor = migrationDescriptor
            self.applicationSupportIdentity = rootIdentity
            self.operationsIdentity = operationsIdentity
            self.migrationIdentity = migrationIdentity
            try protectDirectory(.stagingDirectory, at: self.operationsURL)
            try protectDirectory(.stagingDirectory, at: self.migrationURL)
            guard Darwin.fsync(migrationDescriptor) == 0,
                  Darwin.fsync(operationsDescriptor) == 0,
                  Darwin.fsync(rootDescriptor) == 0 else {
                throw StoreMigrationFailure.invalidIdentity
            }
            try verify()
            try reconcileDeletionTombstones()
            try requireOnlyOwnedNames(validateManifests: false)
            try reconcilePreparedEnvelopeIfPresent()
            try requireOnlyOwnedNames()
            succeeded = true
            retained.removeAll()
        } catch {
            throw error
        }
    }

    deinit {
        _ = Darwin.close(migrationDescriptor)
        _ = Darwin.close(operationsDescriptor)
        _ = Darwin.close(applicationSupportDescriptor)
    }

    func loadJournal() throws -> StoreMigrationJournalV1? {
        try verify()
        try reconcileDeletionTombstones()
        try requireOnlyOwnedNames(validateManifests: false)
        try reconcilePreparedEnvelopeIfPresent()
        try requireOnlyOwnedNames()
        try reconcileJournalTemporaryIfPresent()
        guard try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.journalName
        ) else {
            try verify()
            return nil
        }
        let captured = try readRegularFile(name: Self.journalName)
        let value = try StoreMigrationJournalV1.decodeCanonical(
            from: captured.data
        )
        try verifyNamedIdentity(
            name: Self.journalName,
            expected: captured.identity
        )
        try protectFile(
            .journal,
            name: Self.journalName,
            expected: captured.identity
        )
        return value
    }

    /// Durably commits the coupled prepared state. The envelope is the commit
    /// authority: recovery materializes the immutable source manifest first,
    /// then the hash-bound prepared journal, and removes the envelope last.
    func createPreparedMigration(
        journal: StoreMigrationJournalV1,
        sourceManifest: StoreGenerationManifestV1
    ) throws {
        // Validate the complete coupling before any recovery or filesystem
        // mutation. Presence flags are recorded only after current state is
        // pinned and proven below.
        _ = try PreparedMigrationEnvelopeV1(
            journal: journal,
            sourceManifest: sourceManifest,
            journalWasPresent: false,
            sourceManifestWasPresent: false
        )

        try verify()
        try reconcileDeletionTombstones()
        try requireOnlyOwnedNames(validateManifests: false)
        try reconcilePreparedEnvelopeIfPresent()
        try reconcileJournalTemporaryIfPresent()
        try requireOnlyOwnedNames()

        let journalData = try journal.canonicalData()
        let manifestName = try Self.manifestName(
            for: sourceManifest.generationID
        )
        let manifestData = try sourceManifest.canonicalData()
        let journalExists = try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.journalName
        )
        let manifestExists = try Self.itemExists(
            parent: migrationDescriptor,
            name: manifestName
        )

        if journalExists {
            let current = try readRegularFile(name: Self.journalName)
            guard current.data == journalData else {
                throw StoreMigrationFailure.invalidPhaseTransition
            }
        }
        if manifestExists {
            let current = try readRegularFile(name: manifestName)
            guard current.data == manifestData else {
                throw StoreMigrationFailure.digestMismatch
            }
        }
        if journalExists && manifestExists {
            return
        }

        let envelope = try PreparedMigrationEnvelopeV1(
            journal: journal,
            sourceManifest: sourceManifest,
            journalWasPresent: journalExists,
            sourceManifestWasPresent: manifestExists
        )
        let envelopeData = try envelope.canonicalData()
        guard envelopeData.count <= Self.maximumOwnedArtifactByteCount else {
            throw StoreMigrationFailure.invalidContract
        }

        guard try !Self.itemExists(
            parent: migrationDescriptor,
            name: Self.preparedEnvelopeName
        ), try !Self.itemExists(
            parent: migrationDescriptor,
            name: Self.preparedEnvelopeTemporaryName
        ) else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidJournal)
        }
        try createRegularFile(
            name: Self.preparedEnvelopeTemporaryName,
            data: envelopeData,
            kind: .journalTemporary
        )
        let temporary = try readRegularFile(
            name: Self.preparedEnvelopeTemporaryName
        )
        guard temporary.data == envelopeData else {
            throw StoreMigrationFailure.digestMismatch
        }
        try verifyNamedIdentity(
            name: Self.preparedEnvelopeTemporaryName,
            expected: temporary.identity
        )
        guard Darwin.renameatx_np(
            migrationDescriptor,
            Self.preparedEnvelopeTemporaryName,
            migrationDescriptor,
            Self.preparedEnvelopeName,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard Darwin.fsync(migrationDescriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let committed = try readRegularFile(
            name: Self.preparedEnvelopeName
        )
        guard committed.data == envelopeData,
              committed.identity == temporary.identity else {
            throw StoreMigrationFailure.maintenanceRequired(
                .forwardFixRequired
            )
        }
        try protectFile(
            .journal,
            name: Self.preparedEnvelopeName,
            expected: committed.identity
        )
        try reconcilePreparedEnvelopeIfPresent()

        let persistedJournal = try readRegularFile(name: Self.journalName)
        let persistedManifest = try readRegularFile(name: manifestName)
        guard persistedJournal.data == journalData,
              persistedManifest.data == manifestData,
              try !Self.itemExists(
                parent: migrationDescriptor,
                name: Self.preparedEnvelopeName
              ) else {
            throw StoreMigrationFailure.maintenanceRequired(
                .forwardFixRequired
            )
        }
    }

    func replaceJournal(
        expected: StoreMigrationJournalV1,
        with replacement: StoreMigrationJournalV1
    ) throws {
        try replacement.validateReplacement(of: expected)
        guard let current = try loadJournal(), current == expected else {
            throw StoreMigrationFailure.invalidPhaseTransition
        }
        let expectedData = try expected.canonicalData()
        let replacementData = try replacement.canonicalData()
        let expectedRead = try readRegularFile(name: Self.journalName)
        guard expectedRead.data == expectedData else {
            throw StoreMigrationFailure.digestMismatch
        }

        try createRegularFile(
            name: Self.journalTemporaryName,
            data: replacementData,
            kind: .journalTemporary
        )
        let replacementRead = try readRegularFile(
            name: Self.journalTemporaryName
        )
        try verifyNamedIdentity(
            name: Self.journalName,
            expected: expectedRead.identity
        )
        try verifyNamedIdentity(
            name: Self.journalTemporaryName,
            expected: replacementRead.identity
        )
        guard Darwin.renameatx_np(
            migrationDescriptor,
            Self.journalTemporaryName,
            migrationDescriptor,
            Self.journalName,
            UInt32(RENAME_SWAP)
        ) == 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }

        // From this point forward the replacement may be published. Never
        // roll it back: every failure is an ambiguous forward-recovery state.
        do {
            guard Darwin.fsync(migrationDescriptor) == 0 else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .forwardFixRequired
                )
            }
            let published = try readRegularFile(name: Self.journalName)
            let displaced = try readRegularFile(name: Self.journalTemporaryName)
            guard published.data == replacementData,
                  published.identity == replacementRead.identity,
                  displaced.data == expectedData,
                  displaced.identity == expectedRead.identity else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .forwardFixRequired
                )
            }
            try unlinkExact(
                name: Self.journalTemporaryName,
                expected: displaced.identity
            )
            try protectFile(
                .journal,
                name: Self.journalName,
                expected: published.identity
            )
            try verify()
        } catch {
            throw Self.forwardFailure(for: error)
        }
    }

    func removeJournal(expected: StoreMigrationJournalV1) throws {
        guard let current = try loadJournal(), current == expected else {
            throw StoreMigrationFailure.invalidPhaseTransition
        }
        let captured = try readRegularFile(name: Self.journalName)
        guard captured.data == (try expected.canonicalData()) else {
            throw StoreMigrationFailure.digestMismatch
        }
        do {
            try unlinkExact(name: Self.journalName, expected: captured.identity)
        } catch {
            throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
        }
        try verify()
        try requireOnlyOwnedNames()
    }

    @discardableResult
    func writeManifest(_ manifest: StoreGenerationManifestV1) throws -> String {
        try manifest.validate()
        let name = try Self.manifestName(for: manifest.generationID)
        let data = try manifest.canonicalData()
        let digest = StoreMigrationCanonicalJSONV1.sha256(data)
        try verify()
        try reconcileDeletionTombstones()
        try requireOnlyOwnedNames()
        if try Self.itemExists(parent: migrationDescriptor, name: name) {
            let existing = try readRegularFile(name: name)
            guard existing.data == data else {
                throw StoreMigrationFailure.digestMismatch
            }
            try protectFile(.journal, name: name, expected: existing.identity)
            return digest
        }
        try createRegularFile(name: name, data: data, kind: .journal)
        let persisted = try readRegularFile(name: name)
        guard persisted.data == data else {
            throw StoreMigrationFailure.digestMismatch
        }
        try protectFile(.journal, name: name, expected: persisted.identity)
        return digest
    }

    func loadManifest(
        targetGenerationID: UUID,
        expectedDigest: String
    ) throws -> StoreGenerationManifestV1 {
        try verify()
        try reconcileDeletionTombstones()
        try requireOnlyOwnedNames()
        guard StoreMigrationCanonicalJSONV1.isLowercaseSHA256(expectedDigest) else {
            throw StoreMigrationFailure.invalidDigest
        }
        let name = try Self.manifestName(for: targetGenerationID)
        let captured = try readRegularFile(name: name)
        guard StoreMigrationCanonicalJSONV1.sha256(captured.data)
                == expectedDigest else {
            throw StoreMigrationFailure.digestMismatch
        }
        let manifest = try StoreGenerationManifestV1.decodeCanonical(
            from: captured.data
        )
        guard manifest.generationID == targetGenerationID else {
            throw StoreMigrationFailure.invalidIdentity
        }
        try protectFile(.journal, name: name, expected: captured.identity)
        return manifest
    }

    func loadManifestIfPresent(
        targetGenerationID: UUID
    ) throws -> (manifest: StoreGenerationManifestV1, digest: String)? {
        try verify()
        try reconcileDeletionTombstones()
        try requireOnlyOwnedNames()
        let name = try Self.manifestName(for: targetGenerationID)
        guard try Self.itemExists(
            parent: migrationDescriptor,
            name: name
        ) else {
            return nil
        }
        let captured = try readRegularFile(name: name)
        let manifest = try StoreGenerationManifestV1.decodeCanonical(
            from: captured.data
        )
        guard manifest.generationID == targetGenerationID else {
            throw StoreMigrationFailure.invalidIdentity
        }
        try protectFile(.journal, name: name, expected: captured.identity)
        return (
            manifest,
            StoreMigrationCanonicalJSONV1.sha256(captured.data)
        )
    }

    func removeManifest(
        targetGenerationID: UUID,
        expectedDigest: String
    ) throws {
        try verify()
        try reconcileDeletionTombstones()
        try requireOnlyOwnedNames()
        let name = try Self.manifestName(for: targetGenerationID)
        let captured = try readRegularFile(name: name)
        guard StoreMigrationCanonicalJSONV1.sha256(captured.data)
                == expectedDigest else {
            throw StoreMigrationFailure.digestMismatch
        }
        _ = try StoreGenerationManifestV1.decodeCanonical(from: captured.data)
        try unlinkExact(name: name, expected: captured.identity)
        try verify()
    }

    private func reconcilePreparedEnvelopeIfPresent() throws {
        if try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.preparedEnvelopeTemporaryName
        ) {
            let temporary = try readRegularFile(
                name: Self.preparedEnvelopeTemporaryName
            )
            try protectFile(
                .journalTemporary,
                name: Self.preparedEnvelopeTemporaryName,
                expected: temporary.identity
            )

            // A temporary-only envelope never crossed the commit rename and
            // therefore has no authority to publish either coupled artifact.
            try unlinkExact(
                name: Self.preparedEnvelopeTemporaryName,
                expected: temporary.identity
            )
        }

        guard try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.preparedEnvelopeName
        ) else { return }

        let committed = try readRegularFile(
            name: Self.preparedEnvelopeName
        )
        let envelope = try PreparedMigrationEnvelopeV1.decodeCanonical(
            from: committed.data
        )
        try protectFile(
            .journal,
            name: Self.preparedEnvelopeName,
            expected: committed.identity
        )

        // The immutable source manifest is made durable before the journal so
        // every visible prepared journal has its exact hash-bound dependency.
        try materializePreparedSourceManifest(envelope)
        let persistedManifest = try loadManifest(
            targetGenerationID: envelope.sourceManifest.generationID,
            expectedDigest: envelope.sourceManifestDigest
        )
        guard persistedManifest == envelope.sourceManifest else {
            throw StoreMigrationFailure.digestMismatch
        }

        try materializePreparedJournal(
            envelope.journal,
            wasPresent: envelope.journalWasPresent
        )
        let persistedJournal = try readRegularFile(name: Self.journalName)
        guard persistedJournal.data == (try envelope.journal.canonicalData()),
              StoreMigrationCanonicalJSONV1.sha256(persistedJournal.data)
                == envelope.journalDigest else {
            throw StoreMigrationFailure.digestMismatch
        }

        // The final envelope remains recoverable authority until both payloads
        // have been independently reread and proven exact.
        try verifyNamedIdentity(
            name: Self.preparedEnvelopeName,
            expected: committed.identity
        )
        try unlinkExact(
            name: Self.preparedEnvelopeName,
            expected: committed.identity
        )
        try verify()
    }

    private func materializePreparedSourceManifest(
        _ envelope: PreparedMigrationEnvelopeV1
    ) throws {
        let manifest = envelope.sourceManifest
        let name = try Self.manifestName(for: manifest.generationID)
        let data = try manifest.canonicalData()
        let exists = try Self.itemExists(
            parent: migrationDescriptor,
            name: name
        )
        if exists {
            let current = try readRegularFile(name: name)
            if current.data == data {
                try protectFile(
                    .journal,
                    name: name,
                    expected: current.identity
                )
                return
            }
            // A manifest at its immutable final name is never replaced. The
            // coupled path publishes through a temporary and RENAME_EXCL, so a
            // mismatch is conflicting accepted state, not crash residue.
            throw StoreMigrationFailure.digestMismatch
        } else if envelope.sourceManifestWasPresent {
            throw StoreMigrationFailure.maintenanceRequired(
                .sourceUnavailable
            )
        }

        guard try !Self.itemExists(
            parent: migrationDescriptor,
            name: Self.preparedEnvelopeTemporaryName
        ) else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidJournal)
        }
        try createRegularFile(
            name: Self.preparedEnvelopeTemporaryName,
            data: data,
            kind: .journalTemporary
        )
        let temporary = try readRegularFile(
            name: Self.preparedEnvelopeTemporaryName
        )
        guard temporary.data == data else {
            throw StoreMigrationFailure.digestMismatch
        }
        try verifyNamedIdentity(
            name: Self.preparedEnvelopeTemporaryName,
            expected: temporary.identity
        )
        if Darwin.renameatx_np(
            migrationDescriptor,
            Self.preparedEnvelopeTemporaryName,
            migrationDescriptor,
            name,
            UInt32(RENAME_EXCL)
        ) != 0 {
            let renameError = errno
            if renameError == EEXIST,
               let raced = try? readRegularFile(name: name),
               raced.data == data {
                try unlinkExact(
                    name: Self.preparedEnvelopeTemporaryName,
                    expected: temporary.identity
                )
                return
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(renameError))
        }
        guard Darwin.fsync(migrationDescriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let persisted = try readRegularFile(name: name)
        guard persisted.data == data,
              persisted.identity == temporary.identity,
              StoreMigrationCanonicalJSONV1.sha256(persisted.data)
                == envelope.sourceManifestDigest else {
            throw StoreMigrationFailure.digestMismatch
        }
        try protectFile(.journal, name: name, expected: persisted.identity)
    }

    private func materializePreparedJournal(
        _ journal: StoreMigrationJournalV1,
        wasPresent: Bool
    ) throws {
        try journal.validate()
        guard journal.phase == .prepared else {
            throw StoreMigrationFailure.invalidPhaseTransition
        }
        let data = try journal.canonicalData()
        let canonicalExists = try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.journalName
        )
        let temporaryExists = try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.journalTemporaryName
        )

        if canonicalExists {
            let current = try readRegularFile(name: Self.journalName)
            guard current.data == data else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .invalidJournal
                )
            }
            if temporaryExists {
                let temporary = try readRegularFile(
                    name: Self.journalTemporaryName
                )
                guard temporary.data == data else {
                    throw StoreMigrationFailure.maintenanceRequired(
                        .invalidJournal
                    )
                }
                try unlinkExact(
                    name: Self.journalTemporaryName,
                    expected: temporary.identity
                )
            }
            try protectFile(
                .journal,
                name: Self.journalName,
                expected: current.identity
            )
            return
        }
        guard !wasPresent else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidJournal)
        }

        var temporary: (data: Data, identity: Identity)
        if temporaryExists {
            temporary = try readRegularFile(
                name: Self.journalTemporaryName
            )
            if temporary.data != data {
                // No journal existed when the envelope committed, and startup
                // reconciled any older temporary before that commit. A partial
                // temporary here is therefore envelope-owned crash residue.
                try unlinkExact(
                    name: Self.journalTemporaryName,
                    expected: temporary.identity
                )
                try createRegularFile(
                    name: Self.journalTemporaryName,
                    data: data,
                    kind: .journalTemporary
                )
                temporary = try readRegularFile(
                    name: Self.journalTemporaryName
                )
            }
        } else {
            try createRegularFile(
                name: Self.journalTemporaryName,
                data: data,
                kind: .journalTemporary
            )
            temporary = try readRegularFile(
                name: Self.journalTemporaryName
            )
        }
        try verifyNamedIdentity(
            name: Self.journalTemporaryName,
            expected: temporary.identity
        )
        guard Darwin.renameatx_np(
            migrationDescriptor,
            Self.journalTemporaryName,
            migrationDescriptor,
            Self.journalName,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard Darwin.fsync(migrationDescriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let persisted = try readRegularFile(name: Self.journalName)
        guard persisted.data == data,
              persisted.identity == temporary.identity else {
            throw StoreMigrationFailure.maintenanceRequired(
                .forwardFixRequired
            )
        }
        try protectFile(
            .journal,
            name: Self.journalName,
            expected: persisted.identity
        )
    }

    private func reconcileJournalTemporaryIfPresent() throws {
        guard try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.journalTemporaryName
        ) else { return }

        let temporary = try readRegularFile(name: Self.journalTemporaryName)
        let temporaryJournal = try StoreMigrationJournalV1.decodeCanonical(
            from: temporary.data
        )
        try protectFile(
            .journalTemporary,
            name: Self.journalTemporaryName,
            expected: temporary.identity
        )

        guard try Self.itemExists(
            parent: migrationDescriptor,
            name: Self.journalName
        ) else {
            guard temporaryJournal.phase == .prepared else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .invalidJournal
                )
            }
            try verifyNamedIdentity(
                name: Self.journalTemporaryName,
                expected: temporary.identity
            )
            guard Darwin.renameatx_np(
                migrationDescriptor,
                Self.journalTemporaryName,
                migrationDescriptor,
                Self.journalName,
                UInt32(RENAME_EXCL)
            ) == 0,
                  Darwin.fsync(migrationDescriptor) == 0 else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .forwardFixRequired
                )
            }
            let persisted = try readRegularFile(name: Self.journalName)
            guard persisted.data == temporary.data,
                  persisted.identity == temporary.identity else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .forwardFixRequired
                )
            }
            try protectFile(
                .journal,
                name: Self.journalName,
                expected: persisted.identity
            )
            return
        }

        let current = try readRegularFile(name: Self.journalName)
        let currentJournal = try StoreMigrationJournalV1.decodeCanonical(
            from: current.data
        )
        if (try? temporaryJournal.validateReplacement(of: currentJournal)) != nil {
            try verifyNamedIdentity(
                name: Self.journalName,
                expected: current.identity
            )
            try verifyNamedIdentity(
                name: Self.journalTemporaryName,
                expected: temporary.identity
            )
            guard Darwin.renameatx_np(
                migrationDescriptor,
                Self.journalTemporaryName,
                migrationDescriptor,
                Self.journalName,
                UInt32(RENAME_SWAP)
            ) == 0,
                  Darwin.fsync(migrationDescriptor) == 0 else {
                throw StoreMigrationFailure.maintenanceRequired(
                    .forwardFixRequired
                )
            }
            do {
                let displaced = try readRegularFile(
                    name: Self.journalTemporaryName
                )
                guard displaced.data == current.data,
                      displaced.identity == current.identity else {
                    throw StoreMigrationFailure.maintenanceRequired(
                        .forwardFixRequired
                    )
                }
                try unlinkExact(
                    name: Self.journalTemporaryName,
                    expected: displaced.identity
                )
            } catch {
                throw Self.forwardFailure(for: error)
            }
        } else if (try? currentJournal.validateReplacement(
            of: temporaryJournal
        )) != nil {
            // The swap succeeded and only old-journal cleanup was interrupted.
            do {
                try unlinkExact(
                    name: Self.journalTemporaryName,
                    expected: temporary.identity
                )
            } catch {
                throw Self.forwardFailure(for: error)
            }
        } else {
            throw StoreMigrationFailure.maintenanceRequired(.invalidJournal)
        }
    }

    private func createRegularFile(
        name: String,
        data: Data,
        kind: OwnedFileKindV1
    ) throws {
        try Self.requireSafeName(name)
        guard data.count <= Self.maximumOwnedArtifactByteCount else {
            throw StoreMigrationFailure.invalidContract
        }
        try verify()
        guard try !Self.itemExists(parent: migrationDescriptor, name: name) else {
            throw StoreMigrationFailure.invalidIdentity
        }
        let descriptor = Darwin.openat(
            migrationDescriptor,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        var cleanupIdentity: Identity?
        var shouldRemove = true
        defer {
            _ = Darwin.close(descriptor)
            if shouldRemove, let cleanupIdentity {
                try? unlinkExact(name: name, expected: cleanupIdentity)
            }
        }
        let identity = try Self.regularFileIdentity(descriptor)
        cleanupIdentity = identity
        try protectFile(kind, name: name, expected: identity)
        try Self.writeAll(data, to: descriptor)
        guard Darwin.fsync(descriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        try verifyNamedIdentity(name: name, expected: identity)
        guard Darwin.fsync(migrationDescriptor) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let reread = try readRegularFile(name: name)
        guard reread.identity == identity, reread.data == data else {
            throw StoreMigrationFailure.digestMismatch
        }
        shouldRemove = false
    }

    private func readRegularFile(
        name: String
    ) throws -> (data: Data, identity: Identity) {
        try Self.requireSafeName(name)
        try verify()
        let descriptor = Darwin.openat(
            migrationDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        defer { _ = Darwin.close(descriptor) }
        let identity = try Self.regularFileIdentity(descriptor)
        try protectFile(
            Self.ownedFileKind(for: name),
            name: name,
            expected: identity
        )
        let before = try Self.regularFileSnapshot(descriptor)
        let data = try Self.readAll(from: descriptor)
        guard try Self.regularFileSnapshot(descriptor) == before else {
            throw StoreMigrationFailure.invalidIdentity
        }
        try verifyNamedIdentity(name: name, expected: before.identity)
        return (data, before.identity)
    }

    private func unlinkExact(name: String, expected: Identity) throws {
        try verifyNamedIdentity(name: name, expected: expected)
        let tombstone = try Self.deletionTombstoneName(for: name)
        guard try !Self.itemExists(
            parent: migrationDescriptor,
            name: tombstone
        ), Darwin.renameatx_np(
            migrationDescriptor,
            name,
            migrationDescriptor,
            tombstone,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        guard Darwin.fsync(migrationDescriptor) == 0 else {
            throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
        }
        let moved = try readRegularFile(name: tombstone)
        guard moved.identity == expected else {
            if try !Self.itemExists(parent: migrationDescriptor, name: name) {
                _ = Darwin.renameatx_np(
                    migrationDescriptor,
                    tombstone,
                    migrationDescriptor,
                    name,
                    UInt32(RENAME_EXCL)
                )
                _ = Darwin.fsync(migrationDescriptor)
            }
            throw StoreMigrationFailure.invalidIdentity
        }
        try unlinkQuarantined(name: tombstone, expected: expected)
        guard try !Self.itemExists(
            parent: migrationDescriptor,
            name: name
        ) else {
            throw StoreMigrationFailure.invalidIdentity
        }
    }

    private func unlinkQuarantined(name: String, expected: Identity) throws {
        try verifyNamedIdentity(name: name, expected: expected)
        guard Darwin.unlinkat(migrationDescriptor, name, 0) == 0,
              Darwin.fsync(migrationDescriptor) == 0 else {
            throw StoreMigrationFailure.maintenanceRequired(.forwardFixRequired)
        }
    }

    private func reconcileDeletionTombstones() throws {
        let names = try Self.names(in: migrationDescriptor)
        for tombstone in names where tombstone.hasSuffix(Self.deletionSuffix) {
            let original = String(tombstone.dropLast(Self.deletionSuffix.count))
            guard Self.isOwnedBaseName(original),
                  try !Self.itemExists(
                    parent: migrationDescriptor,
                    name: original
                  ) else {
                throw StoreMigrationFailure.maintenanceRequired(.invalidJournal)
            }
            let captured = try readRegularFile(name: tombstone)
            try unlinkQuarantined(
                name: tombstone,
                expected: captured.identity
            )
        }
    }

    private func protectDirectory(
        _ kind: OwnedFileKindV1,
        at url: URL
    ) throws {
        try ProtectedFilePolicyV1.applyAndVerify(
            kind,
            at: url,
            authorityCheck: { [self] in try verify() }
        )
    }

    private func protectFile(
        _ kind: OwnedFileKindV1,
        name: String,
        expected: Identity
    ) throws {
        let url = migrationURL.appendingPathComponent(
            name,
            isDirectory: false
        )
        try ProtectedFilePolicyV1.applyAndVerify(
            kind,
            at: url,
            authorityCheck: { [self] in
                try verify()
                try verifyNamedIdentity(name: name, expected: expected)
            }
        )
        let descriptor = Darwin.openat(
            migrationDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.regularFileIdentity(descriptor) == expected,
              Darwin.fsync(descriptor) == 0,
              Darwin.fsync(migrationDescriptor) == 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
    }

    private func verify() throws {
        try Self.requireDirectory(
            applicationSupportDescriptor,
            identity: applicationSupportIdentity
        )
        try Self.requireDirectory(
            operationsDescriptor,
            identity: operationsIdentity
        )
        try Self.requireDirectory(
            migrationDescriptor,
            identity: migrationIdentity
        )
        let currentRoot = Darwin.open(
            applicationSupportURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard currentRoot >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        defer { _ = Darwin.close(currentRoot) }
        guard try Self.directoryIdentity(currentRoot)
                == applicationSupportIdentity else {
            throw StoreMigrationFailure.invalidIdentity
        }
        try verifyChildDirectory(
            parent: applicationSupportDescriptor,
            name: Self.operationsName,
            expected: operationsIdentity
        )
        try verifyChildDirectory(
            parent: operationsDescriptor,
            name: Self.migrationName,
            expected: migrationIdentity
        )
    }

    private func verifyChildDirectory(
        parent: Int32,
        name: String,
        expected: Identity
    ) throws {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.directoryIdentity(descriptor) == expected else {
            throw StoreMigrationFailure.invalidIdentity
        }
    }

    private func verifyNamedIdentity(
        name: String,
        expected: Identity
    ) throws {
        let descriptor = Darwin.openat(
            migrationDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.regularFileIdentity(descriptor) == expected else {
            throw StoreMigrationFailure.invalidIdentity
        }
    }

    private func requireOnlyOwnedNames(
        validateManifests: Bool = true
    ) throws {
        let names = try Self.names(in: migrationDescriptor)
        guard names.allSatisfy({ name in
            name == Self.journalName
                || name == Self.journalTemporaryName
                || name == Self.preparedEnvelopeName
                || name == Self.preparedEnvelopeTemporaryName
                || Self.isManifestName(name)
        }) else {
            throw StoreMigrationFailure.invalidPath
        }
        guard validateManifests else { return }
        for name in names where Self.isManifestName(name) {
            let captured = try readRegularFile(name: name)
            let manifest = try StoreGenerationManifestV1.decodeCanonical(
                from: captured.data
            )
            guard try Self.manifestName(for: manifest.generationID) == name else {
                throw StoreMigrationFailure.invalidIdentity
            }
        }
    }

    private static func manifestName(for id: UUID) throws -> String {
        let canonical = id.uuidString.lowercased()
        guard UUID(uuidString: canonical)?.uuidString.lowercased()
                == canonical else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return "manifest-\(canonical).json"
    }

    private static func isManifestName(_ name: String) -> Bool {
        let prefix = "manifest-"
        let suffix = ".json"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else {
            return false
        }
        let start = name.index(name.startIndex, offsetBy: prefix.count)
        let end = name.index(name.endIndex, offsetBy: -suffix.count)
        let value = String(name[start..<end])
        return UUID(uuidString: value)?.uuidString.lowercased() == value
    }

    private static func isOwnedBaseName(_ name: String) -> Bool {
        name == journalName
            || name == journalTemporaryName
            || name == preparedEnvelopeName
            || name == preparedEnvelopeTemporaryName
            || isManifestName(name)
    }

    private static func deletionTombstoneName(for name: String) throws -> String {
        guard isOwnedBaseName(name) else {
            throw StoreMigrationFailure.invalidPath
        }
        return name + deletionSuffix
    }

    private static func ownedFileKind(for name: String) -> OwnedFileKindV1 {
        let baseName = name.hasSuffix(deletionSuffix)
            ? String(name.dropLast(deletionSuffix.count))
            : name
        return baseName == journalTemporaryName
            || baseName == preparedEnvelopeTemporaryName
            ? .journalTemporary
            : .journal
    }

    private static func forwardFailure(for error: Error) -> StoreMigrationFailure {
        if let failure = error as? StoreMigrationFailure {
            switch failure {
            case .maintenanceRequired:
                return failure
            default:
                break
            }
        }
        if ProtectedFilePolicyV1.isProtectedDataUnavailable(error) {
            return .maintenanceRequired(.protectedDataUnavailable)
        }
        var current = error as NSError
        for _ in 0..<8 {
            if current.domain == NSPOSIXErrorDomain,
               current.code == ENOSPC {
                return .maintenanceRequired(.insufficientStorage)
            }
            if current.domain == NSCocoaErrorDomain,
               current.code == NSFileWriteOutOfSpaceError {
                return .maintenanceRequired(.insufficientStorage)
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey]
                    as? NSError,
                  underlying !== current else {
                break
            }
            current = underlying
        }
        return .maintenanceRequired(.forwardFixRequired)
    }

    private static func requireSafeName(_ name: String) throws {
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\\") else {
            throw StoreMigrationFailure.invalidPath
        }
    }

    private static func openOrCreateDirectory(
        parent: Int32,
        name: String
    ) throws -> Int32 {
        try requireSafeName(name)
        var descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if descriptor >= 0 { return descriptor }
        guard errno == ENOENT,
              Darwin.mkdirat(parent, name, mode_t(0o700)) == 0,
              Darwin.fsync(parent) == 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return descriptor
    }

    private static func requireDirectory(
        _ descriptor: Int32,
        identity: Identity
    ) throws {
        guard try directoryIdentity(descriptor) == identity else {
            throw StoreMigrationFailure.invalidIdentity
        }
    }

    private static func directoryIdentity(_ descriptor: Int32) throws -> Identity {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFDIR,
              information.st_nlink >= 1 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return Identity(information)
    }

    private static func regularFileIdentity(_ descriptor: Int32) throws -> Identity {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return Identity(information)
    }

    private static func regularFileSnapshot(_ descriptor: Int32) throws -> FileSnapshot {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1,
              information.st_size >= 0,
              information.st_size <= off_t(maximumOwnedArtifactByteCount) else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return FileSnapshot(information)
    }

    private static func itemExists(parent: Int32, name: String) throws -> Bool {
        try requireSafeName(name)
        var information = stat()
        guard Darwin.fstatat(
            parent,
            name,
            &information,
            AT_SYMLINK_NOFOLLOW
        ) == 0 else {
            if errno == ENOENT { return false }
            throw StoreMigrationFailure.invalidIdentity
        }
        guard (information.st_mode & S_IFMT) != S_IFLNK else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return true
    }

    private static func readAll(from descriptor: Int32) throws -> Data {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { return result }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw StoreMigrationFailure.invalidIdentity
            }
            guard result.count <= maximumOwnedArtifactByteCount - count else {
                throw StoreMigrationFailure.invalidContract
            }
            result.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    rawBuffer.baseAddress?.advanced(by: offset),
                    rawBuffer.count - offset
                )
                guard count > 0 else {
                    if count < 0 && errno == EINTR { continue }
                    throw NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(errno)
                    )
                }
                offset += count
            }
        }
    }

    private static func names(in descriptor: Int32) throws -> [String] {
        let independent = Darwin.openat(
            descriptor,
            ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard independent >= 0,
              let directory = Darwin.fdopendir(independent) else {
            if independent >= 0 { _ = Darwin.close(independent) }
            throw StoreMigrationFailure.invalidIdentity
        }
        defer { _ = Darwin.closedir(directory) }
        var values: [String] = []
        errno = 0
        while let entry = Darwin.readdir(directory) {
            var tuple = entry.pointee.d_name
            let capacity = MemoryLayout.size(ofValue: tuple)
            let name = withUnsafePointer(to: &tuple) { pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: capacity
                ) { String(cString: $0) }
            }
            if name != "." && name != ".." { values.append(name) }
            errno = 0
        }
        guard errno == 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return values.sorted()
    }
}
