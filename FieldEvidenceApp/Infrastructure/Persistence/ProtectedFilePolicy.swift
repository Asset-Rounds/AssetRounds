import Darwin
import Foundation

enum EvidenceContextProtectedFilePolicyV1{static let durableRowNames:Set<String>=["EvidenceContextRow","PairedObservationLinkRow"];static let ownsExternalFiles=false;static let canonicalBytesRemainInProtectedDatabase=true}
enum LightingProtectedFilePolicyV1{static let durableRowNames:Set<String>=["LightingSystemRow","LightingObservationRow","LightingIssueRow","MeasurementPlanRow","LightingClaimStateRow"];static let ownsExternalFiles=false;static let canonicalBytesRemainInProtectedDatabase=true}
enum TemporalEvidenceProtectedFilePolicyV1 {
    static let durableRowNames: Set<String> = ["TemporalEvidenceClipRow", "TimecodedEvidenceAnchorRow"]
    static let originalContentFileKind: OwnedFileKindV1 = .mediaOriginal
    static let originalBytesAreCanonicalAndIncludedInBackup = true
    static let derivativesRemainRegenerable = true

    static func validate() throws {
        guard durableRowNames == Set(TemporalEvidencePersistenceEnrollmentV1.persistentFamilies),
              !ProtectedFilePolicyV1.isExcludedFromBackup(for: originalContentFileKind),
              originalBytesAreCanonicalAndIncludedInBackup,
              derivativesRemainRegenerable else {
            throw ProtectedFilePolicyError.invalidType
        }
    }
}

/// The closed set of app-owned file classes that may be passed to the
/// persistence protection policy.  Keeping this list closed prevents a new
/// writer from silently inheriting the wrong backup disposition.
enum OwnedFileKindV1: String, CaseIterable, Equatable, Hashable, Sendable {
    case durableDirectory
    case stagingDirectory
    case restoreStaging
    case stagingFile
    case fieldDraftStagingFile
    case temporaryFile
    case database
    case databaseWAL
    case databaseSHM
    case generationPointer
    case generationPointerTemporary
    case generationLeaseDirectory
    case generationLeaseControl
    case generationLeaseControlTemporary
    case generationLeaseOwnerLock
    case journal
    case journalTemporary
    case mediaOriginal
    case mediaThumbnail
    case reportSnapshot
    case reportPDF
    case diagnostics
    case commerceEntitlementCache
    case cache
    case scratch
    case searchIndex
}

enum PlanProtectedFileBoundaryV1 {
    static let ownsExternalFiles = false
    static let canonicalRowsUseProtectedDatabase = true
    static let sourceContentRemainsUnderExistingContentAuthority = true
}
enum PlacementPoseProtectedFileBoundaryV1{static let ownsExternalFiles=false;static let durableBytesAreSwiftDataRows=true;static let derivedTipsAreDisposable=true}

struct OwnedFileProtectionDispositionV1: Equatable, Sendable {
    let expectsDirectory: Bool
    let isExcludedFromBackup: Bool
}

enum ProtectedFilePolicyError: Error, Equatable, Sendable {
    case invalidURL
    case invalidRelativePath
    case missing
    case symbolicLink
    case invalidType
    case hardLink
    case identityChanged
    case attributeWriteFailed
    case resourceValueMismatch
    case protectedDataUnavailable
}

/// Applies the one protection/backup policy used by all persistence writers.
///
/// The URL operations are deliberately paired with a caller-supplied
/// descriptor-authority closure.  Descriptor owners can verify their pinned
/// ancestors immediately before and after the URL operation without replacing
/// their existing O_NOFOLLOW/inode checks with path-only authority.
enum ProtectedFilePolicyV1 {
    static let requiredFileProtection: FileProtectionType = .complete

    /// C27 adds database rows only. Locator representations are references,
    /// never authority for creating a new app-owned file class.
    static func validateAssetLocatorPersistencePosture() throws {
        guard disposition(for: .database).isExcludedFromBackup == false,
              disposition(for: .journal).isExcludedFromBackup else {
            throw ProtectedFilePolicyError.resourceValueMismatch
        }
    }
    static func validateSchedulePersistencePosture()throws{guard disposition(for:.database).isExcludedFromBackup == false,disposition(for:.journal).isExcludedFromBackup else{throw ProtectedFilePolicyError.resourceValueMismatch}}

    /// Recoverability verification stages only under the existing disposable
    /// staging policy. The opaque locator never creates a new durable file
    /// class or a second archive/store authority.
    static func protectRecoverabilityVerificationStagingDirectory(
        at url: URL,
        authorityCheck: () throws -> Void = {}
    ) throws {
        try applyAndVerify(.stagingDirectory, at: url, authorityCheck: authorityCheck)
    }

    static func isProtectedDataUnavailable(_ error: Error) -> Bool {
        if let policyError = error as? ProtectedFilePolicyError {
            return policyError == .protectedDataUnavailable
        }
        mapWriteError(error) == .protectedDataUnavailable
    }

    static func isExcludedFromBackup(for kind: OwnedFileKindV1) -> Bool {
        disposition(for: kind).isExcludedFromBackup
    }

    /// Every closed file kind remains part of owned-byte accounting even when
    /// it is excluded from filesystem backup or portable export.
    static func countsTowardOwnedStorage(_ kind: OwnedFileKindV1) -> Bool {
        OwnedFileKindV1.allCases.contains(kind)
    }

    /// Storage pressure is an admission signal, never deletion authority.
    static func permitsAutomaticStoragePressureDeletion(
        _: OwnedFileKindV1
    ) -> Bool {
        false
    }

    static func disposition(
        for kind: OwnedFileKindV1
    ) -> OwnedFileProtectionDispositionV1 {
        switch kind {
        case .durableDirectory,
             .database,
             .databaseWAL,
             .databaseSHM,
             .generationPointer,
             .mediaOriginal,
             .mediaThumbnail,
             .reportSnapshot,
             .reportPDF:
            return OwnedFileProtectionDispositionV1(
                expectsDirectory: kind == .durableDirectory,
                isExcludedFromBackup: false
            )
        case .stagingDirectory,
             .restoreStaging,
             .generationLeaseDirectory,
             .cache,
             .scratch:
            return OwnedFileProtectionDispositionV1(
                expectsDirectory: true,
                isExcludedFromBackup: true
            )
        case .stagingFile,
             .fieldDraftStagingFile,
             .temporaryFile,
             .generationPointerTemporary,
             .generationLeaseControl,
             .generationLeaseControlTemporary,
             .generationLeaseOwnerLock,
             .journal,
             .journalTemporary,
             .diagnostics,
             .commerceEntitlementCache,
             .searchIndex:
            return OwnedFileProtectionDispositionV1(
                expectsDirectory: false,
                isExcludedFromBackup: true
            )
        }
    }

    static func applyAndVerify(
        _ kind: OwnedFileKindV1,
        at url: URL,
        authorityCheck: () throws -> Void = {}
    ) throws {
        let disposition = disposition(for: kind)
        try authorityCheck()
        let before = try pin(kind, at: url, disposition: disposition)

        do {
            try FileManager.default.setAttributes(
                [.protectionKey: requiredFileProtection],
                ofItemAtPath: url.path
            )

            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = disposition.isExcludedFromBackup
            try url.setResourceValues(resourceValues)
        } catch {
            throw mapWriteError(error)
        }

        try authorityCheck()
        let after = try pin(kind, at: url, disposition: disposition)
        guard before == after else {
            throw ProtectedFilePolicyError.identityChanged
        }
        try verifyResourceValues(at: url, disposition: disposition)
        try authorityCheck()
    }

    static func applyAndVerify(
        _ kind: OwnedFileKindV1,
        relativePath: String,
        within rootURL: URL,
        authorityCheck: @escaping () throws -> Void = {}
    ) throws {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("\\"),
              !relativePath.contains("\\") else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }

        let root = rootURL.standardizedFileURL
        guard root.isFileURL else {
            throw ProtectedFilePolicyError.invalidURL
        }
        let disposition = disposition(for: kind)
        let target = root
            .appendingPathComponent(relativePath, isDirectory: disposition.expectsDirectory)
            .standardizedFileURL
        guard isWithin(target: target, root: root) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        let before = try captureOwnedPath(
            kind,
            root: root,
            target: target,
            leafDisposition: disposition
        )
        let guardedAuthorityCheck: () throws -> Void = {
            try authorityCheck()
            let current = try captureOwnedPath(
                kind,
                root: root,
                target: target,
                leafDisposition: disposition
            )
            guard before == current else {
                throw ProtectedFilePolicyError.identityChanged
            }
        }
        try applyAndVerify(
            kind,
            at: target,
            authorityCheck: guardedAuthorityCheck
        )
        let after = try captureOwnedPath(
            kind,
            root: root,
            target: target,
            leafDisposition: disposition
        )
        guard before == after else {
            throw ProtectedFilePolicyError.identityChanged
        }
    }

    static func verify(
        _ kind: OwnedFileKindV1,
        at url: URL
    ) throws {
        let disposition = disposition(for: kind)
        _ = try pin(kind, at: url, disposition: disposition)
        try verifyResourceValues(at: url, disposition: disposition)
    }

    static func verifyIfPresent(
        _ kind: OwnedFileKindV1,
        at url: URL
    ) throws {
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return }
            throw ProtectedFilePolicyError.invalidURL
        }
        try verify(kind, at: url)
    }

    static func verifyIfPresent(
        _ kind: OwnedFileKindV1,
        relativePath: String,
        within rootURL: URL,
        authorityCheck: () throws -> Void = {}
    ) throws {
        guard !relativePath.isEmpty else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        let target = try targetURL(relativePath: relativePath, within: rootURL, kind: kind)
        try validateOwnedAncestors(
            root: rootURL.standardizedFileURL,
            target: target
        )
        try authorityCheck()
        var info = stat()
        guard Darwin.lstat(target.path, &info) == 0 else {
            if errno == ENOENT { return }
            throw ProtectedFilePolicyError.invalidURL
        }
        let before = try captureOwnedPath(
            kind,
            root: rootURL.standardizedFileURL,
            target: target,
            leafDisposition: disposition(for: kind)
        )
        try verify(kind, at: target)
        let after = try captureOwnedPath(
            kind,
            root: rootURL.standardizedFileURL,
            target: target,
            leafDisposition: disposition(for: kind)
        )
        guard before == after else {
            throw ProtectedFilePolicyError.identityChanged
        }
        try authorityCheck()
    }

    private struct LeafIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let linkCount: nlink_t
    }

    private static func pin(
        _ kind: OwnedFileKindV1,
        at url: URL,
        disposition: OwnedFileProtectionDispositionV1
    ) throws -> LeafIdentity {
        guard url.isFileURL else {
            throw ProtectedFilePolicyError.invalidURL
        }

        var inspected = stat()
        guard Darwin.lstat(url.path, &inspected) == 0 else {
            if errno == ENOENT { throw ProtectedFilePolicyError.missing }
            if errno == ELOOP { throw ProtectedFilePolicyError.symbolicLink }
            throw ProtectedFilePolicyError.invalidURL
        }
        let type = inspected.st_mode & S_IFMT
        if type == S_IFLNK {
            throw ProtectedFilePolicyError.symbolicLink
        }
        guard (disposition.expectsDirectory && type == S_IFDIR) ||
              (!disposition.expectsDirectory && type == S_IFREG) else {
            throw ProtectedFilePolicyError.invalidType
        }
        if !disposition.expectsDirectory && inspected.st_nlink != 1 {
            throw ProtectedFilePolicyError.hardLink
        }

        let flags = disposition.expectsDirectory
            ? O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            : O_RDONLY | O_NOFOLLOW
        let descriptor = Darwin.open(url.path, flags)
        guard descriptor >= 0 else {
            if errno == ENOENT { throw ProtectedFilePolicyError.missing }
            if errno == ELOOP { throw ProtectedFilePolicyError.symbolicLink }
            if errno == EACCES || errno == EPERM {
                throw ProtectedFilePolicyError.protectedDataUnavailable
            }
            throw ProtectedFilePolicyError.invalidURL
        }
        defer { _ = Darwin.close(descriptor) }

        var actual = stat()
        guard Darwin.fstat(descriptor, &actual) == 0 else {
            throw ProtectedFilePolicyError.invalidURL
        }
        let actualType = actual.st_mode & S_IFMT
        guard actualType == type else {
            throw ProtectedFilePolicyError.identityChanged
        }
        if !disposition.expectsDirectory && actual.st_nlink != 1 {
            throw ProtectedFilePolicyError.hardLink
        }
        let identity = LeafIdentity(
            device: actual.st_dev,
            inode: actual.st_ino,
            linkCount: actual.st_nlink
        )
        guard identity.device == inspected.st_dev,
              identity.inode == inspected.st_ino,
              identity.linkCount == inspected.st_nlink else {
            throw ProtectedFilePolicyError.identityChanged
        }
        _ = kind
        return identity
    }

    private static func targetURL(
        relativePath: String,
        within rootURL: URL,
        kind: OwnedFileKindV1
    ) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("\\"),
              !relativePath.contains("\\") else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        let root = rootURL.standardizedFileURL
        guard root.isFileURL else { throw ProtectedFilePolicyError.invalidURL }
        let target = root
            .appendingPathComponent(relativePath, isDirectory: disposition(for: kind).expectsDirectory)
            .standardizedFileURL
        guard isWithin(target: target, root: root) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        return target
    }

    private static func isWithin(target: URL, root: URL) -> Bool {
        let targetPath = target.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if rootPath == "/" {
            return targetPath.hasPrefix("/")
        }
        return targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
    }

    private static func captureOwnedPath(
        _ kind: OwnedFileKindV1,
        root: URL,
        target: URL,
        leafDisposition: OwnedFileProtectionDispositionV1
    ) throws -> [LeafIdentity] {
        let root = root.standardizedFileURL
        let target = target.standardizedFileURL
        guard isWithin(target: target, root: root) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        let relative = String(target.path.dropFirst(root.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = relative.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }

        var identities = [try pin(
            .durableDirectory,
            at: root,
            disposition: disposition(for: .durableDirectory)
        )]
        var cursor = root
        for component in components.dropLast() {
            cursor.appendPathComponent(component, isDirectory: true)
            identities.append(try pin(
                .durableDirectory,
                at: cursor,
                disposition: disposition(for: .durableDirectory)
            ))
        }
        identities.append(try pin(kind, at: target, disposition: leafDisposition))
        return identities
    }

    /// Checks only components below the caller-owned root.  System-managed
    /// ancestors (for example /var) are intentionally outside this authority
    /// boundary and are never mutated or rejected here.
    private static func validateOwnedAncestors(root: URL, target: URL) throws {
        let rootPath = root.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        guard isWithin(target: target, root: root) else {
            throw ProtectedFilePolicyError.invalidRelativePath
        }
        var rootInfo = stat()
        guard Darwin.lstat(rootPath, &rootInfo) == 0 else {
            if errno == ENOENT { throw ProtectedFilePolicyError.missing }
            throw ProtectedFilePolicyError.invalidURL
        }
        let rootType = rootInfo.st_mode & S_IFMT
        if rootType == S_IFLNK {
            throw ProtectedFilePolicyError.symbolicLink
        }
        guard rootType == S_IFDIR else {
            throw ProtectedFilePolicyError.invalidType
        }
        let relative = String(targetPath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else { return }
        let components = relative.split(separator: "/").map(String.init)
        guard components.count > 1 else { return }

        var cursor = root
        for component in components.dropLast() {
            cursor.appendPathComponent(component, isDirectory: true)
            var info = stat()
            guard Darwin.lstat(cursor.path, &info) == 0 else {
                if errno == ENOENT { throw ProtectedFilePolicyError.missing }
                throw ProtectedFilePolicyError.invalidURL
            }
            let type = info.st_mode & S_IFMT
            if type == S_IFLNK {
                throw ProtectedFilePolicyError.symbolicLink
            }
            guard type == S_IFDIR else {
                throw ProtectedFilePolicyError.invalidType
            }
        }
    }

    private static func verifyResourceValues(
        at url: URL,
        disposition: OwnedFileProtectionDispositionV1
    ) throws {
        do {
            let values = try url.resourceValues(forKeys: [
                .fileProtectionKey,
                .isExcludedFromBackupKey
            ])
            guard values.fileProtection == .complete,
                  values.isExcludedFromBackup == disposition.isExcludedFromBackup else {
                throw ProtectedFilePolicyError.resourceValueMismatch
            }
        } catch let error as ProtectedFilePolicyError {
            throw error
        } catch {
            throw mapWriteError(error)
        }
    }

    private static func mapWriteError(_ error: Error) -> ProtectedFilePolicyError {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain,
           (nsError.code == EACCES || nsError.code == EPERM) {
            return .protectedDataUnavailable
        }
        if nsError.domain == NSCocoaErrorDomain,
           (nsError.code == CocoaError.Code.fileReadNoPermission.rawValue ||
            nsError.code == CocoaError.Code.fileWriteNoPermission.rawValue) {
            return .protectedDataUnavailable
        }
        return .attributeWriteFailed
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Persistence_ProtectedFilePolicy {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

enum C45AcceptedLabelProtectedFileBoundaryV1 { static let canonicalStoreRequiresCompleteProtection=true;static let leasedOutputScratchIsNotBackupAuthority=true }

enum C46OperationalContactBoundary_21{static let persistentFamilies=OperationalContactPersistenceEnrollmentV1.persistentFamilies;static let platformOutcomesPersistent=false}
