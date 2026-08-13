import CryptoKit
import Foundation
import SwiftData

enum ReportRenderServiceError: Error, Equatable {
    case invalidGeneration
    case reportNotFound
    case reportNotPending
    case contextHasChanges
    case invalidStorageAuthority
    case writeFailed
    case bytesMismatch
    case saveFailed
    case cleanupFailed
}

struct ReportRenderResult: Equatable, Sendable {
    let reportID: UUID
    let pdfRelativePath: String
    let pdfSHA256: String
    let pageCount: Int
}

@MainActor
final class ReportRenderService {
    private let modelContext: ModelContext
    private let generationRootURL: URL
    private let storagePreflight: StoragePreflightService
    private let fileManager: FileManager
    private let validator: SnapshotValidatorV1
    private let renderer: WorklightPDFRendererV1

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        fileManager: FileManager = .default,
        signPack: SignPack = .illuminatedSignV1
    ) throws {
        let root = generationRootURL.standardizedFileURL
        guard root.deletingLastPathComponent().lastPathComponent == "generations",
              root.deletingLastPathComponent().deletingLastPathComponent()
                .lastPathComponent == "FieldEvidenceData",
              let generationID = UUID(uuidString: root.lastPathComponent),
              generationID.uuidString.lowercased() == root.lastPathComponent,
              try Self.itemType(at: root, fileManager: fileManager) == .typeDirectory,
              !Self.isSymbolicLink(root, fileManager: fileManager) else {
            throw ReportRenderServiceError.invalidGeneration
        }
        self.modelContext = modelContext
        self.generationRootURL = root
        self.storagePreflight = storagePreflight
        self.fileManager = fileManager
        self.validator = try SnapshotValidatorV1(
            modelContext: modelContext,
            generationRootURL: root,
            fileManager: fileManager,
            signPack: signPack
        )
        self.renderer = WorklightPDFRendererV1()
    }

    func renderPendingReport(id reportID: UUID) throws -> ReportRenderResult {
        guard !modelContext.hasChanges else {
            throw ReportRenderServiceError.contextHasChanges
        }
        let reports = try modelContext.fetch(FetchDescriptor<Report>()).filter {
            $0.id == reportID
        }
        guard reports.count == 1 else {
            throw reports.isEmpty
                ? ReportRenderServiceError.reportNotFound
                : ReportRenderServiceError.invalidStorageAuthority
        }
        let report = reports[0]
        guard report.pdfState == ReportPDFState.pending.rawValue,
              report.pdfRelativePath == nil,
              report.pdfSHA256 == nil else {
            throw ReportRenderServiceError.reportNotPending
        }

        let validated = try validator.validate(report: report)
        try storagePreflight.checkPDFGeneration(
            referencedImageByteCount: validated.referencedImageByteCount,
            onVolumeContaining: generationRootURL
        )
        let rendered = try renderer.render(validated)
        guard !rendered.data.isEmpty,
              rendered.pageCount > 0,
              Self.isLowercaseSHA256(rendered.sha256),
              Self.sha256(rendered.data) == rendered.sha256 else {
            throw ReportRenderServiceError.bytesMismatch
        }
        let paths = try preparePaths(for: reportID)
        var ownsStage = false
        var ownsFinal = false
        do {
            do {
                try rendered.data.write(
                    to: paths.stageURL,
                    options: .withoutOverwriting
                )
            } catch {
                throw ReportRenderServiceError.writeFailed
            }
            ownsStage = true
            try verify(
                paths.stageURL,
                expectedData: rendered.data,
                expectedSHA256: rendered.sha256
            )
            do {
                try fileManager.moveItem(at: paths.stageURL, to: paths.finalURL)
            } catch {
                throw ReportRenderServiceError.writeFailed
            }
            ownsStage = false
            ownsFinal = true
            try verify(
                paths.finalURL,
                expectedData: rendered.data,
                expectedSHA256: rendered.sha256
            )

            report.pdfState = ReportPDFState.ready.rawValue
            report.pdfRelativePath = paths.finalRelativePath
            report.pdfSHA256 = rendered.sha256
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                do {
                    try removeOwned(
                        paths.finalURL,
                        expectedData: rendered.data,
                        expectedSHA256: rendered.sha256
                    )
                } catch {
                    throw ReportRenderServiceError.cleanupFailed
                }
                ownsFinal = false
                throw ReportRenderServiceError.saveFailed
            }
            ownsFinal = false
            return ReportRenderResult(
                reportID: report.id,
                pdfRelativePath: paths.finalRelativePath,
                pdfSHA256: rendered.sha256,
                pageCount: rendered.pageCount
            )
        } catch {
            do {
                if ownsStage {
                    try removeOwned(
                        paths.stageURL,
                        expectedData: rendered.data,
                        expectedSHA256: rendered.sha256
                    )
                }
                if ownsFinal {
                    try removeOwned(
                        paths.finalURL,
                        expectedData: rendered.data,
                        expectedSHA256: rendered.sha256
                    )
                }
            } catch {
                throw ReportRenderServiceError.cleanupFailed
            }
            throw error
        }
    }

    private struct Paths {
        let stageURL: URL
        let finalURL: URL
        let finalRelativePath: String
    }

    private func preparePaths(for reportID: UUID) throws -> Paths {
        let canonicalID = reportID.uuidString.lowercased()
        let stagingRoot = generationRootURL.appendingPathComponent(
            ".staging",
            isDirectory: true
        )
        let stagingPDFsRoot = stagingRoot.appendingPathComponent(
            "pdfs",
            isDirectory: true
        )
        let pdfsRoot = generationRootURL.appendingPathComponent(
            "pdfs",
            isDirectory: true
        )
        try ensureDirectory(stagingRoot)
        try ensureDirectory(stagingPDFsRoot)
        try ensureDirectory(pdfsRoot)

        let stageURL = stagingPDFsRoot.appendingPathComponent(
            "\(canonicalID).pdf",
            isDirectory: false
        )
        let finalRelativePath = "pdfs/\(canonicalID).pdf"
        let finalURL = generationRootURL.appendingPathComponent(finalRelativePath)
        guard try Self.itemType(at: stageURL, fileManager: fileManager) == nil,
              try Self.itemType(at: finalURL, fileManager: fileManager) == nil else {
            throw ReportRenderServiceError.invalidStorageAuthority
        }
        return Paths(
            stageURL: stageURL,
            finalURL: finalURL,
            finalRelativePath: finalRelativePath
        )
    }

    private func ensureDirectory(_ url: URL) throws {
        switch try Self.itemType(at: url, fileManager: fileManager) {
        case nil:
            do {
                try fileManager.createDirectory(
                    at: url,
                    withIntermediateDirectories: false
                )
            } catch {
                throw ReportRenderServiceError.writeFailed
            }
        case .some(.typeDirectory):
            guard !Self.isSymbolicLink(url, fileManager: fileManager) else {
                throw ReportRenderServiceError.invalidStorageAuthority
            }
        case .some:
            throw ReportRenderServiceError.invalidStorageAuthority
        }
    }

    private func verify(
        _ url: URL,
        expectedData: Data,
        expectedSHA256: String
    ) throws {
        guard try Self.itemType(at: url, fileManager: fileManager) == .typeRegular,
              !Self.isSymbolicLink(url, fileManager: fileManager) else {
            throw ReportRenderServiceError.invalidStorageAuthority
        }
        let bytes: Data
        do {
            bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ReportRenderServiceError.writeFailed
        }
        guard bytes == expectedData,
              Self.sha256(bytes) == expectedSHA256 else {
            throw ReportRenderServiceError.bytesMismatch
        }
    }

    private func removeOwned(
        _ url: URL,
        expectedData: Data,
        expectedSHA256: String
    ) throws {
        guard try Self.itemType(at: url, fileManager: fileManager) != nil else { return }
        try verify(
            url,
            expectedData: expectedData,
            expectedSHA256: expectedSHA256
        )
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw ReportRenderServiceError.writeFailed
        }
    }

    private static func itemType(
        at url: URL,
        fileManager: FileManager
    ) throws -> FileAttributeType? {
        do {
            return try fileManager.attributesOfItem(atPath: url.path)[.type]
                as? FileAttributeType
        } catch let error as CocoaError where
            error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw ReportRenderServiceError.invalidStorageAuthority
        }
    }

    private static func isSymbolicLink(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
