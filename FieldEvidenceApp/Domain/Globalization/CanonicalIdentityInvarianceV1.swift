import CryptoKit
import Foundation

/// Fail-closed outcomes for the C05 proof that presentation axes never become
/// canonical workspace identity or historical data.
enum CanonicalIdentityInvarianceFailureV1: Error, Equatable, Sendable {
    case invalidSnapshot
    case invalidDigest
    case presentationDidNotChange
    case canonicalIdentityChanged([String])
    case historicalIdentityChanged
    case seamBoundaryViolation
}

/// A compact, deterministic projection of the identity-bearing values that
/// must survive a language or formatting change byte-for-byte.
struct CanonicalIdentitySnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let stableIDs: [String]
    let rawEnumValues: [String]
    let mutationSHA256: String
    let journalSHA256: String
    let evidenceSHA256: String
    let backupIdentitySHA256: String
    let authoredEvidenceSHA256: String
    let productIdentitySHA256: String
    let jurisdictionIdentifier: String
    let historicalEnUSIdentities: [String]
    let snapshotSHA256: String

    init(
        stableIDs: [String],
        rawEnumValues: [String],
        mutationSHA256: String,
        journalSHA256: String,
        evidenceSHA256: String,
        backupIdentitySHA256: String,
        authoredEvidenceSHA256: String,
        productIdentitySHA256: String,
        jurisdictionIdentifier: String,
        historicalEnUSIdentities: [String]
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.stableIDs = stableIDs.sorted()
        self.rawEnumValues = rawEnumValues.sorted()
        self.mutationSHA256 = mutationSHA256
        self.journalSHA256 = journalSHA256
        self.evidenceSHA256 = evidenceSHA256
        self.backupIdentitySHA256 = backupIdentitySHA256
        self.authoredEvidenceSHA256 = authoredEvidenceSHA256
        self.productIdentitySHA256 = productIdentitySHA256
        self.jurisdictionIdentifier = jurisdictionIdentifier
        self.historicalEnUSIdentities = historicalEnUSIdentities.sorted()
        self.snapshotSHA256 = try Self.digest(
            Material(
                schemaVersion: Self.schemaVersion,
                stableIDs: self.stableIDs,
                rawEnumValues: self.rawEnumValues,
                mutationSHA256: mutationSHA256,
                journalSHA256: journalSHA256,
                evidenceSHA256: evidenceSHA256,
                backupIdentitySHA256: backupIdentitySHA256,
                authoredEvidenceSHA256: authoredEvidenceSHA256,
                productIdentitySHA256: productIdentitySHA256,
                jurisdictionIdentifier: jurisdictionIdentifier,
                historicalEnUSIdentities: self.historicalEnUSIdentities
            )
        )
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              !stableIDs.isEmpty,
              stableIDs == stableIDs.sorted(),
              Set(stableIDs).count == stableIDs.count,
              stableIDs.allSatisfy(Self.isToken),
              !rawEnumValues.isEmpty,
              rawEnumValues == rawEnumValues.sorted(),
              Set(rawEnumValues).count == rawEnumValues.count,
              rawEnumValues.allSatisfy(Self.isToken),
              !jurisdictionIdentifier.isEmpty,
              Self.isToken(jurisdictionIdentifier),
              !historicalEnUSIdentities.isEmpty,
              historicalEnUSIdentities == historicalEnUSIdentities.sorted(),
              Set(historicalEnUSIdentities).count == historicalEnUSIdentities.count,
              historicalEnUSIdentities.allSatisfy({ $0.contains("en-US") && Self.isToken($0) }),
              Self.isSHA256(mutationSHA256),
              Self.isSHA256(journalSHA256),
              Self.isSHA256(evidenceSHA256),
              Self.isSHA256(backupIdentitySHA256),
              Self.isSHA256(authoredEvidenceSHA256),
              Self.isSHA256(productIdentitySHA256),
              Self.isSHA256(snapshotSHA256) else {
            throw CanonicalIdentityInvarianceFailureV1.invalidSnapshot
        }

        let expected = try Self.digest(
            Material(
                schemaVersion: schemaVersion,
                stableIDs: stableIDs,
                rawEnumValues: rawEnumValues,
                mutationSHA256: mutationSHA256,
                journalSHA256: journalSHA256,
                evidenceSHA256: evidenceSHA256,
                backupIdentitySHA256: backupIdentitySHA256,
                authoredEvidenceSHA256: authoredEvidenceSHA256,
                productIdentitySHA256: productIdentitySHA256,
                jurisdictionIdentifier: jurisdictionIdentifier,
                historicalEnUSIdentities: historicalEnUSIdentities
            )
        )
        guard snapshotSHA256 == expected else {
            throw CanonicalIdentityInvarianceFailureV1.invalidDigest
        }
    }

    var canonicalFields: [String: String] {
        [
            "stableIDs": stableIDs.joined(separator: "\u{1F}"),
            "rawEnumValues": rawEnumValues.joined(separator: "\u{1F}"),
            "mutationSHA256": mutationSHA256,
            "journalSHA256": journalSHA256,
            "evidenceSHA256": evidenceSHA256,
            "backupIdentitySHA256": backupIdentitySHA256,
            "authoredEvidenceSHA256": authoredEvidenceSHA256,
            "productIdentitySHA256": productIdentitySHA256,
            "jurisdictionIdentifier": jurisdictionIdentifier,
            "historicalEnUSIdentities": historicalEnUSIdentities.joined(separator: "\u{1F}")
        ]
    }

    private struct Material: Codable {
        let schemaVersion: Int
        let stableIDs: [String]
        let rawEnumValues: [String]
        let mutationSHA256: String
        let journalSHA256: String
        let evidenceSHA256: String
        let backupIdentitySHA256: String
        let authoredEvidenceSHA256: String
        let productIdentitySHA256: String
        let jurisdictionIdentifier: String
        let historicalEnUSIdentities: [String]
    }

    private static func digest(_ material: Material) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return sha256(try encoder.encode(material))
    }

    /// Uses the same lower-case hexadecimal representation as every durable
    /// V23 mutation, journal, and backup digest. Keeping this helper beside
    /// the C05 audit makes the executable boundary checks independent of a
    /// presentation locale or formatter.
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func isToken(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.contains("\n")
            && !value.contains("\r")
            && !value.contains("\u{1F}")
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64
            && value == value.lowercased()
            && value.allSatisfy { $0.isHexDigit }
    }
}

/// A comparable display fingerprint built only from the six independent V30
/// axes. It deliberately has no canonical IDs, mutation bytes, or evidence.
struct GlobalizationPresentationFingerprintV1: Codable, Equatable, Sendable {
    let appLanguageTag: String
    let formattingLocaleIdentifier: String
    let ianaTimeZoneIdentifier: String
    let calendar: String
    let numberingSystem: String
    let units: String
    let authoredContentLanguage: String
    let reportLanguage: String
    let storefrontCountry: String
    let jurisdictionIdentifier: String

    init(axisSet: GlobalizationAxisSetV1) {
        appLanguageTag = axisSet.appLanguage.rawValue
        formattingLocaleIdentifier = axisSet.formatting.localeIdentifier
        ianaTimeZoneIdentifier = axisSet.formatting.ianaTimeZoneIdentifier
        calendar = axisSet.formatting.calendar.rawValue
        numberingSystem = axisSet.formatting.numberingSystem.rawValue
        units = axisSet.formatting.units.rawValue
        switch axisSet.authoredContentLanguage {
        case let .known(value): authoredContentLanguage = value
        case .unknown: authoredContentLanguage = "unknown"
        }
        let report = axisSet.reportLanguage
        reportLanguage = "\(report.requestedLanguage.rawValue)|\(report.effectiveLanguage.rawValue)|\(report.fallback.rawValue)"
        storefrontCountry = axisSet.storefrontCountry.rawValue
        jurisdictionIdentifier = axisSet.projectJurisdiction.stableIdentifier
    }

    var displayKey: String {
        [
            appLanguageTag,
            formattingLocaleIdentifier,
            ianaTimeZoneIdentifier,
            calendar,
            numberingSystem,
            units,
            authoredContentLanguage,
            reportLanguage,
            storefrontCountry,
            jurisdictionIdentifier
        ].joined(separator: "\u{1F}")
    }
}

struct CanonicalIdentityComparisonV1: Codable, Equatable, Sendable {
    let presentationChanged: Bool
    let canonicalIdentityUnchanged: Bool
    let historicalEnUSIdentityPreserved: Bool
    let changedCanonicalFields: [String]
}

struct CanonicalIdentityBaselineFixtureV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let baseline: CanonicalIdentitySnapshotV1
    let localized: CanonicalIdentitySnapshotV1
    let beforePresentation: GlobalizationPresentationFingerprintV1
    let afterPresentation: GlobalizationPresentationFingerprintV1

    init(
        baseline: CanonicalIdentitySnapshotV1,
        localized: CanonicalIdentitySnapshotV1,
        beforePresentation: GlobalizationPresentationFingerprintV1,
        afterPresentation: GlobalizationPresentationFingerprintV1
    ) {
        schemaVersion = Self.schemaVersion
        self.baseline = baseline
        self.localized = localized
        self.beforePresentation = beforePresentation
        self.afterPresentation = afterPresentation
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw CanonicalIdentityInvarianceFailureV1.invalidSnapshot
        }
        _ = try CanonicalIdentityInvarianceV1.audit(
            baseline: baseline,
            localized: localized,
            beforePresentation: beforePresentation,
            afterPresentation: afterPresentation
        )
    }
}

enum CanonicalIdentityInvarianceV1 {
    static func audit(_ fixture: CanonicalIdentityBaselineFixtureV1) throws -> CanonicalIdentityComparisonV1 {
        try audit(
            baseline: fixture.baseline,
            localized: fixture.localized,
            beforePresentation: fixture.beforePresentation,
            afterPresentation: fixture.afterPresentation
        )
    }

    static func audit(
        baseline: CanonicalIdentitySnapshotV1,
        localized: CanonicalIdentitySnapshotV1,
        beforePresentation: GlobalizationPresentationFingerprintV1,
        afterPresentation: GlobalizationPresentationFingerprintV1
    ) throws -> CanonicalIdentityComparisonV1 {
        try baseline.validate()
        try localized.validate()
        guard beforePresentation.displayKey != afterPresentation.displayKey else {
            throw CanonicalIdentityInvarianceFailureV1.presentationDidNotChange
        }

        let changed = baseline.canonicalFields.keys.sorted().filter {
            baseline.canonicalFields[$0] != localized.canonicalFields[$0]
        }
        guard changed.isEmpty else {
            throw CanonicalIdentityInvarianceFailureV1.canonicalIdentityChanged(changed)
        }
        guard baseline.historicalEnUSIdentities == localized.historicalEnUSIdentities else {
            throw CanonicalIdentityInvarianceFailureV1.historicalIdentityChanged
        }
        return CanonicalIdentityComparisonV1(
            presentationChanged: true,
            canonicalIdentityUnchanged: true,
            historicalEnUSIdentityPreserved: true,
            changedCanonicalFields: []
        )
    }

    static func validateDeclaredSeams() throws {
        guard V30P01C05SettingsCanonicalIdentityBoundaryV1.validate(),
              V30P01C05ChangeJournalCanonicalIdentityBoundaryV1.validate(),
              V30P01C05MutationJournalCanonicalIdentityBoundaryV1.validate(),
              V30P01C05LocalChangeJournalCanonicalIdentityBoundaryV1.validate(),
              V30P01C05WorkspaceWriterCanonicalIdentityBoundaryV1.validate(),
              V30P01C05BackupRecordsCanonicalIdentityBoundaryV1.validate(),
              V30P01C05BackupEncoderCanonicalIdentityBoundaryV1.validate(),
              V30P01C05BackupDecoderCanonicalIdentityBoundaryV1.validate(),
              V30P01C05BackupPackageCanonicalIdentityBoundaryV1.validate(),
              V30P01C05BackupRestoreCanonicalIdentityBoundaryV1.validate(),
              V30BackupGlobalizationBoundaryV1.validate(),
              !GlobalizationCanonicalIdentityBoundaryV1.languageOrFormattingChangesCanonicalIdentity,
              !GlobalizationCanonicalIdentityBoundaryV1.backupIncludesAxisPreferences,
              !GlobalizationCanonicalIdentityBoundaryV1.rawEnumValuesLocalized else {
            throw CanonicalIdentityInvarianceFailureV1.seamBoundaryViolation
        }
        try GlobalizationCanonicalIdentityBoundaryV1.validateNoCanonicalIdentityMutation([])
    }
}

// MARK: - Executable C05 canonical boundaries

extension GlobalizationDevicePreferenceV1 {
    /// The preference is validated as device-local presentation data and is
    /// never admitted as a canonical/workspace identity input.
    static func validateC05CanonicalIdentityBoundary(
        _ value: GlobalizationPresentationPreferenceV1
    ) throws {
        try value.validate()
        let descriptor = try descriptor()
        guard descriptor.scope == .deviceLocal,
              descriptor.backup == .excludedDeviceLocal,
              !descriptor.changesHistoricOutput,
              try CompatibilityCanonicalV1.encode(value).count
                <= descriptor.maximumCanonicalBytes else {
            throw CanonicalIdentityInvarianceFailureV1.seamBoundaryViolation
        }
    }
}

extension CanonicalIdentityInvarianceV1 {
    /// Checks an encoded canonical payload against its declared digest at the
    /// same boundary where a backup or journal writer would publish bytes.
    static func validateCanonicalBytes(
        _ data: Data,
        declaredSHA256: String
    ) throws {
        guard declaredSHA256.count == 64,
              declaredSHA256 == declaredSHA256.lowercased(),
              declaredSHA256.allSatisfy({ $0.isHexDigit }),
              sha256(data) == declaredSHA256 else {
            throw CanonicalIdentityInvarianceFailureV1.invalidDigest
        }
    }
}

extension V30P01C05BackupEncoderCanonicalIdentityBoundaryV1 {
    static func validateEncodedBytes(
        _ data: Data,
        declaredSHA256: String
    ) throws {
        try CanonicalIdentityInvarianceV1.validateCanonicalBytes(
            data,
            declaredSHA256: declaredSHA256
        )
    }
}

extension V30P01C05BackupDecoderCanonicalIdentityBoundaryV1 {
    static func validateCanonicalRoundTrip(
        source: Data,
        canonical: Data
    ) throws {
        guard source == canonical else {
            throw BackupCanonicalDecodingErrorV1.invalidRecords
        }
        _ = CanonicalIdentityInvarianceV1.sha256(canonical)
    }
}

extension V30P01C05MutationJournalCanonicalIdentityBoundaryV1 {
    static func validateCanonicalCommit(_ envelope: MutationEnvelopeV1) throws {
        do {
            try envelope.validate()
            let data = try envelope.canonicalData()
            guard try MutationEnvelopeV1.decodeCanonical(from: data) == envelope else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        } catch let failure as WorkspaceMutationFailureV1 {
            throw failure
        } catch {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    static func validateCanonicalReceipt(_ receipt: MutationReceiptV1) throws {
        do {
            try receipt.validate()
            let data = try receipt.canonicalData()
            guard try MutationReceiptV1.decodeCanonical(from: data) == receipt else {
                throw WorkspaceMutationFailureV1.invalidReceipt
            }
        } catch let failure as WorkspaceMutationFailureV1 {
            throw failure
        } catch {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
    }
}

extension V30P01C05LocalChangeJournalCanonicalIdentityBoundaryV1 {
    static func validateCanonicalBatch(
        _ batch: ChangeBatchV1,
        limits: ChangeJournalLimitsV1
    ) throws {
        do {
            try batch.validate(limits: limits)
            let data = try batch.canonicalData(limits: limits)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let decoded = try decoder.decode(ChangeBatchV1.self, from: data)
            guard decoded == batch else {
                throw ChangeJournalFailureV1.tamperedBatch
            }
        } catch let failure as ChangeJournalFailureV1 {
            throw failure
        } catch {
            throw ChangeJournalFailureV1.tamperedBatch
        }
    }
}

extension V30P01C05WorkspaceWriterCanonicalIdentityBoundaryV1 {
    static func validateCanonicalCommand(_ command: WorkspaceCommandV1) throws {
        do {
            let data = try WorkspaceMutationCanonicalV1.data(command)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let decoded = try decoder.decode(WorkspaceCommandV1.self, from: data)
            guard decoded == command else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        } catch let failure as WorkspaceMutationFailureV1 {
            throw failure
        } catch {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }
}

extension V30P01C05BackupPackageCanonicalIdentityBoundaryV1 {
    static func validateCanonicalPackage(
        _ package: ValidatedV4BackupPackageV1
    ) throws {
        do {
            let encoded = try BackupCanonicalEncoderV1().encodeRecords(package.records)
            try validateEncodedBytes(
                encoded.data,
                declaredSHA256: encoded.sha256
            )
            let decoded = try BackupCanonicalDecoderV1().decodeRecords(encoded.data)
            guard decoded == package.records else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
        } catch let failure as BackupPackageValidationErrorV1 {
            throw failure
        } catch {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
    }
}

extension V30P01C05BackupRestoreCanonicalIdentityBoundaryV1 {
    static func validateCanonicalRecords(_ records: V4BackupRecordsV1) throws {
        do {
            let encoded = try BackupCanonicalEncoderV1().encodeRecords(records)
            try CanonicalIdentityInvarianceV1.validateCanonicalBytes(
                encoded.data,
                declaredSHA256: encoded.sha256
            )
            let decoded = try BackupCanonicalDecoderV1().decodeRecords(encoded.data)
            guard decoded == records else {
                throw BackupRestoreServiceError.invalidPackage
            }
        } catch let failure as BackupRestoreServiceError {
            throw failure
        } catch {
            throw BackupRestoreServiceError.invalidPackage
        }
    }
}
