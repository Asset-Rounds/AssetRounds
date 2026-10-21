import Foundation

/// An immutable snapshot produced only by the real package validator. The
/// ordinary validated-package value has a module-visible memberwise initializer
/// and is therefore not, by itself, evidence that validation ran.
struct ValidatedRepetitiveCaptureSourcePackageV2: Equatable, Sendable {
    let validatedPackage: ValidatedV4BackupPackageV1
    let manifestJSONSHA256: String
    let recordsJSONSHA256: String

    var source: V4BackupSourceV1 { validatedPackage.manifest.source }
    var records: V4BackupRecordsV1 { validatedPackage.records }

    private init(validatedPackage: ValidatedV4BackupPackageV1,
                 manifestJSONSHA256: String, recordsJSONSHA256: String) {
        self.validatedPackage = validatedPackage
        self.manifestJSONSHA256 = manifestJSONSHA256
        self.recordsJSONSHA256 = recordsJSONSHA256
    }

    static func validate(
        stagedPackageURL: URL,
        using validator: BackupPackageValidatorV1,
        cancellation: StreamingArchiveCancellationV1 = .none
    ) throws -> Self {
        let validation = try validator.validateWithCanonicalFacts(
            stagedPackageURL: stagedPackageURL, cancellation: cancellation)
        let package = validation.package
        try cancellation.checkpoint()
        let entries = package.manifest.entries.filter { $0.path == "records.json" }
        guard package.manifest.source.workspaceID != nil,
              package.records.mutationHistory != nil,
              package.manifest.source.recordsSchemaVersion == package.records.recordsSchemaVersion,
              entries.count == 1, let entry = entries.first,
              let manifestDescriptor = package.members.descriptors["manifest.json"],
              let recordsDescriptor = package.members.descriptors["records.json"] else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        // Bind the complete returned values to the bytes validated by the
        // package boundary; no caller-selected subset can enter this capability.
        let encoder = BackupCanonicalEncoderV1()
        let manifest = try encoder.encodeManifest(package.manifest)
        guard let records = validation.recordsFacts.descriptor(matching: package.records),
              manifest.sha256 == manifestDescriptor.sha256,
              Int64(manifest.data.count) == manifestDescriptor.byteCount,
              records.sha256 == entry.sha256,
              records.byteCount == entry.byteCount,
              records.sha256 == recordsDescriptor.sha256,
              Int64(records.byteCount) == recordsDescriptor.byteCount else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        if package.manifest.backupSchemaVersion == BackupRawDataWireV1.backupSchemaVersion {
            guard validation.recordsFacts.wireFormat == .rawDataV1,
                  let raw = validation.recordsFacts.rawDescriptor(matching: package.records),
                  let descriptor = package.members.descriptors[BackupRawDataWireV1.rawPath],
                  let entry = package.manifest.entries.first(where: { $0.path == BackupRawDataWireV1.rawPath }),
                  raw.sha256 == descriptor.sha256, Int64(raw.byteCount) == descriptor.byteCount,
                  raw.sha256 == entry.sha256, raw.byteCount == entry.byteCount else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
        } else {
            guard validation.recordsFacts.wireFormat == .legacyJSON else {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
        }
        try cancellation.checkpoint()
        return Self(validatedPackage: package,
                    manifestJSONSHA256: manifest.sha256,
                    recordsJSONSHA256: records.sha256)
    }
}
