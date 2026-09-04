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
        return SHA256.hash(data: try encoder.encode(material))
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
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
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
