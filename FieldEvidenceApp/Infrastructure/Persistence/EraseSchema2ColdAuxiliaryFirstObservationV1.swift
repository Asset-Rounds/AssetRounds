import Darwin
import CryptoKit
import Foundation

/// Pure topology arithmetic only. Matching these counts grants no authority;
/// actual held/named facts and complete namespaces remain separately checked.
enum EraseDirectoryEntryLinkModelV1 {
    nonisolated static func expectedLinkCount(directEntryCount: Int) -> Int64? {
        guard directEntryCount >= 0,
              let count = Int64(exactly: directEntryCount) else { return nil }
        let links = count.addingReportingOverflow(2)
        return links.overflow ? nil : links.partialValue
    }

    nonisolated static func matches(linkCount: Int64, directEntryCount: Int) -> Bool {
        guard linkCount >= 0,
              let expected = expectedLinkCount(directEntryCount: directEntryCount) else { return false }
        return linkCount == expected
    }

    nonisolated static func linkDelta(beforeDirectEntryCount: Int,
        afterDirectEntryCount: Int) -> Int64? {
        guard let before = expectedLinkCount(directEntryCount: beforeDirectEntryCount),
              let after = expectedLinkCount(directEntryCount: afterDirectEntryCount) else { return nil }
        let delta = after.subtractingReportingOverflow(before)
        return delta.overflow ? nil : delta.partialValue
    }

    nonisolated static func directEntryCount(paths: Set<String>, parentPath: String) -> Int {
        let prefix = parentPath.isEmpty ? "" : parentPath + "/"
        return paths.lazy.filter { path in
            guard path.hasPrefix(prefix) else { return false }
            let entry = path.dropFirst(prefix.count)
            return !entry.isEmpty && !entry.contains("/")
        }.count
    }
}

/// Observation only. These bytes never grant Erase, descriptor, policy or
/// deletion authority. The operation/Manifest owners supply and retain the
/// actual named ancestors, EX and activity exclusion around both scans.
/// The operation must retain this observer before capture, including on error,
/// because its checked IO can retain uncertain-close descriptors.
@MainActor
final class EraseSchema2ColdAuxiliaryFirstObserverV1 {
    struct ParentIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let mode: mode_t
        let user: uid_t
        let group: gid_t
    }

    enum Tree: Equatable {
        case absent
        case present(rootFact: String, digest: String)

        var rootFact: String? {
            guard case .present(let value, _) = self else { return nil }
            return value
        }
    }

    enum OperationsChild: Equatable {
        case directory(rootFact: String, digest: String)
        case regular(fact: String, digest: String)
    }

    struct ControlNode: Equatable {
        let path: String
        let fullFact: String
        let policy: TemporalPolicyObservationV1
        let contentSHA256: String?
    }

    struct Snapshot: Equatable {
        let supportIdentity: ParentIdentity
        let cacheIdentity: ParentIdentity
        let temporaryIdentity: ParentIdentity
        let supportFact: String
        let supportNames: [String]
        let supportTrees: [String: Tree]
        let operations: Tree
        let operationsChildren: [String: OperationsChild]
        let ingressControlNodes: [ControlNode]?
        let notificationControlNodes: [ControlNode]?
        let notificationControlStableDigest: String?
        let cacheTree: Tree
        let temporaryTree: Tree
    }

    private let io = EraseAbortCheckedSnapshotIOV1()
    private var attempted = false
    private var first: Snapshot?
    private var firstScratchImage: ScratchDataLeaseStoreV1.OriginalEraseScratchImageV1?
    private var ingressControlURL: URL?
    private var notificationControlURL: URL?

    /// Borrowed descriptors must not be closed or retained here. The caller
    /// brackets this entire synchronous call with its genuine named-root proof.
    /// Cache/temp sibling activity is outside our ownership: only each parent
    /// identity and the exact FieldEvidenceApp child are observed there.
    func captureFirst(support: Int32, caches: Int32, temporary: Int32,
        applicationSupportURL: URL, retainingOriginalScratchImage: Bool = false
    ) throws -> Snapshot {
        guard !attempted else { throw EraseAllServiceError.invalidAuthority }
        attempted = true
        guard applicationSupportURL.isFileURL else {
            throw EraseAllServiceError.invalidAuthority
        }
        ingressControlURL = applicationSupportURL.standardizedFileURL
            .appendingPathComponent("FieldEvidenceOperations",
                isDirectory: true)
            .appendingPathComponent("ProtectedIngressReceiptsV1",
                isDirectory: true)
        notificationControlURL = applicationSupportURL.standardizedFileURL
            .appendingPathComponent("FieldEvidenceOperations",
                isDirectory: true)
            .appendingPathComponent(AppLockNotificationControlStoreV1.rootName,
                isDirectory: true)
        let one = try observe(support: support, caches: caches, temporary: temporary)
        let two = try observe(support: support, caches: caches, temporary: temporary)
        try io.requireSettled()
        guard one == two else { throw EraseAllServiceError.invalidAuthority }
        if retainingOriginalScratchImage,
           let scratch = one.operationsChildren["ScratchDataV1"],
           case .directory(let rootFact, let digest) = scratch {
            let image = try observeScratchImage(support: support)
            let repeated = try observeScratchImage(support: support)
            guard image == repeated, image.rootFact == rootFact,
                  image.digest == digest else { throw EraseAllServiceError.invalidAuthority }
            firstScratchImage = image
        }
        first = one
        return one
    }

    /// Returns the first complete data image. It does not reobserve, refresh,
    /// approve a replay cut, or turn present filesystem state into authority.
    func firstObservation() throws -> Snapshot {
        try io.requireSettled()
        guard let first else { throw EraseAllServiceError.invalidAuthority }
        return first
    }

    func originalScratchFirstImage() throws -> ScratchDataLeaseStoreV1.OriginalEraseScratchImageV1 {
        _ = try firstObservation()
        guard let firstScratchImage else { throw EraseAllServiceError.invalidAuthority }
        return firstScratchImage
    }

    private func observeScratchImage(support: Int32) throws
        -> ScratchDataLeaseStoreV1.OriginalEraseScratchImageV1 {
        try io.withOpen(parent: support, name: "FieldEvidenceOperations",
            flags: O_RDONLY | O_DIRECTORY) { operations in
            try ScratchDataLeaseStoreV1.observeOriginalEraseScratchImage(
                io: io, operations: operations)
        }
    }

    /// Reproves the immutable first image using the same genuinely held
    /// ancestors. This is data validation only; the caller must bracket the
    /// scan with its operation-bound named-root and exclusion checks.
    func requireUnchanged(support: Int32, caches: Int32, temporary: Int32) throws {
        let expected = try firstObservation()
        let one = try observe(support: support, caches: caches, temporary: temporary)
        let two = try observe(support: support, caches: caches, temporary: temporary)
        try io.requireSettled()
        guard one == expected, two == expected else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    /// Read-only post-Q check after the original parent descriptors have been
    /// checked-closed. The caller supplies the immutable first image and the
    /// exact checked Scratch projection, and holds the same operation's EX/G
    /// plus a named, borrowed Support descriptor around both scans.
    func requirePostPointerOperationsProjected(
        first expected: Snapshot, projected: Snapshot, support: Int32
    ) throws {
        guard try firstObservation() == expected,
              expected.supportIdentity == projected.supportIdentity,
              expected.supportFact == projected.supportFact,
              expected.supportNames == projected.supportNames,
              expected.supportTrees == projected.supportTrees,
              case .present(let firstOperationsFact, _) =
                expected.operations,
              case .present(let projectedOperationsFact, _) =
                projected.operations,
              firstOperationsFact == projectedOperationsFact,
              Set(expected.operationsChildren.keys)
                == Set(projected.operationsChildren.keys) else {
            throw EraseAllServiceError.invalidAuthority
        }
        for (name, child) in expected.operationsChildren
            where name != "ScratchDataV1" {
            guard projected.operationsChildren[name] == child else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        let before = try directoryFact(support)
        guard Self.identity(before) == projected.supportIdentity,
              Self.fullFact(before) == projected.supportFact,
              try io.names(in: support) == projected.supportNames else {
            throw EraseAllServiceError.invalidAuthority
        }
        for _ in 0..<2 {
            let operations = try tree(parent: support,
                name: "FieldEvidenceOperations")
            let children = try childrenOfOperations(parent: support,
                operations: operations)
            guard operations == projected.operations,
                  children.0 == projected.operationsChildren,
                  children.1 == projected.ingressControlNodes,
                  children.2 == projected.notificationControlNodes,
                  children.3 == projected.notificationControlStableDigest,
                  Self.fullFact(try directoryFact(support))
                    == projected.supportFact,
                  try io.names(in: support) == projected.supportNames else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        try io.requireSettled()
    }

    /// Reprove the checked reader→writer→old-close image immediately before
    /// the original notification owner begins its real effect. Search is the
    /// only Support child already changed, and its separate retained writer
    /// must be rechecked by Router on both sides of this borrowed scan.
    func requireOriginalNotificationBefore(
        oldClose: Snapshot,
        searchWasAbsent: Bool,
        support: Int32, caches: Int32, temporary: Int32
    ) throws -> Snapshot {
        let first = try firstObservation()
        func check(_ value: Snapshot) throws {
            let expectedNames = Set(first.supportNames)
                .union(searchWasAbsent
                    ? [LocalSearchIndexStoreV1.directoryName] : [])
            guard value.supportIdentity == first.supportIdentity,
                  value.cacheIdentity == first.cacheIdentity,
                  value.temporaryIdentity == first.temporaryIdentity,
                  Self.sameStableParent(value.supportFact,
                    first.supportFact),
                  Set(value.supportNames) == expectedNames,
                  value.cacheTree == first.cacheTree,
                  value.temporaryTree == first.temporaryTree,
                  value.operations == oldClose.operations,
                  value.operationsChildren == oldClose.operationsChildren,
                  value.ingressControlNodes == oldClose.ingressControlNodes,
                  value.notificationControlNodes == oldClose.notificationControlNodes,
                  value.notificationControlStableDigest
                    == oldClose.notificationControlStableDigest else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (name, tree) in first.supportTrees
                where name != LocalSearchIndexStoreV1.directoryName {
                guard value.supportTrees[name] == tree else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            guard value.supportTrees[LocalSearchIndexStoreV1.directoryName]
                    != .absent else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        let one = try observe(support: support, caches: caches,
            temporary: temporary)
        let two = try observe(support: support, caches: caches,
            temporary: temporary)
        try io.requireSettled()
        try check(one)
        guard two == one else { throw EraseAllServiceError.invalidAuthority }
        return two
    }

    /// Only the notification owner can produce the revocation after OS
    /// absence and checked record removal. This image projects precisely its
    /// A separate creation permit may use this immutable-P classification
    /// only after requireOriginalNotificationBefore has authenticated `before`.
    /// The immutable first observation is never replaced by a created tree.
    func requireOriginalNotificationCreationAdmission(before: Snapshot) throws {
        let first = try firstObservation()
        let name = AppLockNotificationControlStoreV1.rootName
        guard first.operationsChildren[name] == nil,
              first.notificationControlNodes == nil,
              first.notificationControlStableDigest == nil,
              before.operationsChildren[name] == nil,
              before.notificationControlNodes == nil,
              before.notificationControlStableDigest == nil,
              case .present = first.operations,
              case .present = before.operations,
              Self.sameStableParent(first.operations.rootFact,
                  before.operations.rootFact) else {
            throw EraseAllServiceError.invalidAuthority
        }
    }

    /// Read-only bracket while the new Notification root has no policy yet.
    /// The actual mkdir owner supplies its checked held/named parent postfact;
    /// no current survivor tree becomes a new first observation. The outside
    /// digest omits only Operations metadata changed by that named mkdir.
    func requireOriginalNotificationCreationOutsideRoot(
        before: Snapshot, operationsFact: String,
        rootIsPresent: Bool, outsideDigest: String?,
        support: Int32, caches: Int32, temporary: Int32
    ) throws -> String {
        try requireOriginalNotificationCreationAdmission(before: before)
        let name = AppLockNotificationControlStoreV1.rootName
        guard Self.sameStableParent(operationsFact,
                before.operations.rootFact),
              rootIsPresent || operationsFact == before.operations.rootFact else {
            throw EraseAllServiceError.invalidAuthority
        }
        guard let priorFact = before.operations.rootFact else {
            throw EraseAllServiceError.invalidAuthority
        }
        let priorFields = priorFact.split(separator: "|", omittingEmptySubsequences: false)
        let currentFields = operationsFact.split(separator: "|", omittingEmptySubsequences: false)
        guard priorFields.count == 11, currentFields.count == 11,
              let priorLinks = UInt64(priorFields[5]),
              let currentLinks = UInt64(currentFields[5]),
              currentLinks == priorLinks ||
                (rootIsPresent && priorLinks < UInt64.max && currentLinks == priorLinks + 1) else {
            throw EraseAllServiceError.invalidAuthority
        }
        // Some supported filesystems keep directory nlink stable, others add
        // one for this single checked mkdir. Normalize only that proved +1;
        // the complete actual parent postfact remains receipt-bound throughout.
        let normalizedLinks: UInt64? = rootIsPresent && currentLinks != priorLinks
            ? priorLinks : nil
        func scan() throws -> String {
            guard Self.fullFact(try directoryFact(support)) == before.supportFact,
                  try io.names(in: support) == before.supportNames,
                  Self.identity(try directoryFact(caches)) == before.cacheIdentity,
                  Self.identity(try directoryFact(temporary)) == before.temporaryIdentity,
                  try tree(parent: caches, name: "FieldEvidenceApp") == before.cacheTree,
                  try tree(parent: temporary, name: "FieldEvidenceApp") == before.temporaryTree else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (child, expected) in before.supportTrees {
                guard try tree(parent: support, name: child) == expected else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            return try io.withOpen(parent: support,
                name: "FieldEvidenceOperations", flags: O_RDONLY | O_DIRECTORY) { operations in
                func requireParent() throws {
                    var held = stat(), named = stat()
                    let names = Array(before.operationsChildren.keys)
                        + (rootIsPresent ? [name] : [])
                    guard Darwin.fstat(operations, &held) == 0,
                          Darwin.fstatat(support, "FieldEvidenceOperations", &named,
                            AT_SYMLINK_NOFOLLOW) == 0,
                          Self.fullFact(held) == operationsFact,
                          Self.fullFact(named) == operationsFact,
                          try io.names(in: operations) == names.sorted() else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    if !rootIsPresent {
                        var missing = stat()
                        guard Darwin.fstatat(operations, name, &missing,
                            AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
                            throw EraseAllServiceError.invalidAuthority
                        }
                    }
                }
                try requireParent()
                for (child, expected) in before.operationsChildren {
                    switch expected {
                    case .directory(let fact, let digest):
                        guard try tree(parent: operations, name: child)
                            == .present(rootFact: fact, digest: digest) else {
                            throw EraseAllServiceError.invalidAuthority
                        }
                    case .regular:
                        // The complete checked outside digest below includes
                        // every regular child and its exact inode/content.
                        break
                    }
                }
                if let firstIngress = before.ingressControlNodes,
                   let entry = before.operationsChildren["ProtectedIngressReceiptsV1"],
                   case .directory(let fact, let digest) = entry,
                   let ingressControlURL {
                    guard try observeControlNodes(operations: operations,
                        name: "ProtectedIngressReceiptsV1", rootURL: ingressControlURL,
                        notificationControl: false, expectedRootFact: fact,
                        expectedTreeDigest: digest).0 == firstIngress else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
                var nodes: [EraseAbortCheckedSnapshotIOV1.CheckedTreeNode] = []
                let digest = try io.postRetiredTree(parent: support,
                    name: "FieldEvidenceOperations", excluding: [name],
                    ignoringDirectoryMetadata: Set([""]),
                    normalizingSingleTargetManifestRootLinksFrom: normalizedLinks,
                    observeTypedNode: { node, _ in nodes.append(node) })
                for (child, expected) in before.operationsChildren {
                    if case .regular(let fact, let content) = expected {
                        guard let node = nodes.first(where: { $0.path == child }),
                              Self.fullFact(node.fact) == fact,
                              node.sha256 == content else {
                            throw EraseAllServiceError.invalidAuthority
                        }
                    }
                }
                try requireParent()
                return digest
            }
        }
        let one = try scan(), two = try scan()
        try io.requireSettled()
        guard one == two, outsideDigest == nil || outsideDigest == two else {
            throw EraseAllServiceError.invalidAuthority
        }
        return two
    }

    /// Read back the exact checked mkdir/protection/sync/close postimage.
    /// This admits exactly one empty Notification root and its actual parent
    /// metadata transition, retaining every previously proved outside branch.
    func requireOriginalNotificationCreatedPostimage(
        before: Snapshot, operationsFact: String,
        rootFact: String, treeDigest: String, stableDigest: String,
        disposition: ProtectedFileVerificationDispositionV1,
        support: Int32, caches: Int32, temporary: Int32
    ) throws -> Snapshot {
        try requireOriginalNotificationCreationAdmission(before: before)
        let name = AppLockNotificationControlStoreV1.rootName
        func check(_ value: Snapshot) throws {
            guard value.supportIdentity == before.supportIdentity,
                  value.cacheIdentity == before.cacheIdentity,
                  value.temporaryIdentity == before.temporaryIdentity,
                  value.supportFact == before.supportFact,
                  value.supportNames == before.supportNames,
                  value.supportTrees == before.supportTrees,
                  value.cacheTree == before.cacheTree,
                  value.temporaryTree == before.temporaryTree,
                  value.ingressControlNodes == before.ingressControlNodes,
                  value.operations.rootFact == operationsFact,
                  Self.sameStableParent(operationsFact, before.operations.rootFact),
                  Set(value.operationsChildren.keys)
                    == Set(before.operationsChildren.keys).union([name]),
                  value.operationsChildren[name]
                    == .directory(rootFact: rootFact, digest: treeDigest),
                  let nodes = value.notificationControlNodes,
                  nodes.count == 1, let root = nodes.first,
                  root.path.isEmpty, root.contentSHA256 == nil,
                  root.fullFact == rootFact,
                  root.policy.isDirectory == true,
                  root.policy.backupExcluded == true,
                  root.policy.state == .strictComplete ||
                    (disposition == .simulatorFileProtectionUnsupported &&
                     root.policy.state == .pendingSimulatorRequest),
                  value.notificationControlStableDigest == stableDigest else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (child, expected) in before.operationsChildren {
                guard value.operationsChildren[child] == expected else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        let one = try observe(support: support, caches: caches, temporary: temporary)
        let two = try observe(support: support, caches: caches, temporary: temporary)
        try io.requireSettled()
        try check(one)
        guard one == two else { throw EraseAllServiceError.invalidAuthority }
        return two
    }

    private func originalNotificationAnchor(
        creation: OriginalEraseNotificationRootCreationReceiptV1?
    ) throws -> Snapshot {
        guard let creation else { return try firstObservation() }
        try creation.requireObserver(self)
        try requireOriginalNotificationCreationAdmission(before: creation.before)
        return creation.after
    }

    /// one Operations child; all other first-roster branches remain bound.
    func requireOriginalNotificationAfter(
        before: Snapshot,
        revocation: NotificationEraseRevocationV1,
        removal: OriginalEraseNotificationRecordRemovalReceiptV1,
        creation: OriginalEraseNotificationRootCreationReceiptV1? = nil,
        support: Int32, caches: Int32, temporary: Int32
    ) throws -> Snapshot {
        let first = try originalNotificationAnchor(creation: creation)
        guard let old = before.operationsChildren[
                AppLockNotificationControlStoreV1.rootName],
              case .directory(let oldRootFact, _) = old,
              let firstRoot = first.operationsChildren[
                AppLockNotificationControlStoreV1.rootName],
              case .directory(let firstRootFact, _) = firstRoot,
              Self.sameStableParent(oldRootFact, firstRootFact),
              Self.sameRootLinks(oldRootFact, firstRootFact),
              before.notificationControlStableDigest
                == first.notificationControlStableDigest,
              let firstNodes = first.notificationControlNodes,
              let beforeNodes = before.notificationControlNodes,
              firstNodes.count == beforeNodes.count,
              firstNodes.dropFirst() == beforeNodes.dropFirst() else {
            throw EraseAllServiceError.invalidAuthority
        }
        let expectedBytes = try CompatibilityCanonicalV1.encode(revocation)
        func check(_ value: Snapshot) throws {
            guard value.supportIdentity == before.supportIdentity,
                  value.cacheIdentity == before.cacheIdentity,
                  value.temporaryIdentity == before.temporaryIdentity,
                  value.supportFact == before.supportFact,
                  value.supportNames == before.supportNames,
                  value.supportTrees == before.supportTrees,
                  value.cacheTree == before.cacheTree,
                  value.temporaryTree == before.temporaryTree,
                  value.ingressControlNodes == before.ingressControlNodes,
                  value.notificationControlNodes != nil,
                  value.operations.rootFact
                    == before.operations.rootFact,
                  Set(value.operationsChildren.keys)
                    == Set(before.operationsChildren.keys),
                  let notification = value.operationsChildren[
                    AppLockNotificationControlStoreV1.rootName],
                  case .directory(let newRootFact,
                      let newRootDigest) = notification,
                  Self.sameStableParent(newRootFact, oldRootFact),
                  newRootFact == removal.finalRootFact,
                  newRootDigest == removal.finalTreeDigest else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (name, child) in before.operationsChildren
                where name != AppLockNotificationControlStoreV1.rootName {
                guard value.operationsChildren[name] == child else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        let one = try observe(support: support, caches: caches,
            temporary: temporary)
        let two = try observe(support: support, caches: caches,
            temporary: temporary)
        try io.requireSettled()
        try check(one)
        guard two == one else { throw EraseAllServiceError.invalidAuthority }
        try io.withOpen(parent: support,
            name: "FieldEvidenceOperations",
            flags: O_RDONLY | O_DIRECTORY) { operations in
            try io.withOpen(parent: operations,
                name: AppLockNotificationControlStoreV1.rootName,
                flags: O_RDONLY | O_DIRECTORY) { root in
                guard try io.names(in: root)
                        == [AppLockNotificationControlStoreV1.eraseName],
                      try io.control(parent: root,
                        name: AppLockNotificationControlStoreV1.eraseName,
                        maximum: AppLockNotificationControlStoreV1
                            .maximumRecordBytes).0 == expectedBytes else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        let three = try observe(support: support, caches: caches,
            temporary: temporary)
        let four = try observe(support: support, caches: caches,
            temporary: temporary)
        try io.requireSettled()
        guard three == two, four == two else {
            throw EraseAllServiceError.invalidAuthority
        }
        return two
    }

    /// The original Notification root policy request may change only that
    /// root's ctime and checked policy. Its stable tree digest was captured
    /// during the immutable first P observation, before any auxiliary effect.
    /// A caller may open the ctime window only at the actual checked setter
    /// boundary while retaining its one-use original EX/G permit.
    func requireOriginalNotificationRootPolicyBranches(
        before: Snapshot, allowRootCtime: Bool,
        creation: OriginalEraseNotificationRootCreationReceiptV1? = nil,
        support: Int32, caches: Int32, temporary: Int32
    ) throws -> Snapshot {
        let first = try originalNotificationAnchor(creation: creation)
        let name = AppLockNotificationControlStoreV1.rootName
        guard let firstNodes = first.notificationControlNodes,
              let stable = first.notificationControlStableDigest,
              before.notificationControlNodes == firstNodes,
              before.notificationControlStableDigest == stable,
              before.operationsChildren[name]
                == first.operationsChildren[name],
              let firstRoot = firstNodes.first(where: { $0.path.isEmpty }) else {
            throw EraseAllServiceError.invalidAuthority
        }
        func sameExceptCtime(_ lhs: String, _ rhs: String) -> Bool {
            let a = lhs.split(separator: "|", omittingEmptySubsequences: false)
            let b = rhs.split(separator: "|", omittingEmptySubsequences: false)
            return a.count == 11 && b.count == 11 &&
                Array(a.prefix(9)) == Array(b.prefix(9))
        }
        func check(_ value: Snapshot) throws {
            guard value.supportIdentity == before.supportIdentity,
                  value.cacheIdentity == before.cacheIdentity,
                  value.temporaryIdentity == before.temporaryIdentity,
                  value.supportFact == before.supportFact,
                  value.supportNames == before.supportNames,
                  value.cacheTree == before.cacheTree,
                  value.temporaryTree == before.temporaryTree,
                  value.notificationControlStableDigest == stable,
                  value.operations.rootFact == before.operations.rootFact,
                  Set(value.operationsChildren.keys)
                    == Set(before.operationsChildren.keys),
                  let current = value.operationsChildren[name],
                  case .directory(let currentRootFact, _) = current,
                  let old = before.operationsChildren[name],
                  case .directory(let oldRootFact, _) = old,
                  let currentNodes = value.notificationControlNodes,
                  currentNodes.count == firstNodes.count,
                  let root = currentNodes.first(where: { $0.path.isEmpty }),
                  root.fullFact == currentRootFact else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (child, tree) in before.supportTrees
                where child != "FieldEvidenceOperations" {
                guard value.supportTrees[child] == tree else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            for (child, tree) in before.operationsChildren
                where child != name {
                guard value.operationsChildren[child] == tree else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            for (firstNode, currentNode) in zip(firstNodes,
                currentNodes) where !firstNode.path.isEmpty {
                guard currentNode == firstNode else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            if allowRootCtime {
                guard sameExceptCtime(currentRootFact, oldRootFact),
                      sameExceptCtime(root.fullFact,
                          firstRoot.fullFact),
                      root.policy.device == firstRoot.policy.device,
                      root.policy.inode == firstRoot.policy.inode,
                      root.policy.linkCount
                        == firstRoot.policy.linkCount,
                      root.policy.mode == firstRoot.policy.mode,
                      root.policy.backupExcluded
                        == firstRoot.policy.backupExcluded,
                      root.policy.isDirectory == true,
                      root.policy.volumeSupportsProtection
                        == firstRoot.policy.volumeSupportsProtection,
                      root.policy.state == .strictComplete ||
                        root.policy.state == .pendingSimulatorRequest else {
                    throw EraseAllServiceError.invalidAuthority
                }
            } else {
                guard currentRootFact == oldRootFact,
                      root == firstRoot else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        let one = try observe(support: support, caches: caches,
            temporary: temporary)
        let two = try observe(support: support, caches: caches,
            temporary: temporary)
        try io.requireSettled()
        try check(one)
        guard two == one else {
            throw EraseAllServiceError.invalidAuthority
        }
        return two
    }

    /// The marker publisher changes only one leaf inside Notification. This
    /// scan is deliberately independent of Notification child policy while
    /// its O_EXCL leaf is being written. A complete validated policy postimage
    /// must precede the first call; `outsideDigest` is then retained by the
    /// same original operation, never captured from a later survivor tree.
    func requireOriginalNotificationOutsideRoot(
        afterPolicy: Snapshot, originalBefore: Snapshot,
        searchWriter: OriginalEraseAuxiliarySearchWriterV1, searchBytes: Data,
        outsideDigest: String?,
        creation: OriginalEraseNotificationRootCreationReceiptV1? = nil,
        support: Int32, caches: Int32, temporary: Int32
    ) throws -> String {
        let first = try originalNotificationAnchor(creation: creation)
        let immutable = try firstObservation()
        let searchName = LocalSearchIndexStoreV1.directoryName
        let searchWasAbsent = immutable.supportTrees[searchName] == .absent
        let expectedSupportNames = Set(immutable.supportNames)
            .union(searchWasAbsent ? [searchName] : [])
        let name = AppLockNotificationControlStoreV1.rootName
        guard let policyNodes = afterPolicy.notificationControlNodes,
              let firstNodes = first.notificationControlNodes,
              policyNodes.count == firstNodes.count,
              policyNodes.dropFirst() == firstNodes.dropFirst(),
              // This retained image was authenticated by the original-before
              // observer with the actual checked Search writer on both sides.
              // Search's owned creation may change Support metadata/names;
              // its private published receipt fixes the exact postfact below.
              originalBefore.supportIdentity == immutable.supportIdentity,
              originalBefore.cacheIdentity == immutable.cacheIdentity,
              originalBefore.temporaryIdentity == immutable.temporaryIdentity,
              originalBefore.cacheTree == immutable.cacheTree,
              originalBefore.temporaryTree == immutable.temporaryTree,
              Self.sameStableParent(originalBefore.supportFact, immutable.supportFact),
              Set(originalBefore.supportNames) == expectedSupportNames,
              originalBefore.supportFact == searchWriter.projectedSupportFact,
              searchWriter.publishedBytes == searchBytes,
              originalBefore.notificationControlNodes == firstNodes,
              originalBefore.notificationControlStableDigest
                == first.notificationControlStableDigest,
              originalBefore.operationsChildren[name] == first.operationsChildren[name],
              afterPolicy.supportFact == originalBefore.supportFact,
              afterPolicy.supportNames == originalBefore.supportNames,
              afterPolicy.supportIdentity == originalBefore.supportIdentity,
              afterPolicy.cacheIdentity == originalBefore.cacheIdentity,
              afterPolicy.temporaryIdentity == originalBefore.temporaryIdentity,
              afterPolicy.supportTrees == originalBefore.supportTrees,
              afterPolicy.cacheTree == originalBefore.cacheTree,
              afterPolicy.temporaryTree == originalBefore.temporaryTree,
              afterPolicy.ingressControlNodes == originalBefore.ingressControlNodes,
              afterPolicy.operations.rootFact == originalBefore.operations.rootFact,
              Set(afterPolicy.operationsChildren.keys)
                == Set(originalBefore.operationsChildren.keys) else {
            throw EraseAllServiceError.invalidAuthority
        }
        for (child, tree) in originalBefore.operationsChildren where child != name {
            guard afterPolicy.operationsChildren[child] == tree else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        for (child, tree) in immutable.supportTrees where child != searchName {
            guard originalBefore.supportTrees[child] == tree else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        try searchWriter.requirePublished(searchBytes, supportFD: support)
        func scan() throws -> String {
            var heldSupport = stat()
            guard Darwin.fstat(support, &heldSupport) == 0,
                  Self.fullFact(heldSupport) == afterPolicy.supportFact,
                  try io.names(in: support) == afterPolicy.supportNames,
                  Self.identity(try directoryFact(caches))
                    == afterPolicy.cacheIdentity,
                  Self.identity(try directoryFact(temporary))
                    == afterPolicy.temporaryIdentity,
                  try tree(parent: caches, name: "FieldEvidenceApp")
                    == afterPolicy.cacheTree,
                  try tree(parent: temporary, name: "FieldEvidenceApp")
                    == afterPolicy.temporaryTree else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (child, expected) in afterPolicy.supportTrees {
                guard try tree(parent: support, name: child)
                        == expected else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            return try io.withOpen(parent: support,
                name: "FieldEvidenceOperations",
                flags: O_RDONLY | O_DIRECTORY) { operations in
                var held = stat(), named = stat()
                guard Darwin.fstat(operations, &held) == 0,
                      Darwin.fstatat(support,
                          "FieldEvidenceOperations", &named,
                          AT_SYMLINK_NOFOLLOW) == 0,
                      Self.fullFact(held)
                        == afterPolicy.operations.rootFact,
                      Self.fullFact(named)
                        == afterPolicy.operations.rootFact,
                      try io.names(in: operations)
                        == Array(afterPolicy.operationsChildren.keys)
                            .sorted() else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let value = try io.postRetiredTree(parent: support,
                    name: "FieldEvidenceOperations",
                    excluding: [name])
                guard Darwin.fstat(operations, &held) == 0,
                      Darwin.fstatat(support,
                          "FieldEvidenceOperations", &named,
                          AT_SYMLINK_NOFOLLOW) == 0,
                      Self.fullFact(held)
                        == afterPolicy.operations.rootFact,
                      Self.fullFact(named)
                        == afterPolicy.operations.rootFact else {
                    throw EraseAllServiceError.invalidAuthority
                }
                return value
            }
        }
        let one = try scan()
        try searchWriter.requirePublished(searchBytes, supportFD: support)
        let two = try scan()
        try searchWriter.requirePublished(searchBytes, supportFD: support)
        try io.requireSettled()
        guard one == two, outsideDigest == nil || outsideDigest == two else {
            throw EraseAllServiceError.invalidAuthority
        }
        return two
    }

    /// Data-only bracket for one existing ingress-control root policy
    /// request after the original notification receipt. The policy owner
    /// separately proves the exact held/named control root, its complete
    /// descendants and the permitted root-ctime projection. This scan keeps
    /// every other first/projected branch fixed at the notification cut.
    func requireOriginalScratchControlPolicyUnaffectedBranches(
        notificationAfter: Snapshot,
        support: Int32, caches: Int32, temporary: Int32
    ) throws {
        let first = try firstObservation()
        let name = "ProtectedIngressReceiptsV1"
        guard first.operationsChildren[name]
                == notificationAfter.operationsChildren[name],
              first.ingressControlNodes
                == notificationAfter.ingressControlNodes else {
            throw EraseAllServiceError.invalidAuthority
        }
        func check(_ value: Snapshot) throws {
            guard value.supportIdentity == notificationAfter.supportIdentity,
                  value.cacheIdentity == notificationAfter.cacheIdentity,
                  value.temporaryIdentity
                    == notificationAfter.temporaryIdentity,
                  value.supportFact == notificationAfter.supportFact,
                  value.supportNames == notificationAfter.supportNames,
                  Set(value.supportTrees.keys)
                    == Set(notificationAfter.supportTrees.keys),
                  value.cacheTree == notificationAfter.cacheTree,
                  value.temporaryTree == notificationAfter.temporaryTree,
                  value.notificationControlNodes == notificationAfter.notificationControlNodes,
                  value.notificationControlStableDigest
                    == notificationAfter.notificationControlStableDigest,
                  case .present(let currentOperationsFact, _) = value.operations,
                  case .present(let priorOperationsFact, _) = notificationAfter.operations,
                  currentOperationsFact == priorOperationsFact,
                  Set(value.operationsChildren.keys)
                    == Set(notificationAfter.operationsChildren.keys) else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (child, tree) in notificationAfter.supportTrees
                where child != "FieldEvidenceOperations" {
                guard value.supportTrees[child] == tree else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            for (child, tree) in notificationAfter.operationsChildren
                where child != name {
                guard value.operationsChildren[child] == tree else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            if let firstControl = notificationAfter.ingressControlNodes {
                guard value.operationsChildren[name] != nil,
                      let currentControl = value.ingressControlNodes,
                      currentControl.count == firstControl.count else {
                    throw EraseAllServiceError.invalidAuthority
                }
                for (firstNode, currentNode) in zip(firstControl,
                    currentControl) {
                    guard firstNode.path == currentNode.path,
                          firstNode.path.isEmpty ||
                            firstNode == currentNode else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
            } else {
                guard value.operationsChildren[name] == nil,
                      value.ingressControlNodes == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        let one = try observe(support: support, caches: caches,
            temporary: temporary)
        let two = try observe(support: support, caches: caches,
            temporary: temporary)
        try io.requireSettled()
        try check(one)
        guard two == one else { throw EraseAllServiceError.invalidAuthority }
    }

    /// Data-only projection for exact checked original-owner ScratchData
    /// source-read settlements. Every Operations sibling remains the first
    /// physical child; only the existing ScratchData root metadata may advance
    /// through the receipt chain. The caller binds every receipt to its own
    /// operation and retained EX/G before borrowing these descriptors.
    func requireScratchProjected(
        _ receipts: [ScratchDataLeaseStoreV1.OriginalEraseExclusiveSourceReadReceiptV1],
        support: Int32, caches: Int32, temporary: Int32
    ) throws -> Snapshot {
        let expected = try firstObservation()
        guard !receipts.isEmpty,
              case .present(let operationsFact, _) = expected.operations,
              let scratch = expected.operationsChildren["ScratchDataV1"],
              case .directory(let scratchFact, let scratchDigest) = scratch else {
            throw EraseAllServiceError.invalidAuthority
        }
        var priorFact = scratchFact
        var priorDigest = scratchDigest
        var priorImage = try originalScratchFirstImage()
        for receipt in receipts {
            try receipt.requireCheckedSettlement()
            guard receipt.operationsFact == operationsFact,
                  receipt.beforeScratchRootFact == priorFact,
                  receipt.beforeScratchDigest == priorDigest,
                  receipt.beforeScratchImage == priorImage else {
                throw EraseAllServiceError.invalidAuthority
            }
            priorFact = receipt.afterScratchRootFact
            priorDigest = receipt.afterScratchDigest
            priorImage = receipt.afterScratchImage
        }
        func requireProjected(_ value: Snapshot) throws {
            guard value.supportIdentity == expected.supportIdentity,
                  value.cacheIdentity == expected.cacheIdentity,
                  value.temporaryIdentity == expected.temporaryIdentity,
                  value.supportFact == expected.supportFact,
                  value.supportNames == expected.supportNames,
                  value.supportTrees == expected.supportTrees,
                  value.cacheTree == expected.cacheTree,
                  value.temporaryTree == expected.temporaryTree,
                  value.ingressControlNodes == expected.ingressControlNodes,
                  value.notificationControlNodes == expected.notificationControlNodes,
                  value.notificationControlStableDigest
                    == expected.notificationControlStableDigest,
                  case .present(let currentOperationsFact, _) = value.operations,
                  currentOperationsFact == operationsFact,
                  Set(value.operationsChildren.keys) ==
                    Set(expected.operationsChildren.keys),
                  value.operationsChildren["ScratchDataV1"] ==
                    .directory(rootFact: priorFact, digest: priorDigest) else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (name, child) in expected.operationsChildren
                where name != "ScratchDataV1" {
                guard value.operationsChildren[name] == child else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        let one = try observe(support: support,
            caches: caches, temporary: temporary)
        let two = try observe(support: support,
            caches: caches, temporary: temporary)
        try io.requireSettled()
        try requireProjected(one)
        let image = try observeScratchImage(support: support)
        let repeated = try observeScratchImage(support: support)
        try io.requireSettled()
        guard two == one, image == priorImage, repeated == priorImage else {
            throw EraseAllServiceError.invalidAuthority
        }
        return two
    }

    /// Reprove the sealed recovery projection against the immutable original
    /// P image before the first target-reader record. This is called inside
    /// the genuine retained EX/G with the original held parent descriptors.
    func requireOriginalRecoveryReaderStartingImage(
        _ sealed: OriginalRecoveryPostPointerAuxiliaryProjectionV1,
        operation: EraseRouterOperationV1,
        owner: StoreOriginalEraseRecoveryPreOpenOwnerV1,
        support: Int32, caches: Int32, temporary: Int32
    ) throws -> Snapshot {
        let first = try firstObservation()
        let projected = try sealed.requireReaderStartingImage(
            originalP: first, operation: operation, owner: owner,
            support: support)
        guard projected.supportIdentity == first.supportIdentity,
              projected.cacheIdentity == first.cacheIdentity,
              projected.temporaryIdentity == first.temporaryIdentity,
              projected.supportFact == first.supportFact,
              projected.supportNames == first.supportNames,
              projected.supportTrees == first.supportTrees,
              projected.cacheTree == first.cacheTree,
              projected.temporaryTree == first.temporaryTree,
              case .present(let firstOperationsFact, _) = first.operations,
              case .present(let projectedOperationsFact, _) = projected.operations,
              firstOperationsFact == projectedOperationsFact,
              Set(projected.operationsChildren.keys)
                == Set(first.operationsChildren.keys),
              first.operationsChildren["generation-leases"]
                == projected.operationsChildren["generation-leases"] else {
            throw EraseAllServiceError.invalidAuthority
        }
        let firstScratch = first.operationsChildren["ScratchDataV1"]
        let projectedScratch = projected.operationsChildren["ScratchDataV1"]
        if firstScratch == nil {
            guard projectedScratch == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
        } else {
            guard let firstScratch, let projectedScratch,
                  case .directory = firstScratch,
                  case .directory = projectedScratch else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        for (name, child) in first.operationsChildren
            where name != "ScratchDataV1" {
            guard projected.operationsChildren[name] == child else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        let one = try observe(support: support,
            caches: caches, temporary: temporary)
        let two = try observe(support: support,
            caches: caches, temporary: temporary)
        try io.requireSettled()
        guard one == projected, two == projected else {
            throw EraseAllServiceError.invalidAuthority
        }
        return projected
    }

    /// Data-only projection of the original operation's checked target-reader
    /// publication. The caller must first bind the private receipt to its
    /// retained allocation, handle, Registry, EX and actual G effect. No
    /// current tree is used as a new baseline: the receipt's before image
    /// must equal the authenticated P-to-Scratch projected starting image,
    /// and only generation-leases may differ in two complete held-parent rereads.
    func requireOriginalReaderProjected(
        _ projection: OriginalEraseRetainedTargetReaderProjectionV1,
        starting: Snapshot,
        support: Int32, caches: Int32, temporary: Int32
    ) throws -> Snapshot {
        #if DEBUG
        FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=observer.reader-first-enter\n".utf8))
        #endif
        let original = try firstObservation()
        guard projection.checkedSettled,
              starting.supportIdentity == original.supportIdentity,
              starting.cacheIdentity == original.cacheIdentity,
              starting.temporaryIdentity == original.temporaryIdentity,
              starting.supportFact == original.supportFact,
              starting.supportNames == original.supportNames,
              starting.supportTrees == original.supportTrees,
              starting.cacheTree == original.cacheTree,
              starting.temporaryTree == original.temporaryTree,
              starting.operations == .present(
                rootFact: projection.operationsFact,
                digest: projection.firstOperationsDigest),
              starting.operationsChildren["generation-leases"]
                == .directory(
                    rootFact: projection.firstLeaseRootFact,
                    digest: projection.firstLeaseDigest) else {
            throw EraseAllServiceError.invalidAuthority
        }
        #if DEBUG
        FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=observer.reader-first-bound\n".utf8))
        #endif
        func requireProjected(_ value: Snapshot) throws {
            guard value.supportIdentity == starting.supportIdentity,
                  value.cacheIdentity == starting.cacheIdentity,
                  value.temporaryIdentity == starting.temporaryIdentity,
                  value.supportFact == starting.supportFact,
                  value.supportNames == starting.supportNames,
                  value.supportTrees == starting.supportTrees,
                  value.cacheTree == starting.cacheTree,
                  value.temporaryTree == starting.temporaryTree,
                  value.ingressControlNodes == starting.ingressControlNodes,
                  value.notificationControlNodes == starting.notificationControlNodes,
                  value.notificationControlStableDigest
                    == starting.notificationControlStableDigest,
                  value.operations == .present(
                    rootFact: projection.operationsFact,
                    digest: projection.afterOperationsDigest),
                  Set(value.operationsChildren.keys)
                    == Set(starting.operationsChildren.keys),
                  value.operationsChildren["generation-leases"]
                    == .directory(
                        rootFact: projection.afterLeaseRootFact,
                        digest: projection.afterLeaseDigest) else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (name, child) in starting.operationsChildren
                where name != "generation-leases" {
                guard value.operationsChildren[name] == child else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        #if DEBUG
        FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=observer.reader-scan-enter\n".utf8))
        #endif
        let one = try observe(support: support,
            caches: caches, temporary: temporary)
        let two = try observe(support: support,
            caches: caches, temporary: temporary)
        try io.requireSettled()
        try requireProjected(one)
        guard two == one else { throw EraseAllServiceError.invalidAuthority }
        #if DEBUG
        FileHandle.standardError.write(Data("V23_ORIGINAL_READER_DIAG stage=observer.reader-scan-complete\n".utf8))
        #endif
        return two
    }

    /// The checked writer insertion starts from the reader's already
    /// projected Operations image. Only the same generation-leases child may
    /// advance; the checked Scratch projection and all other auxiliary trees
    /// remain exact.
    func requireOriginalWriterProjected(
        reader: OriginalEraseRetainedTargetReaderProjectionV1,
        writer: OriginalEraseRetainedWriterPublicationProjectionV1,
        starting: Snapshot,
        support: Int32, caches: Int32, temporary: Int32
    ) throws -> Snapshot {
        let original = try firstObservation()
        guard starting.supportIdentity == original.supportIdentity,
              starting.supportFact == original.supportFact,
              starting.supportNames == original.supportNames,
              starting.supportTrees == original.supportTrees,
              reader.checkedSettled, writer.checkedSettled,
              starting.operations == .present(
                rootFact: reader.operationsFact,
                digest: reader.firstOperationsDigest),
              starting.operationsChildren["generation-leases"]
                == .directory(rootFact: reader.firstLeaseRootFact,
                    digest: reader.firstLeaseDigest),
              writer.operationsFact == reader.operationsFact,
              writer.firstOperationsDigest
                == reader.afterOperationsDigest,
              writer.firstLeaseRootFact == reader.afterLeaseRootFact,
              writer.firstLeaseDigest == reader.afterLeaseDigest,
              writer.priorTokens == reader.afterTokens else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try requireProjectedOperations(
            first: starting, operationsFact: writer.operationsFact,
            operationsDigest: writer.afterOperationsDigest,
            leaseRootFact: writer.afterLeaseRootFact,
            leaseDigest: writer.afterLeaseDigest,
            support: support, caches: caches, temporary: temporary)
    }

    /// The checked old-writer release starts exactly at the insertion's
    /// projected image, never at whatever target-only tree survives a crash.
    func requireOriginalOldWriterCloseProjected(
        reader: OriginalEraseRetainedTargetReaderProjectionV1,
        writer: OriginalEraseRetainedWriterPublicationProjectionV1,
        release: OriginalEraseRetainedOldWriterReleaseProjectionV1,
        starting: Snapshot,
        support: Int32, caches: Int32, temporary: Int32
    ) throws -> Snapshot {
        let original = try firstObservation()
        guard starting.supportIdentity == original.supportIdentity,
              starting.supportFact == original.supportFact,
              starting.supportNames == original.supportNames,
              starting.supportTrees == original.supportTrees,
              reader.checkedSettled, writer.checkedSettled,
              release.checkedSettled,
              starting.operations == .present(
                rootFact: reader.operationsFact,
                digest: reader.firstOperationsDigest),
              starting.operationsChildren["generation-leases"]
                == .directory(rootFact: reader.firstLeaseRootFact,
                    digest: reader.firstLeaseDigest),
              writer.operationsFact == reader.operationsFact,
              writer.firstOperationsDigest
                == reader.afterOperationsDigest,
              writer.firstLeaseRootFact == reader.afterLeaseRootFact,
              writer.firstLeaseDigest == reader.afterLeaseDigest,
              writer.priorTokens == reader.afterTokens,
              release.operationsFact == writer.operationsFact,
              release.firstOperationsDigest
                == writer.afterOperationsDigest,
              release.firstLeaseRootFact == writer.afterLeaseRootFact,
              release.firstLeaseDigest == writer.afterLeaseDigest,
              release.priorTokens == writer.afterTokens else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try requireProjectedOperations(
            first: starting, operationsFact: release.operationsFact,
            operationsDigest: release.afterOperationsDigest,
            leaseRootFact: release.afterLeaseRootFact,
            leaseDigest: release.afterLeaseDigest,
            support: support, caches: caches, temporary: temporary)
    }

    private func requireProjectedOperations(
        first: Snapshot, operationsFact: String,
        operationsDigest: String,
        leaseRootFact: String, leaseDigest: String,
        support: Int32, caches: Int32, temporary: Int32
    ) throws -> Snapshot {
        func check(_ value: Snapshot) throws {
            guard value.supportIdentity == first.supportIdentity,
                  value.cacheIdentity == first.cacheIdentity,
                  value.temporaryIdentity == first.temporaryIdentity,
                  value.supportFact == first.supportFact,
                  value.supportNames == first.supportNames,
                  value.supportTrees == first.supportTrees,
                  value.cacheTree == first.cacheTree,
                  value.temporaryTree == first.temporaryTree,
                  value.ingressControlNodes == first.ingressControlNodes,
                  value.notificationControlNodes == first.notificationControlNodes,
                  value.notificationControlStableDigest
                    == first.notificationControlStableDigest,
                  value.operations == .present(
                    rootFact: operationsFact, digest: operationsDigest),
                  Set(value.operationsChildren.keys)
                    == Set(first.operationsChildren.keys),
                  value.operationsChildren["generation-leases"]
                    == .directory(rootFact: leaseRootFact,
                        digest: leaseDigest) else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (name, child) in first.operationsChildren
                where name != "generation-leases" {
                guard value.operationsChildren[name] == child else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        let one = try observe(support: support,
            caches: caches, temporary: temporary)
        let two = try observe(support: support,
            caches: caches, temporary: temporary)
        try io.requireSettled()
        try check(one)
        guard two == one else { throw EraseAllServiceError.invalidAuthority }
        return two
    }

    private static func sameStableParent(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        let a = lhs.split(separator: "|", omittingEmptySubsequences: false)
        let b = rhs.split(separator: "|", omittingEmptySubsequences: false)
        return a.count == 11 && b.count == 11
            && Array(a.prefix(5)) == Array(b.prefix(5))
    }

    private static func sameRootLinks(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        let a = lhs.split(separator: "|", omittingEmptySubsequences: false)
        let b = rhs.split(separator: "|", omittingEmptySubsequences: false)
        return a.count == 11 && b.count == 11 && a[5] == b[5]
    }

    private func observe(support: Int32, caches: Int32, temporary: Int32) throws -> Snapshot {
        try io.requireSettled()
        let supportBefore = try directoryFact(support)
        let cacheBefore = try directoryFact(caches)
        let temporaryBefore = try directoryFact(temporary)
        let names = try io.names(in: support)
        let targets = [
            "FieldEvidenceRestore", "FieldEvidenceCommerce", "FieldEvidenceDiagnostics",
            LocalSearchIndexStoreV1.directoryName,
            PortableExchangeSessionStoreLayoutV2.directoryName,
            LocalJobStoreSchemaV1.directoryName
        ]
        let assigned = Set(targets).union([
            "FieldEvidenceData", "FieldEvidenceErase", "FieldEvidenceOperations"
        ])
        guard Set(names).isSubset(of: assigned) else {
            throw EraseAllServiceError.invalidAuthority
        }
        var trees: [String: Tree] = [:]
        for name in targets { trees[name] = try tree(parent: support, name: name) }
        let operations = try tree(parent: support, name: "FieldEvidenceOperations")
        let (operationsChildren, ingressControlNodes,
             notificationControlNodes,
             notificationControlStableDigest) = try childrenOfOperations(
            parent: support, operations: operations)
        guard try tree(parent: support, name: "FieldEvidenceOperations")
                == operations else {
            throw EraseAllServiceError.invalidAuthority
        }
        let cacheTree = try tree(parent: caches, name: "FieldEvidenceApp")
        let temporaryTree = try tree(parent: temporary, name: "FieldEvidenceApp")
        guard try io.names(in: support) == names,
              Self.fullFact(try directoryFact(support)) == Self.fullFact(supportBefore),
              Self.identity(try directoryFact(caches)) == Self.identity(cacheBefore),
              Self.identity(try directoryFact(temporary)) == Self.identity(temporaryBefore) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try io.requireSettled()
        return Snapshot(supportIdentity: Self.identity(supportBefore),
            cacheIdentity: Self.identity(cacheBefore),
            temporaryIdentity: Self.identity(temporaryBefore),
            supportFact: Self.fullFact(supportBefore), supportNames: names,
            supportTrees: trees, operations: operations,
            operationsChildren: operationsChildren,
            ingressControlNodes: ingressControlNodes,
            notificationControlNodes: notificationControlNodes,
            notificationControlStableDigest: notificationControlStableDigest,
            cacheTree: cacheTree, temporaryTree: temporaryTree)
    }

    private func childrenOfOperations(parent: Int32, operations: Tree)
        throws -> ([String: OperationsChild], [ControlNode]?,
            [ControlNode]?, String?) {
        if operations == .absent { return ([:], nil, nil, nil) }
        return try io.withOpen(parent: parent, name: "FieldEvidenceOperations",
            flags: O_RDONLY | O_DIRECTORY) { directory in
            var held = stat(), named = stat()
            guard Darwin.fstat(directory, &held) == 0,
                  Darwin.fstatat(parent, "FieldEvidenceOperations",
                    &named, AT_SYMLINK_NOFOLLOW) == 0,
                  Self.fullFact(held) == Self.fullFact(named),
                  case .present(let rootFact, _) = operations,
                  Self.fullFact(held) == rootFact else {
                throw EraseAllServiceError.invalidAuthority
            }
            let names = try io.names(in: directory)
            var children: [String: OperationsChild] = [:]
            var controlNodes: [ControlNode]?
            var notificationNodes: [ControlNode]?
            var notificationStableDigest: String?
            for name in names {
                var initial = stat()
                guard Darwin.fstatat(directory, name, &initial,
                        AT_SYMLINK_NOFOLLOW) == 0 else {
                    throw EraseAllServiceError.invalidAuthority
                }
                if initial.st_mode & S_IFMT == S_IFDIR {
                    guard case .present(let fact, let digest) =
                            try tree(parent: directory, name: name) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    children[name] = .directory(rootFact: fact, digest: digest)
                    if name == "ProtectedIngressReceiptsV1" {
                        guard let ingressControlURL else {
                            throw EraseAllServiceError.invalidAuthority
                        }
                        controlNodes = try observeControlNodes(
                            operations: directory,
                            name: name, rootURL: ingressControlURL,
                            notificationControl: false,
                            expectedRootFact: fact,
                            expectedTreeDigest: digest).0
                    } else if name == AppLockNotificationControlStoreV1.rootName {
                        guard let notificationControlURL else {
                            throw EraseAllServiceError.invalidAuthority
                        }
                        let captured = try observeControlNodes(
                            operations: directory,
                            name: name, rootURL: notificationControlURL,
                            notificationControl: true,
                            expectedRootFact: fact,
                            expectedTreeDigest: digest)
                        notificationNodes = captured.0
                        notificationStableDigest = captured.1
                    }
                } else if initial.st_mode & S_IFMT == S_IFREG {
                    guard initial.st_nlink == 1, initial.st_size >= 0,
                          initial.st_size <= 1_073_741_824 else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    let digest = try io.withOpen(parent: directory, name: name,
                        flags: O_RDONLY | O_NONBLOCK) { descriptor in
                        var held = stat(), after = stat()
                        guard Darwin.fstat(descriptor, &held) == 0,
                              Self.fullFact(held) == Self.fullFact(initial) else {
                            throw EraseAllServiceError.invalidAuthority
                        }
                        var hash = SHA256()
                        var byteCount: off_t = 0
                        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
                        while true {
                            let count = buffer.withUnsafeMutableBytes {
                                Darwin.read(descriptor, $0.baseAddress, $0.count)
                            }
                            if count > 0 {
                                guard byteCount <= held.st_size - off_t(count) else {
                                    throw EraseAllServiceError.invalidAuthority
                                }
                                byteCount += off_t(count)
                                buffer.withUnsafeBytes { bytes in
                                    hash.update(bufferPointer: UnsafeRawBufferPointer(
                                        start: bytes.baseAddress, count: count))
                                }
                            } else if count == 0 { break }
                            else if errno != EINTR {
                                throw EraseAllServiceError.invalidAuthority
                            }
                        }
                        guard byteCount == held.st_size,
                              Darwin.fstat(descriptor, &after) == 0,
                              Self.fullFact(after) == Self.fullFact(held) else {
                            throw EraseAllServiceError.invalidAuthority
                        }
                        return hash.finalize().map {
                            String(format: "%02x", $0)
                        }.joined()
                    }
                    var final = stat()
                    guard Darwin.fstatat(directory, name, &final,
                            AT_SYMLINK_NOFOLLOW) == 0,
                          Self.fullFact(initial) == Self.fullFact(final) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    children[name] = .regular(
                        fact: Self.fullFact(initial),
                        digest: digest)
                } else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            var heldAfter = stat(), namedAfter = stat()
            guard try io.names(in: directory) == names,
                  Darwin.fstat(directory, &heldAfter) == 0,
                  Darwin.fstatat(parent, "FieldEvidenceOperations",
                    &namedAfter, AT_SYMLINK_NOFOLLOW) == 0,
                  Self.fullFact(heldAfter) == rootFact,
                  Self.fullFact(namedAfter) == rootFact,
                  children.count == names.count else {
                throw EraseAllServiceError.invalidAuthority
            }
            return (children, controlNodes, notificationNodes,
                notificationStableDigest)
        }
    }

    /// First-P owner and policy facts for every ingress-control node. The
    /// existing checked tree digest is proved both before and after these
    /// policy reads, so this adds facts to the immutable first observation
    /// rather than recapturing a later survivor image.
    private func observeControlNodes(operations: Int32,
        name: String, rootURL: URL,
        notificationControl: Bool,
        expectedRootFact: String,
        expectedTreeDigest: String) throws -> ([ControlNode], String?) {
        var nodes: [EraseAbortCheckedSnapshotIOV1.CheckedTreeNode] = []
        let digest = try io.postRetiredTree(parent: operations,
            name: name,
            observeTypedNode: { node, _ in nodes.append(node) })
        guard digest == expectedTreeDigest,
              let root = nodes.first(where: { $0.path.isEmpty }),
              Self.fullFact(root.fact) == expectedRootFact else {
            throw EraseAllServiceError.invalidAuthority
        }
        let stableDigest = notificationControl
            ? try io.postRetiredTree(parent: operations, name: name,
                ignoringDirectoryMetadata: Set([""])) : nil
        var byPath: [String: EraseAbortCheckedSnapshotIOV1.CheckedTreeNode] = [:]
        for node in nodes {
            guard byPath.updateValue(node, forKey: node.path) == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        if notificationControl {
            let allowed = Set([
                AppLockNotificationControlStoreV1.recordName,
                AppLockNotificationControlStoreV1.pendingName,
                AppLockNotificationControlStoreV1.mappingName,
                AppLockNotificationControlStoreV1.mappingPendingName,
                AppLockNotificationControlStoreV1.eraseName,
                AppLockNotificationControlStoreV1.erasePendingName
            ])
            guard Set(byPath.keys).subtracting([""]).isSubset(of: allowed),
                  byPath.values.allSatisfy({ $0.path.isEmpty ||
                      $0.sha256 != nil }) else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        var children: [String: [String]] = [:]
        for node in nodes where !node.path.isEmpty {
            let components = node.path.split(separator: "/",
                omittingEmptySubsequences: false).map(String.init)
            guard components.count <= 64,
                  components.allSatisfy({ !$0.isEmpty && $0 != "." &&
                      $0 != ".." && !$0.contains("/") }),
                  let name = components.last else {
                throw EraseAllServiceError.invalidAuthority
            }
            let parentPath = components.dropLast().joined(separator: "/")
            guard byPath[parentPath]?.sha256 == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            children[parentPath, default: []].append(name)
        }
        // A tree digest deliberately omits uid/gid. While each ancestor is
        // held, bind the complete named and held fact (including ownership)
        // before and after the URL policy observation of that exact inode.
        // This happens during the immutable first P capture, never after an
        // effect as a newly adopted baseline.
        var values: [ControlNode] = []
        func walk(parent: Int32, name: String, path: String) throws {
            guard let node = byPath[path] else {
                throw EraseAllServiceError.invalidAuthority
            }
            let isDirectory = node.sha256 == nil
            let flags: Int32 = O_RDONLY | O_NONBLOCK |
                (isDirectory ? O_DIRECTORY : 0)
            try io.withOpen(parent: parent, name: name,
                flags: flags) { descriptor in
                func requireFullHeldNamed() throws {
                    var held = stat(), named = stat()
                    guard Darwin.fstat(descriptor, &held) == 0,
                          Darwin.fstatat(parent, name, &named,
                              AT_SYMLINK_NOFOLLOW) == 0,
                          Self.fullFact(held) == Self.fullFact(node.fact),
                          Self.fullFact(named) == Self.fullFact(node.fact) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
                try requireFullHeldNamed()
                let kind: OwnedFileKindV1
                if isDirectory {
                    kind = .stagingDirectory
                } else if notificationControl {
                    kind = path.hasSuffix(".pending.json")
                        ? .journalTemporary : .journal
                } else {
                    kind = .temporaryFile
                }
                let url = path.split(separator: "/").reduce(
                    rootURL) { parent, component in
                    parent.appendingPathComponent(String(component))
                }
                let policy = try ProtectedFilePolicyV1
                    .observeTemporalPolicyWithCheckedClose(kind,
                        at: url, retainUncertainDescriptor: {
                            self.io.retainUncertainDescriptor($0)
                        })
                guard policy.device == UInt64(node.fact.st_dev),
                      policy.inode == UInt64(node.fact.st_ino),
                      policy.mode == UInt16(node.fact.st_mode),
                      policy.linkCount == UInt64(node.fact.st_nlink),
                      policy.isDirectory == isDirectory,
                      policy.backupExcluded == true,
                      policy.state == .strictComplete ||
                        policy.state == .pendingSimulatorRequest else {
                    throw EraseAllServiceError.invalidAuthority
                }
                values.append(ControlNode(path: path,
                    fullFact: Self.fullFact(node.fact), policy: policy,
                    contentSHA256: node.sha256))
                if isDirectory {
                    let expectedNames = (children[path] ?? []).sorted()
                    guard try io.names(in: descriptor) == expectedNames else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    for child in expectedNames {
                        try walk(parent: descriptor, name: child,
                            path: path.isEmpty ? child : "\(path)/\(child)")
                    }
                } else if children[path] != nil {
                    throw EraseAllServiceError.invalidAuthority
                }
                try requireFullHeldNamed()
            }
        }
        try walk(parent: operations, name: name,
            path: "")
        values.sort { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
        guard values.count == nodes.count,
              Set(values.map(\.path)).count == values.count,
              try io.postRetiredTree(parent: operations,
                  name: name)
                    == expectedTreeDigest,
              try (!notificationControl ||
                io.postRetiredTree(parent: operations, name: name,
                    ignoringDirectoryMetadata: Set([""]))
                    == stableDigest) else {
            throw EraseAllServiceError.invalidAuthority
        }
        return (values, stableDigest)
    }

    private func tree(parent: Int32, name: String) throws -> Tree {
        var before = stat()
        let status = Darwin.fstatat(parent, name, &before, AT_SYMLINK_NOFOLLOW)
        if status != 0 {
            guard errno == ENOENT else { throw EraseAllServiceError.invalidAuthority }
            return .absent
        }
        guard before.st_mode & S_IFMT == S_IFDIR else {
            throw EraseAllServiceError.invalidAuthority
        }
        // Existing checked walker streams file bytes and rejects links/special
        // nodes. No excluded paths or relaxed directory projections are used.
        let digest = try io.postRetiredTree(parent: parent, name: name)
        var after = stat()
        guard Darwin.fstatat(parent, name, &after, AT_SYMLINK_NOFOLLOW) == 0,
              Self.fullFact(before) == Self.fullFact(after) else {
            throw EraseAllServiceError.invalidAuthority
        }
        return .present(rootFact: Self.fullFact(before), digest: digest)
    }

    private func directoryFact(_ fd: Int32) throws -> stat {
        var value = stat()
        guard Darwin.fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else {
            throw EraseAllServiceError.invalidAuthority
        }
        return value
    }

    private static func identity(_ value: stat) -> ParentIdentity {
        ParentIdentity(device: value.st_dev, inode: value.st_ino, mode: value.st_mode,
                       user: value.st_uid, group: value.st_gid)
    }

    private nonisolated static func fullFact(_ value: stat) -> String {
        "\(value.st_dev)|\(value.st_ino)|\(value.st_mode)|\(value.st_uid)|\(value.st_gid)|\(value.st_nlink)|\(value.st_size)|\(value.st_mtimespec.tv_sec)|\(value.st_mtimespec.tv_nsec)|\(value.st_ctimespec.tv_sec)|\(value.st_ctimespec.tv_nsec)"
    }
}

// MARK: - Original retained Scratch per-effect observation

/// Immutable source DATA. Only Router's actual admission can bind these rows
/// to an earlier complete owned-pair capture and the original publication.
struct OriginalEraseScratchCleanupOriginalAliasPremiseV1 {
    let originalPaths: [String]
    let originalFacts: [String]
    let sha256: String
    let byteCount: Int64
    let metadata: OriginalEraseScratchCleanupAliasMetadataV1
}

enum OriginalEraseScratchCleanupAliasMetadataV1: Equatable {
    case validatedLease(directory: String, bytes: Data, sha256: String)
    case ownedOrphan(directory: String)
}

/// DATA, not authority. Current source mode must be the exact recorded full
/// mode of this positive source role. This engine has no directory-birth kind
/// and therefore never issues checkedBirth; a future issuer needs its real
/// checked birth receipt rather than a current-mode guess.
enum OriginalEraseScratchPrivateDirectoryRoleV1: Equatable {
    case originalP(sourcePath:String,recordedFullMode:UInt32)
    case checkedBirth(requestID:UUID,recordedFullMode:UInt32)
    var recordedFullMode:UInt32 {
        switch self {
        case .originalP(_,let mode), .checkedBirth(_,let mode): return mode
        }
    }
    func admits(fullMode:UInt32) -> Bool {
        fullMode == recordedFullMode && fullMode & UInt32(S_IFMT) == UInt32(S_IFDIR) &&
            (fullMode & 0o7777 == 0o700 || fullMode & 0o7777 == 0o2700)
    }
}

struct OriginalEraseScratchTemporalPolicyNodeV1 {
    struct Ancestor {
        let url: URL
        let fullFact: String
        let directoryRole:OriginalEraseScratchPrivateDirectoryRoleV1
    }
    let kind: OwnedFileKindV1
    let directoryRole:OriginalEraseScratchPrivateDirectoryRoleV1?
    let url: URL
    let fullFact: String
    let parentURL: URL
    let parentFullFact: String
    let ancestors: [Ancestor]
}

struct OriginalEraseScratchTemporalPairV1 {
    struct Member { let relativePath: String; let url: URL; let fullFact: String }
    enum Role {
        case declaredLinkPublication(createRequestID: UUID, linkRequestID: UUID,
            temporaryPath: String, finalPath: String)
        /// Fresh genuinely observed cold REQUEST prefix, separate from live
        /// primitive history and authentic Original generic-alias premises.
        case coldObservedPrefixPublication(ColdEraseScratchObservedRequestLinkV1)
        case admittedOriginalOwnedGenericAliases(premiseIndex: Int,
            originalPaths: [String], originalFacts: [String],
            originalSHA256: String, metadata: OriginalEraseScratchCleanupAliasMetadataV1)
    }
    let members: [Member]
    let kind: OwnedFileKindV1
    let sha256: String
    let byteCount: Int64
    let device: UInt64
    let inode: UInt64
    let user: UInt32
    let group: UInt32
    let parentURL: URL
    let parentFullFact: String
    let ancestors: [OriginalEraseScratchTemporalPolicyNodeV1.Ancestor]
    let role: Role
    fileprivate init(members: [Member], kind: OwnedFileKindV1, sha256: String,
        byteCount: Int64, device: UInt64, inode: UInt64, user: UInt32,
        group: UInt32, parent: OriginalEraseScratchTemporalPolicyNodeV1,
        role: Role) {
        self.members = members; self.kind = kind; self.sha256 = sha256
        self.byteCount = byteCount; self.device = device; self.inode = inode
        self.user = user; self.group = group; parentURL = parent.parentURL
        parentFullFact = parent.parentFullFact; ancestors = parent.ancestors
        self.role = role
    }
}

/// Lexical read capability only. The raw image has already been proved against
/// immutable source roles plus the exact retained syscall and saved result.
/// Closed dispatch of genuine admission objects, never a caller-conformable
/// authority facade. Snapshot/roster access is comparison DATA; every checked
/// operation still invokes the retained actual origin's owner and live G proof.
@MainActor
enum EraseScratchCleanupAdmissionOriginV1 {
    case original(OriginalEraseScratchCleanupInitialAdmissionV1)
    case cold(ColdEraseScratchCleanupInitialAdmissionV1)

    var operationID: UUID {
        switch self {
        case .original(let admission): return admission.operationID
        case .cold(let admission): return admission.operationID
        }
    }
    var applicationSupportURL: URL {
        switch self {
        case .original(let admission): return admission.applicationSupportURL
        case .cold(let admission): return admission.applicationSupportURL
        }
    }
    var firstSnapshot: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        switch self {
        case .original(let admission): return admission.firstSnapshot
        case .cold(let admission): return admission.firstSnapshot
        }
    }
    var notificationAfter: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        switch self {
        case .original(let admission): return admission.notificationAfter
        case .cold(let admission): return admission.notificationAfter
        }
    }
    var scratchStartingChild: EraseSchema2ColdAuxiliaryFirstObserverV1.OperationsChild? {
        switch self {
        case .original(let admission): return admission.scratchStartingChild
        case .cold(let admission): return admission.scratchStartingChild
        }
    }
    var physicalRoster: EraseSchema2ColdAuxiliaryPhysicalRosterV1 {
        switch self {
        case .original(let admission): return admission.physicalRoster
        case .cold(let admission): return admission.physicalRoster
        }
    }
    var originalGenericPairs: [OriginalEraseScratchCleanupOriginalAliasPremiseV1]? {
        switch self {
        case .original(let admission): return admission.originalGenericPairs
        case .cold(let admission): return admission.originalGenericPairs
        }
    }
    var heldScope: EraseScratchCleanupScopeOriginV1 {
        switch self {
        case .original(let admission): return .original(admission.heldScope)
        case .cold(let admission): return .cold(admission.heldScope)
        }
    }
    func requireHeld() throws {
        switch self {
        case .original(let admission): try admission.requireHeld()
        case .cold(let admission): try admission.requireHeld()
        }
    }
    func requireCanonicalSource(path: String, bytes: Data, fullFact: String) throws {
        switch self {
        case .original(let admission):
            try admission.requireCanonicalSource(path: path, bytes: bytes, fullFact: fullFact)
        case .cold(let admission):
            try admission.requireCanonicalSource(path: path, bytes: bytes, fullFact: fullFact)
        }
    }
    func requirePublicationRequest(intent: OriginalEraseScratchCleanupPrimitiveIntentV1) throws {
        switch self {
        case .original(let admission): try admission.requirePublicationRequest(intent: intent)
        case .cold(let admission): try admission.requirePublicationRequest(intent: intent)
        }
    }
    func requireFinalizedIngressReplacement(intent: OriginalEraseScratchCleanupPrimitiveIntentV1,
        originalBytes: Data, stagedBytes: Data) throws {
        switch self {
        case .original(let admission):
            try admission.requireFinalizedIngressReplacement(intent: intent,
                originalBytes: originalBytes, stagedBytes: stagedBytes)
        case .cold(let admission):
            try admission.requireFinalizedIngressReplacement(intent: intent,
                originalBytes: originalBytes, stagedBytes: stagedBytes)
        }
    }
    func requirePrimitiveRequest(intent: OriginalEraseScratchCleanupPrimitiveIntentV1,
        outcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1?) throws {
        switch self {
        case .original(let admission): try admission.requirePrimitiveRequest(intent: intent, outcome: outcome)
        case .cold(let admission): try admission.requirePrimitiveRequest(intent: intent, outcome: outcome)
        }
    }
    func requireCatalogFrame(attempt: OriginalEraseScratchCleanupAttemptV1,
        session: OriginalEraseScratchCanonicalSourceCatalogSessionV1) throws {
        switch self {
        case .original(let admission): try admission.requireCatalogFrame(attempt: attempt, session: session)
        case .cold(let admission): try admission.requireCatalogFrame(attempt: attempt, session: session)
        }
    }
    func requireOutside(operationsFact: String, operationsNames: [String],
        support: Int32, caches: Int32, temporary: Int32, operations: Int32,
        requireHeld: () throws -> Void) throws {
        switch self {
        case .original(let admission):
            try admission.observer.requireOriginalScratchOutside(anchor: admission.notificationAfter,
                operationsFact: operationsFact, operationsNames: operationsNames,
                support: support, caches: caches, temporary: temporary, operations: operations,
                requireHeld: requireHeld)
        case .cold(let admission):
            try admission.requireOutside(operationsFact: operationsFact,
                operationsNames: operationsNames, support: support, caches: caches,
                temporary: temporary, operations: operations)
        }
    }
    func poisonOnUncertainCleanup() {
        switch self {
        case .original(let admission): admission.poisonOnUncertainCleanup()
        case .cold(let admission): admission.poisonOnUncertainCleanup()
        }
    }
}

/// Actual scope objects behind the two closed cleanup origins. Equality is
/// origin-specific object identity only; the carrier does not prove held G,
/// grant IO or turn a cold owner into an Original scope.
@MainActor
enum EraseScratchCleanupScopeOriginV1 {
    case original(OriginalEraseScratchCleanupHeldGScopeV1)
    case cold(ColdEraseScratchCleanupHeldGScopeV1)

    func isSame(as other: EraseScratchCleanupScopeOriginV1) -> Bool {
        switch (self, other) {
        case (.original(let one), .original(let two)): return one === two
        case (.cold(let one), .cold(let two)): return one === two
        case (.original, .cold), (.cold, .original): return false
        }
    }
}

/// Primitive callbacks reprove actual G/frame and lifetime, never a payload
/// rescan. PFP independently pins all declared named/held ancestors and nodes.
@MainActor
final class OriginalEraseScratchTemporalObservationScopeV1 {
    let operationID: UUID
    let observationID = UUID()
    fileprivate let heldScope: EraseScratchCleanupScopeOriginV1
    private weak var owner: OriginalEraseScratchCleanupImageOwnerV1?
    private let nodes: [URL: OriginalEraseScratchTemporalPolicyNodeV1]
    private let pairs: [OriginalEraseScratchTemporalPairV1]
    private var revoked = false
    fileprivate init(owner: OriginalEraseScratchCleanupImageOwnerV1,
        nodes: [URL: OriginalEraseScratchTemporalPolicyNodeV1],
        pairs: [OriginalEraseScratchTemporalPairV1]) {
        self.owner = owner; operationID = owner.operationID; heldScope = owner.currentHeldScope
        self.nodes = nodes; self.pairs = pairs
    }
    func requireCurrentBinding() throws {
        guard !revoked, let owner else { throw EraseAllServiceError.invalidAuthority }
        try owner.requireScope(self)
    }
    /// No scope factory or new authority: this rechecks the exact retained
    /// cold REQUEST handle in this scope's immutable pair DATA. The range
    /// owner performs a nonrecursive current-frame proof around actual IO.
    fileprivate func requirePairOrigins(admission: EraseScratchCleanupAdmissionOriginV1,
        attempt: OriginalEraseScratchCleanupAttemptV1?) throws {
        switch admission {
        case .original:
            guard !pairs.contains(where: {
                if case .coldObservedPrefixPublication = $0.role { return true }
                return false
            }) else { throw EraseAllServiceError.invalidAuthority }
        case .cold(let coldAdmission):
            guard let attempt else { throw EraseAllServiceError.invalidAuthority }
            try attempt.requireColdImageOwnerOrigin(admission: coldAdmission)
            for pair in pairs {
                switch pair.role {
                case .coldObservedPrefixPublication(let handle):
                    try coldAdmission.ranges.requireObservedRequestLink(handle: handle,
                        scope: coldAdmission.heldScope, attempt: attempt)
                case .declaredLinkPublication:
                    // A newly performed live cold link still has its genuine
                    // retained primitive intents; no historical IDs are made.
                    break
                case .admittedOriginalOwnedGenericAliases:
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
    }
    func requirePolicyNode(_ kind: OwnedFileKindV1, at url: URL,
        fullFact: String) throws -> OriginalEraseScratchTemporalPolicyNodeV1 {
        try requireCurrentBinding()
        let node = try policyNodeData(kind, at: url, fullFact: fullFact)
        try requireCurrentBinding(); return node
    }
    func requirePair(aliasURLs: [URL]) throws -> OriginalEraseScratchTemporalPairV1 {
        try requireCurrentBinding()
        let pair = try pairData(aliasURLs: aliasURLs)
        try requireCurrentBinding(); return pair
    }
    /// Immutable DATA selection only; grants no current binding or IO authority.
    /// Protected uses must retain their own fresh live before/after boundaries.
    func policyNodeData(_ kind: OwnedFileKindV1, at url: URL,
        fullFact: String) throws -> OriginalEraseScratchTemporalPolicyNodeV1 {
        guard let node = nodes[url], node.url == url,
              node.kind == kind, node.fullFact == fullFact else {
            throw EraseAllServiceError.invalidAuthority
        }
        return node
    }
    /// Immutable DATA selection only, preserving the first exact ordered pair.
    /// A returned value does not establish a live scope or authorize protected IO.
    func pairData(aliasURLs: [URL]) throws -> OriginalEraseScratchTemporalPairV1 {
        #if DEBUG
        return try OriginalEraseScratchIssuerPairDataSelectionV1.select(pairs, aliasURLs: aliasURLs)
        #else
        guard aliasURLs.count == 2,
              let pair = pairs.first(where: { $0.members.map(\.url) == aliasURLs }) else {
            throw EraseAllServiceError.invalidAuthority
        }
        return pair
        #endif
    }
    #if DEBUG
    /// Complete immutable ordered DATA, copied only at a selected natural revoke.
    /// No Scope/G/owner reference or live/physical permission leaves this accessor.
    fileprivate func pairDataProjectionForIssuerTests() -> [OriginalEraseScratchTemporalPairV1] { pairs }
    #endif
    func retainObservationAttempt(_ attempt: OriginalEraseScratchTemporalPolicyAttemptV1) {
        owner?.retainPolicyAttempt(attempt)
    }
    func poisonOnUncertainObservation() { revoked = true; owner?.poison() }
    fileprivate func revoke() { revoked = true }
}

extension EraseSchema2ColdAuxiliaryFirstObserverV1 {
    /// Reuse the unchanged strict walker only for unaffected branches. The
    /// complete Scratch/ingress image is checked by the distinct typed owner;
    /// neither subtree is omitted from its whole-image before/after proof.
    private func requireOriginalScratchOutsideRegular(parent:Int32,name:String,
        expectedFact:String,expectedSHA:String,requireHeld:() throws -> Void) throws {
        try requireHeld()
        try io.withOpen(parent:parent,name:name,flags:O_RDONLY | O_NONBLOCK) { fd in
            func fact() throws -> stat {
                try requireHeld(); var h = stat(), n = stat()
                guard Darwin.fstat(fd,&h) == 0,
                      Darwin.fstatat(parent,name,&n,AT_SYMLINK_NOFOLLOW) == 0,
                      Self.fullFact(h) == expectedFact, Self.fullFact(n) == expectedFact,
                      h.st_mode & S_IFMT == S_IFREG, h.st_nlink == 1,
                      h.st_size >= 0, h.st_size <= 1_073_741_824 else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try requireHeld(); return h
            }
            let before = try fact()
            var hash = SHA256(), offset:off_t = 0
            var buffer = [UInt8](repeating:0,count:64 * 1_024)
            while offset < before.st_size {
                try requireHeld()
                let requested = min(buffer.count,Int(before.st_size - offset))
                let count = buffer.withUnsafeMutableBytes {
                    Darwin.pread(fd,$0.baseAddress,requested,offset)
                }
                try requireHeld()
                guard count > 0, count <= requested else { throw EraseAllServiceError.invalidAuthority }
                offset += off_t(count)
                buffer.withUnsafeBytes {
                    hash.update(bufferPointer:UnsafeRawBufferPointer(start:$0.baseAddress,count:count))
                }
            }
            try requireHeld(); var eof:UInt8 = 0
            guard Darwin.pread(fd,&eof,1,offset) == 0 else { throw EraseAllServiceError.invalidAuthority }
            try requireHeld(); _ = try fact()
            guard hash.finalize().map({ String(format:"%02x",$0) }).joined() == expectedSHA else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        try requireHeld(); try io.requireSettled()
    }

    /// Comparison-only projection from Manifest's genuine checked
    /// Notification/Registry operations. It proves every supplied changed
    /// fact against two complete scans; unlisted siblings stay exact first.
    /// The caller's real operation brackets this with its continuous EX/G.
    /// This does not recapture a survivor baseline or issue an effect owner.
    func requireColdNotificationProjected(first expected: Snapshot,
        operationsFact: String, operationsNames: [String],
        notificationRootFact: String?, notificationNames: [String],
        notificationLeafFacts: [String: String], notificationLeafSHA256: [String: String],
        registryChild: OperationsChild, creationRecord: OperationsChild?,
        support: Int32, caches: Int32, temporary: Int32) throws -> Snapshot {
        guard try firstObservation() == expected,
              operationsNames == operationsNames.sorted(),
              Set(operationsNames).count == operationsNames.count,
              notificationNames == notificationNames.sorted(),
              Set(notificationNames).count == notificationNames.count,
              Set(notificationLeafFacts.keys) == Set(notificationNames),
              Set(notificationLeafSHA256.keys) == Set(notificationNames) else {
            throw EraseAllServiceError.invalidAuthority
        }
        let notificationName = AppLockNotificationControlStoreV1.rootName
        let registryName = "generation-leases"
        let creationName = EraseSchema2ColdNotificationSourceV1.creationRecordName
        func validate(_ actual: Snapshot) throws {
            guard actual.supportIdentity == expected.supportIdentity,
                  actual.cacheIdentity == expected.cacheIdentity,
                  actual.temporaryIdentity == expected.temporaryIdentity,
                  actual.supportFact == expected.supportFact,
                  actual.supportNames == expected.supportNames,
                  actual.supportTrees == expected.supportTrees,
                  actual.cacheTree == expected.cacheTree,
                  actual.temporaryTree == expected.temporaryTree,
                  actual.operations.rootFact == operationsFact,
                  actual.operationsChildren.keys.sorted() == operationsNames,
                  actual.ingressControlNodes == expected.ingressControlNodes,
                  actual.operationsChildren[registryName] == registryChild,
                  actual.operationsChildren[creationName] == creationRecord else {
                throw EraseAllServiceError.invalidAuthority
            }
            let exceptions = Set([notificationName, registryName, creationName])
            guard Set(actual.operationsChildren.keys).subtracting(exceptions)
                    == Set(expected.operationsChildren.keys).subtracting(exceptions) else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (name, child) in expected.operationsChildren where !exceptions.contains(name) {
                guard actual.operationsChildren[name] == child else { throw EraseAllServiceError.invalidAuthority }
            }
            if let notificationRootFact {
                guard case .directory(let rootFact, _) = actual.operationsChildren[notificationName],
                      rootFact == notificationRootFact, let nodes = actual.notificationControlNodes,
                      let root = nodes.first(where: { $0.path.isEmpty }), root.fullFact == notificationRootFact,
                      nodes.filter({ !$0.path.isEmpty }).map(\.path).sorted() == notificationNames else {
                    throw EraseAllServiceError.invalidAuthority
                }
                for node in nodes where !node.path.isEmpty {
                    guard !node.path.contains("/"), notificationLeafFacts[node.path] == node.fullFact,
                          notificationLeafSHA256[node.path] == node.contentSHA256 else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
            } else {
                guard notificationNames.isEmpty, notificationLeafFacts.isEmpty,
                      notificationLeafSHA256.isEmpty, actual.operationsChildren[notificationName] == nil,
                      actual.notificationControlNodes == nil,
                      actual.notificationControlStableDigest == nil else { throw EraseAllServiceError.invalidAuthority }
            }
        }
        let one = try observe(support: support, caches: caches, temporary: temporary)
        try validate(one)
        let two = try observe(support: support, caches: caches, temporary: temporary)
        try validate(two)
        try io.requireSettled()
        guard one == two else { throw EraseAllServiceError.invalidAuthority }
        return two
    }

    func requireColdNotificationProjected(first expected: Snapshot,
        operationsFact: String, operationsNames: [String],
        notificationRootFact: String?, notificationNames: [String],
        notificationLeafFacts: [String: String], notificationLeafSHA256: [String: String],
        registryChild: OperationsChild, creationRecord: OperationsChild?,
        support: Int32, caches: Int32, temporary: Int32,
        observationScope: ColdEraseScratchNotificationObservationScopeV1) throws -> Snapshot {
        guard try firstObservation() == expected,
              operationsNames == operationsNames.sorted(),
              Set(operationsNames).count == operationsNames.count,
              notificationNames == notificationNames.sorted(),
              Set(notificationNames).count == notificationNames.count,
              Set(notificationLeafFacts.keys) == Set(notificationNames),
              Set(notificationLeafSHA256.keys) == Set(notificationNames) else {
            throw EraseAllServiceError.invalidAuthority
        }
        let notificationName = AppLockNotificationControlStoreV1.rootName
        let registryName = "generation-leases"
        let creationName = EraseSchema2ColdNotificationSourceV1.creationRecordName
        func validate(_ actual: Snapshot) throws {
            guard actual.supportIdentity == expected.supportIdentity,
                  actual.cacheIdentity == expected.cacheIdentity,
                  actual.temporaryIdentity == expected.temporaryIdentity,
                  actual.supportFact == expected.supportFact,
                  actual.supportNames == expected.supportNames,
                  actual.supportTrees == expected.supportTrees,
                  actual.cacheTree == expected.cacheTree,
                  actual.temporaryTree == expected.temporaryTree,
                  actual.operations.rootFact == operationsFact,
                  actual.operationsChildren.keys.sorted() == operationsNames,
                  actual.ingressControlNodes == expected.ingressControlNodes,
                  actual.operationsChildren[registryName] == registryChild,
                  actual.operationsChildren[creationName] == creationRecord else {
                throw EraseAllServiceError.invalidAuthority
            }
            let exceptions = Set([notificationName, registryName, creationName])
            guard Set(actual.operationsChildren.keys).subtracting(exceptions)
                    == Set(expected.operationsChildren.keys).subtracting(exceptions) else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (name, child) in expected.operationsChildren where !exceptions.contains(name) {
                guard actual.operationsChildren[name] == child else { throw EraseAllServiceError.invalidAuthority }
            }
            if let notificationRootFact {
                guard case .directory(let rootFact, _) = actual.operationsChildren[notificationName],
                      rootFact == notificationRootFact, let nodes = actual.notificationControlNodes,
                      let root = nodes.first(where: { $0.path.isEmpty }), root.fullFact == notificationRootFact,
                      nodes.filter({ !$0.path.isEmpty }).map(\.path).sorted() == notificationNames else {
                    throw EraseAllServiceError.invalidAuthority
                }
                for node in nodes where !node.path.isEmpty {
                    guard !node.path.contains("/"), notificationLeafFacts[node.path] == node.fullFact,
                          notificationLeafSHA256[node.path] == node.contentSHA256 else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
            } else {
                guard notificationNames.isEmpty, notificationLeafFacts.isEmpty,
                      notificationLeafSHA256.isEmpty, actual.operationsChildren[notificationName] == nil,
                      actual.notificationControlNodes == nil,
                      actual.notificationControlStableDigest == nil else { throw EraseAllServiceError.invalidAuthority }
            }
        }
        var enteredWindow: ColdEraseScratchNotificationReadWindowV1?
        do {
            try observationScope.requireBorrowedParents(support: support, caches: caches, temporary: temporary)
            try observationScope.requireObserverBackingReservation()
            let window = try ColdEraseScratchNotificationReadWindowV1.make(observationScope: observationScope)
            enteredWindow = window // exact already Native-retained owner before later fallible scans/projection
            func requireProjection() throws {
                try observationScope.requireBorrowedParents(support: support, caches: caches, temporary: temporary)
                try observationScope.requireProjectedSnapshot(first: expected,
                    operationsFact: operationsFact, operationsNames: operationsNames,
                    notificationRootFact: notificationRootFact, notificationNames: notificationNames,
                    notificationLeafFacts: notificationLeafFacts, notificationLeafSHA256: notificationLeafSHA256,
                    registryChild: registryChild, creationRecord: creationRecord)
                try observationScope.requireCurrentBinding()
            }
            try requireProjection()
            let firstResult = try observeColdNotification(window: window)
            let one = try firstResult.requireReturnedSnapshot()
            try validate(one); try requireProjection()
            let secondResult = try observeColdNotification(window: window)
            let two = try secondResult.requireReturnedSnapshot()
            try validate(two); try requireProjection()
            guard one == two else { throw EraseAllServiceError.invalidAuthority }
            try window.completeInitialObservation(observationScope: observationScope)
            try window.requireCheckedInitialReadSettlement(observationScope: observationScope)
            return two // same Native-retained full two-scan result, not a Void projection
        } catch {
            enteredWindow?.poisonSnapshotMaterialization()
            observationScope.poisonOnUncertainObservation(); throw error
        }
    }

    /// A cold-only complete reader. Every open/read/cursor/close is owned by
    /// the same entered Window. Field-role slots retain all genuine operands;
    /// only the exact complete profile may build the Snapshot after close.
    private func observeColdNotification(window: ColdEraseScratchNotificationReadWindowV1)
        throws -> ColdEraseScratchNotificationSnapshotResultV1 {
        let start = window.snapshotSlotCount
        try window.requireCurrentBinding()
        try window.withRootDirectory(root: .support) { support in
            guard support.isDirectory else { throw EraseAllServiceError.invalidAuthority }
            try window.appendSnapshotSlot(.supportIdentity(support.snapshotParentIdentity, support.fullFact))
            try window.appendSnapshotSlot(.cacheIdentity(try window.rootIdentity(root: .caches)))
            try window.appendSnapshotSlot(.temporaryIdentity(try window.rootIdentity(root: .temporary)))
            try support.readNames()
            for ordinal in 0..<support.nameCount {
                try support.withName(at: ordinal) { name in
                    switch name {
                    case "FieldEvidenceRestore", "FieldEvidenceCommerce", "FieldEvidenceDiagnostics",
                         LocalSearchIndexStoreV1.directoryName, PortableExchangeSessionStoreLayoutV2.directoryName,
                         LocalJobStoreSchemaV1.directoryName, "FieldEvidenceData", "FieldEvidenceErase", "FieldEvidenceOperations": break
                    default: throw EraseAllServiceError.invalidAuthority
                    }
                    try window.appendSnapshotSlot(.name(name))
                }
            }
            @MainActor func supportTree(_ name: String) throws {
                try window.appendSnapshotSlot(.supportTree(name, try window.captureTree(parent: support, name: name)))
            }
            try supportTree("FieldEvidenceRestore"); try supportTree("FieldEvidenceCommerce")
            try supportTree("FieldEvidenceDiagnostics"); try supportTree(LocalSearchIndexStoreV1.directoryName)
            try supportTree(PortableExchangeSessionStoreLayoutV2.directoryName); try supportTree(LocalJobStoreSchemaV1.directoryName)
            let operations = try window.captureTree(parent: support, name: "FieldEvidenceOperations")
            try window.appendSnapshotSlot(.operations(operations))
            var ingressPresent = false, notificationPresent = false
            var notificationStableDigest: String?
            if case .present(let rootFact, _) = operations {
                try support.withChild(name: "FieldEvidenceOperations") { directory in
                    guard directory.isDirectory, directory.fullFact == rootFact else { throw EraseAllServiceError.invalidAuthority }
                    try directory.readNames()
                    for ordinal in 0..<directory.nameCount {
                        try directory.withName(at: ordinal) { name in
                            // Actual selected node determines the role. A scalar
                            // caller fact or anonymous Snapshot slot cannot do it.
                            var directoryChild = false
                            try directory.withChild(name: name) { child in
                                directoryChild = child.isDirectory
                                if !child.isDirectory {
                                    let digest = try child.digestFile()
                                    try window.appendSnapshotSlot(.child(name, .regular(fact: child.fullFact, digest: digest)))
                                }
                            }
                            if directoryChild {
                                let tree = try window.captureTree(parent: directory, name: name)
                                guard case .present(let fact, let digest) = tree else { throw EraseAllServiceError.invalidAuthority }
                                try window.appendSnapshotSlot(.child(name, .directory(rootFact: fact, digest: digest)))
                                if name == "ProtectedIngressReceiptsV1" {
                                    ingressPresent = true
                                    _ = try observeColdNotificationControls(window: window, operations: directory,
                                        name: name, expected: tree, notification: false)
                                } else if name == AppLockNotificationControlStoreV1.rootName {
                                    notificationPresent = true
                                    notificationStableDigest = try observeColdNotificationControls(window: window,
                                        operations: directory, name: name, expected: tree, notification: true)
                                }
                            }
                        }
                    }
                    try directory.requireCurrentBinding()
                }
            }
            try window.appendSnapshotSlot(.ingressPresence(ingressPresent))
            try window.appendSnapshotSlot(.notificationPresence(notificationPresent))
            try window.appendSnapshotSlot(.notificationStableDigest(notificationStableDigest))
            guard try window.captureTree(parent: support, name: "FieldEvidenceOperations") == operations else {
                throw EraseAllServiceError.invalidAuthority
            }
            try window.appendSnapshotSlot(.cacheTree(try window.captureTree(root: .caches, name: "FieldEvidenceApp")))
            try window.appendSnapshotSlot(.temporaryTree(try window.captureTree(root: .temporary, name: "FieldEvidenceApp")))
            // Same borrowed Cache/temp identity, while Support remains full11.
            var firstCaches: ParentIdentity?, firstTemporary: ParentIdentity?
            for ordinal in start..<window.snapshotSlotCount {
                try window.withSnapshotSlot(at: ordinal) { value in
                    if case .cacheIdentity(let identity) = value { firstCaches = identity }
                    if case .temporaryIdentity(let identity) = value { firstTemporary = identity }
                }
            }
            guard try window.rootIdentity(root: .caches) == firstCaches,
                  try window.rootIdentity(root: .temporary) == firstTemporary else { throw EraseAllServiceError.invalidAuthority }
            try support.requireCurrentBinding()
            // Node's real close repeats complete names and full11 held/named
            // facts before/after once-close; the callback has returned first.
        }
        try window.requireCheckedReadSettlement()
        let result = try ColdEraseScratchNotificationSnapshotResultV1.make(window: window,
            start: start, end: window.snapshotSlotCount)
        try window.recordCompleteReadPass()
        return result
    }

    /// Whole tree/full11/SHA is checked on both sides of the genuine PFP
    /// policies, whose own pin/getter/checked-close owner is retained before
    /// first IO. The same active Node consumes each exact row and real slots.
    private func observeColdNotificationControls(window: ColdEraseScratchNotificationReadWindowV1,
        operations: ColdEraseScratchNotificationReadNodeV1, name: String, expected: Tree,
        notification: Bool) throws -> String? {
        guard case .present(let rootFact, let expectedDigest) = expected,
              try window.captureTree(parent: operations, name: name) == expected else { throw EraseAllServiceError.invalidAuthority }
        let start = window.snapshotSlotCount
        var count = 0
        let digest = try window.digestTree(parent: operations, name: name) { node, path, sha in
            guard count < 100_000, path.utf8.count <= 16_639,
                  !path.isEmpty || node.isDirectory && node.fullFact == rootFact else { throw EraseAllServiceError.invalidAuthority }
            count += 1
            if notification, !path.isEmpty {
                guard !path.contains("/"), !node.isDirectory else { throw EraseAllServiceError.invalidAuthority }
                try window.requireNotificationLeafName(path)
            }
            let scope = try ColdEraseScratchNotificationControlPolicyObservationScopeV1.make(window: window, node: node)
            let observation = try ProtectedFilePolicyV1.observeColdScratchNotificationControlPolicyWithCheckedClose(scope: scope)
            try observation.requireCheckedSettlement()
            guard let policy = observation.value else { throw EraseAllServiceError.invalidAuthority }
            let row = ControlNode(path: path, fullFact: node.fullFact, policy: policy, contentSHA256: sha)
            try scope.consumeControlRow(row)
            try window.appendSnapshotSlot(notification ? .notificationControl(row) : .ingressControl(row))
            try node.requireCurrentBinding()
        }
        guard digest == expectedDigest, count > 0,
              !notification || count <= 11 else { throw EraseAllServiceError.invalidAuthority }
        // The stable digest has the incumbent root-only metadata exception;
        // every selected Node's actual held/named facts still use full11.
        let stable = notification ? try window.digestTree(parent: operations, name: name, stableNotificationRoot: true) : nil
        guard try window.captureTree(parent: operations, name: name) == expected else { throw EraseAllServiceError.invalidAuthority }
        if notification {
            guard try window.digestTree(parent: operations, name: name, stableNotificationRoot: true) == stable else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        var retained = 0
        for ordinal in start..<window.snapshotSlotCount {
            try window.withSnapshotSlot(at: ordinal) { value in
                if notification { if case .notificationControl = value { retained += 1 } }
                else { if case .ingressControl = value { retained += 1 } }
            }
        }
        guard retained == count else { throw EraseAllServiceError.invalidAuthority }
        return stable
    }

    /// Genuine ongoing cold outside reader: same settled Window transferred
    /// from the consumed initial Scope to the actual Admission. The incumbent
    /// Original outside scanner remains byte-for-byte unchanged.
    private func requireColdNotificationOutside(window: ColdEraseScratchNotificationReadWindowV1,
        admission: ColdEraseScratchCleanupInitialAdmissionV1, operationsFact: String, operationsNames: [String]) throws {
        let anchor = admission.notificationAfter
        try admission.requireColdNotificationOutsideFrame()
        try window.requireCurrentBinding()
        try window.withRootDirectory(root: .support) { support in
            guard support.snapshotParentIdentity == anchor.supportIdentity, support.fullFact == anchor.supportFact,
                  try window.rootIdentity(root: .caches) == anchor.cacheIdentity,
                  try window.rootIdentity(root: .temporary) == anchor.temporaryIdentity else { throw EraseAllServiceError.invalidAuthority }
            try support.readNames()
            guard support.nameCount == anchor.supportNames.count else { throw EraseAllServiceError.invalidAuthority }
            for ordinal in 0..<support.nameCount {
                try support.withName(at: ordinal) { name in
                    guard anchor.supportNames[ordinal] == name else { throw EraseAllServiceError.invalidAuthority }
                }
            }
            for (name, expected) in anchor.supportTrees {
                guard try window.captureTree(parent: support, name: name) == expected else { throw EraseAllServiceError.invalidAuthority }
            }
            guard try window.captureTree(root: .caches, name: "FieldEvidenceApp") == anchor.cacheTree,
                  try window.captureTree(root: .temporary, name: "FieldEvidenceApp") == anchor.temporaryTree else {
                throw EraseAllServiceError.invalidAuthority
            }
            try support.withChild(name: "FieldEvidenceOperations") { operations in
                guard operations.isDirectory, operations.fullFact == operationsFact else { throw EraseAllServiceError.invalidAuthority }
                try operations.readNames()
                guard operations.nameCount == operationsNames.count else { throw EraseAllServiceError.invalidAuthority }
                var untouchedCount = 0
                for ordinal in 0..<operations.nameCount {
                    try operations.withName(at: ordinal) { name in
                        guard operationsNames[ordinal] == name else { throw EraseAllServiceError.invalidAuthority }
                        if name != "ScratchDataV1", name != "ProtectedIngressReceiptsV1" {
                            guard anchor.operationsChildren[name] != nil else { throw EraseAllServiceError.invalidAuthority }
                            untouchedCount += 1
                        }
                    }
                }
                var expectedUntouched = 0
                for (name, expected) in anchor.operationsChildren where name != "ScratchDataV1" && name != "ProtectedIngressReceiptsV1" {
                    expectedUntouched += 1
                    try admission.requireColdNotificationOutsideFrame()
                    switch expected {
                    case .directory(let fact, let digest):
                        let tree: Tree = .present(rootFact: fact, digest: digest)
                        guard try window.captureTree(parent: operations, name: name) == tree else { throw EraseAllServiceError.invalidAuthority }
                        if name == AppLockNotificationControlStoreV1.rootName {
                            guard let rows = anchor.notificationControlNodes else { throw EraseAllServiceError.invalidAuthority }
                            let start = window.snapshotSlotCount
                            let stable = try observeColdNotificationControls(window: window, operations: operations,
                                name: name, expected: tree, notification: true)
                            var actualCount = 0
                            for ordinal in start..<window.snapshotSlotCount {
                                try window.withSnapshotSlot(at: ordinal) { slot in
                                    if case .notificationControl(let row) = slot {
                                        guard rows.first(where: { $0.path == row.path }) == row else { throw EraseAllServiceError.invalidAuthority }
                                        actualCount += 1
                                    }
                                }
                            }
                            guard actualCount == rows.count, stable == anchor.notificationControlStableDigest else {
                                throw EraseAllServiceError.invalidAuthority
                            }
                        }
                    case .regular(let fact, let digest):
                        try operations.withChild(name: name) { child in
                            guard !child.isDirectory, child.fullFact == fact,
                                  try child.digestFile() == digest else { throw EraseAllServiceError.invalidAuthority }
                        }
                    }
                    try admission.requireColdNotificationOutsideFrame()
                }
                guard untouchedCount == expectedUntouched else { throw EraseAllServiceError.invalidAuthority }
                try operations.requireCurrentBinding()
            }
            try support.requireCurrentBinding()
        }
        try window.requireCheckedReadSettlement()
        try admission.requireColdNotificationOutsideFrame()
    }

    /// Distinct cold consumer of the incumbent complete outside scanner.
    /// The snapshot is retained by the genuine cold admission; this method
    /// cannot choose a survivor baseline, issue an Original receipt or change
    /// either Scratch/ingress image. requireHeld is the nonrecursive G/frame
    /// proof, so policy scanning cannot recursively authorize itself.
    @MainActor
    func requireColdScratchOutside(admission: ColdEraseScratchCleanupInitialAdmissionV1,
        operationsFact: String, operationsNames: [String], support: Int32,
        caches: Int32, temporary: Int32, operations: Int32) throws {
        try admission.requireHeld()
        guard try firstObservation() == admission.firstSnapshot,
              admission.notificationAfter.supportIdentity == admission.firstSnapshot.supportIdentity,
              admission.notificationAfter.cacheIdentity == admission.firstSnapshot.cacheIdentity,
              admission.notificationAfter.temporaryIdentity == admission.firstSnapshot.temporaryIdentity else {
            throw EraseAllServiceError.invalidAuthority
        }
        try admission.requireColdNotificationObserverBackingReservation()
        let window = try admission.ranges.requireColdScratchNotificationOutsideReadWindow(admission: admission)
        try window.requireOutsideBorrowedParents(support: support, caches: caches,
            temporary: temporary, operations: operations)
        try requireColdNotificationOutside(window: window, admission: admission,
            operationsFact: operationsFact, operationsNames: operationsNames)
        try admission.requireHeld()
    }

    fileprivate func requireOriginalScratchOutside(
        anchor: Snapshot, operationsFact: String, operationsNames: [String],
        support: Int32, caches: Int32, temporary: Int32, operations: Int32,
        requireHeld: () throws -> Void) throws {
        try requireHeld(); try io.requireSettled()
        guard Self.fullFact(try directoryFact(support)) == anchor.supportFact,
              try io.names(in: support) == anchor.supportNames,
              Self.identity(try directoryFact(caches)) == anchor.cacheIdentity,
              Self.identity(try directoryFact(temporary)) == anchor.temporaryIdentity else {
            throw EraseAllServiceError.invalidAuthority
        }
        for (name, expected) in anchor.supportTrees {
            try requireHeld()
            guard try tree(parent: support, name: name) == expected else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        try requireHeld()
        guard try tree(parent: caches, name: "FieldEvidenceApp") == anchor.cacheTree,
              try tree(parent: temporary, name: "FieldEvidenceApp") == anchor.temporaryTree,
              Self.fullFact(try directoryFact(operations)) == operationsFact,
              try io.names(in: operations) == operationsNames else {
            throw EraseAllServiceError.invalidAuthority
        }
        var named = stat()
        guard Darwin.fstatat(support, "FieldEvidenceOperations", &named,
                AT_SYMLINK_NOFOLLOW) == 0,
              Self.fullFact(named) == operationsFact else {
            throw EraseAllServiceError.invalidAuthority
        }
        let untouched = anchor.operationsChildren.filter {
            $0.key != "ScratchDataV1" && $0.key != "ProtectedIngressReceiptsV1"
        }
        guard Set(operationsNames).subtracting(["ScratchDataV1",
            "ProtectedIngressReceiptsV1"]) == Set(untouched.keys) else {
            throw EraseAllServiceError.invalidAuthority
        }
        for (name, child) in untouched {
            try requireHeld()
            switch child {
            case .directory(let fact, let digest):
                guard try tree(parent: operations, name: name)
                    == .present(rootFact: fact, digest: digest) else {
                    throw EraseAllServiceError.invalidAuthority
                }
            case .regular(let fact, let digest):
                try requireOriginalScratchOutsideRegular(parent: operations,name:name,
                    expectedFact:fact,expectedSHA:digest,requireHeld:requireHeld)
            }
        }
        if let expected = anchor.notificationControlNodes,
           case .directory(let fact, let digest) = untouched[
                AppLockNotificationControlStoreV1.rootName] {
            guard let notificationControlURL else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireHeld()
            let actual = try observeControlNodes(operations: operations,
                name: AppLockNotificationControlStoreV1.rootName,
                rootURL: notificationControlURL, notificationControl: true,
                expectedRootFact: fact, expectedTreeDigest: digest)
            guard actual.0 == expected,
                  actual.1 == anchor.notificationControlStableDigest else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        try requireHeld(); try io.requireSettled()
        guard Self.fullFact(try directoryFact(support)) == anchor.supportFact,
              try io.names(in: support) == anchor.supportNames,
              Self.fullFact(try directoryFact(operations)) == operationsFact,
              try io.names(in: operations) == operationsNames else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
}

/// A closed association of genuine task origin. This DATA label cannot mint
/// a task, historical Outcome, resource, close result or observation proof.
enum ColdEraseScratchTaskSettlementOriginV1: Equatable { case live, freshObserved, mixed }

/// Newly issued current-process full task-postimage proof. Only the actual
/// ImageOwner constructs it after complete scans and positive observer
/// settlement; Pending/Stage/Image/DATA alone cannot create one. Strong real
/// owners survive through the sole OBS and remain permanent on uncertainty.
@MainActor
final class ColdEraseScratchTaskObservationSettlementV1 {
    let image: OriginalEraseScratchCleanupImageV1
    let origin: ColdEraseScratchTaskSettlementOriginV1
    fileprivate let task: ColdEraseScratchPendingTaskV1
    fileprivate let sequence: UInt64
    fileprivate var consumed = false
    private var owner: OriginalEraseScratchCleanupImageOwnerV1?
    private var attempt: OriginalEraseScratchCleanupAttemptV1?
    private var scope: ColdEraseScratchCleanupHeldGScopeV1?

    fileprivate init(owner: OriginalEraseScratchCleanupImageOwnerV1,
        task: ColdEraseScratchPendingTaskV1, attempt: OriginalEraseScratchCleanupAttemptV1,
        scope: ColdEraseScratchCleanupHeldGScopeV1,
        image: OriginalEraseScratchCleanupImageV1,
        origin: ColdEraseScratchTaskSettlementOriginV1, sequence: UInt64) {
        self.owner = owner; self.task = task; self.attempt = attempt; self.scope = scope
        self.image = image; self.origin = origin; self.sequence = sequence
    }

    func requireBound(task: ColdEraseScratchPendingTaskV1,
        attempt: OriginalEraseScratchCleanupAttemptV1,
        scope: ColdEraseScratchCleanupHeldGScopeV1,
        after: OriginalEraseScratchCleanupImageV1) throws {
        guard !consumed, self.task === task, self.attempt === attempt,
              self.scope === scope, image == after, let owner else {
            throw EraseAllServiceError.invalidAuthority
        }
        try owner.requireColdTaskObservationSettlement(self, task: task,
            attempt: attempt, scope: scope, after: after)
    }

    fileprivate func consume(owner: OriginalEraseScratchCleanupImageOwnerV1) throws {
        guard !consumed, self.owner === owner, attempt != nil, scope != nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        // Called only after the actual range owner joins its identical newly
        // durable OBS/Settled to this same Pending/proof. No close is inferred.
        consumed = true
        self.owner = nil; attempt = nil; scope = nil
    }
}

/// Retained before IO; no descriptor, effect permit, Registry or current-image
/// authority escapes. The only image advance is one matched closed primitive.
@MainActor
final class OriginalEraseScratchCleanupImageOwnerV1 {
    typealias Image = OriginalEraseScratchCleanupImageV1
    typealias Intent = OriginalEraseScratchCleanupPrimitiveIntentV1
    typealias Outcome = OriginalEraseScratchCleanupPrimitiveOutcomeV1
    fileprivate let operationID: UUID
    private let admission: EraseScratchCleanupAdmissionOriginV1
    private weak var coldAttempt: OriginalEraseScratchCleanupAttemptV1?
    private var coldReplaySeed: ColdEraseScratchReplaySeedV1?
    private var coldTaskObservationSettlement: ColdEraseScratchTaskObservationSettlementV1?
    // Fixed inline references to real range-owner reservations; no growing
    // bookkeeping array can hide the backing or discard a failed lease.
    private var coldFirstNodesLease: ColdEraseScratchMechanicsIndexLeaseV1?
    private var coldMappingsLease: ColdEraseScratchMechanicsIndexLeaseV1?
    private var coldConsumedLease: ColdEraseScratchMechanicsIndexLeaseV1?
    private var coldPublicationsLease: ColdEraseScratchMechanicsIndexLeaseV1?
    private var callHeldScope: EraseScratchCleanupScopeOriginV1?
    private var lastMatchedHeldScope: EraseScratchCleanupScopeOriginV1?
    fileprivate var currentHeldScope: EraseScratchCleanupScopeOriginV1 { admission.heldScope }
    private var attempted = false
    private var poisoned = false
    private var initial: Image?
    private var current: Image?
    private var activeCatalog: OriginalEraseScratchCanonicalSourceCatalogSessionV1?
    private var retainedCatalogs: [OriginalEraseScratchCanonicalSourceCatalogSessionV1] = []
    private var pending: Intent?
    private var attemptID: UUID?
    private var nextSequence: UInt64?
    private var observationOutcome: Outcome?
    private var activeScope: OriginalEraseScratchTemporalObservationScopeV1?
    private var settledPolicyAttemptCount = 0
    private var policyAttempts: [OriginalEraseScratchTemporalPolicyAttemptV1] = []
    private var uncertainFDs: [Int32] = []
    private var uncertainDirectories: [UnsafeMutablePointer<DIR>] = []
    /// Distinct genuine current-process cold observation owner. The scanner
    /// never exports its slot objects/FDs. A positive lexical close is recorded
    /// once; uncertainty permanently retains the exact acquired owner. The
    /// fixed recursive scanner limit (depth <= 64, plus one names cursor)
    /// bounds simultaneous acquisitions to 65, with one consumed last slot.
    @MainActor private final class ColdObservationResources {
        final class Slot {
            enum State { case opening, refused, open, cursorEntered, cursor, closeEntered, closed, uncertain }
            struct Storage {
                let sequence: UInt64
                var state: State = State.opening
                var descriptor: Int32? = nil
                var directory: UnsafeMutablePointer<DIR>? = nil
                var openResult: Int32? = nil
                var openErrno: Int32? = nil
                var cursorSucceeded: Bool? = nil
                var cursorErrno: Int32? = nil
                var closeResult: Int32? = nil
                var closeErrno: Int32? = nil
                var beforeCloseFact: stat? = nil
                var beforeCloseNamedFact: stat? = nil
                var parentBeforeCloseFact: stat? = nil
                var parentAfterCloseFact: stat? = nil
            }
            private var storage: Storage
            var sequence: UInt64 {
                get { storage.sequence }
            }
            var state: State {
                get { storage.state }
                set { storage.state = newValue }
            }
            var descriptor: Int32? {
                get { storage.descriptor }
                set { storage.descriptor = newValue }
            }
            var directory: UnsafeMutablePointer<DIR>? {
                get { storage.directory }
                set { storage.directory = newValue }
            }
            var openResult: Int32? {
                get { storage.openResult }
                set { storage.openResult = newValue }
            }
            var openErrno: Int32? {
                get { storage.openErrno }
                set { storage.openErrno = newValue }
            }
            var cursorSucceeded: Bool? {
                get { storage.cursorSucceeded }
                set { storage.cursorSucceeded = newValue }
            }
            var cursorErrno: Int32? {
                get { storage.cursorErrno }
                set { storage.cursorErrno = newValue }
            }
            var closeResult: Int32? {
                get { storage.closeResult }
                set { storage.closeResult = newValue }
            }
            var closeErrno: Int32? {
                get { storage.closeErrno }
                set { storage.closeErrno = newValue }
            }
            var beforeCloseFact: stat? {
                get { storage.beforeCloseFact }
                set { storage.beforeCloseFact = newValue }
            }
            var beforeCloseNamedFact: stat? {
                get { storage.beforeCloseNamedFact }
                set { storage.beforeCloseNamedFact = newValue }
            }
            var parentBeforeCloseFact: stat? {
                get { storage.parentBeforeCloseFact }
                set { storage.parentBeforeCloseFact = newValue }
            }
            var parentAfterCloseFact: stat? {
                get { storage.parentAfterCloseFact }
                set { storage.parentAfterCloseFact = newValue }
            }
            init(sequence: UInt64) { storage = Storage(sequence: sequence) }
        }
        private var entered: UInt64 = 0
        private var consumed: UInt64 = 0
        private var active: [Slot] = []
        private var lastConsumed: Slot?
        private var uncertain: [Slot] = []
        private var poisoned = false
        // Comparison transcript belongs to this actual closed owner. It is
        // never accepted as a substitute for the private slot transitions.
        private var transcript = SHA256()
        init() { active.reserveCapacity(65); uncertain.reserveCapacity(65) }
        var actualReferenceCapacity: Int { active.capacity + uncertain.capacity + 1 }
        static var retainedSlotStorageBytes: UInt64 {
            // Exact source-owned scalar storage plus fixed owner backing.
            // Runtime object headers/allocator/VM are separately unmeasured.
            UInt64(66 * MemoryLayout<Slot.Storage>.stride + MemoryLayout<SHA256>.stride
                + 2 * MemoryLayout<UInt64>.stride + 2 * MemoryLayout<[Slot]>.stride
                + MemoryLayout<Slot?>.stride + MemoryLayout<Bool>.stride)
        }
        func prepare() throws -> Slot {
            guard !poisoned, uncertain.isEmpty, active.count < 65 else {
                throw EraseAllServiceError.invalidAuthority
            }
            let next = entered.addingReportingOverflow(1)
            guard !next.overflow else { throw EraseAllServiceError.invalidAuthority }
            let slot = Slot(sequence: next.partialValue)
            active.append(slot); entered = next.partialValue
            return slot // actual retained acquisition BEFORE openat
        }
        func capture(_ slot: Slot, descriptor: Int32, savedErrno: Int32) throws {
            let expected = active.last === slot && slot.state == .opening && slot.openResult == nil
            // Retain the actual returned descriptor/result before any refusal
            // can unwind. No post-call authority check may lose a live FD.
            slot.openResult = descriptor; slot.openErrno = savedErrno
            if descriptor >= 0 { slot.descriptor = descriptor }
            guard expected else {
                slot.state = .uncertain; retainUncertain(slot)
                throw EraseAllServiceError.invalidAuthority
            }
            if descriptor < 0 { slot.state = .refused; poisoned = true; throw EraseAllServiceError.invalidAuthority }
            guard !active.dropLast().contains(where: { $0.descriptor == descriptor }) else {
                slot.state = .uncertain; retainUncertain(slot)
                throw EraseAllServiceError.invalidAuthority
            }
            slot.state = .open
        }
        func enterCursor(_ slot: Slot) throws {
            guard active.last === slot, slot.state == .open else { throw EraseAllServiceError.invalidAuthority }
            slot.state = .cursorEntered
        }
        func captureCursor(_ slot: Slot, directory: UnsafeMutablePointer<DIR>?, savedErrno: Int32) throws {
            let expected = active.last === slot && slot.state == .cursorEntered && slot.cursorSucceeded == nil
            slot.cursorSucceeded = directory != nil; slot.cursorErrno = savedErrno
            if let directory { slot.directory = directory }
            guard expected else {
                slot.state = .uncertain; retainUncertain(slot)
                throw EraseAllServiceError.invalidAuthority
            }
            if directory != nil { slot.state = .cursor }
            else { slot.state = .open; throw EraseAllServiceError.invalidAuthority }
        }
        private func retainUncertain(_ slot: Slot) {
            if !uncertain.contains(where: { $0 === slot }) { uncertain.append(slot) }
            poisoned = true
        }
        func close(_ slot: Slot) throws {
            guard active.last === slot, slot.state == .open || slot.state == .cursor,
                  slot.closeResult == nil, let descriptor = slot.descriptor,
                  let held = slot.beforeCloseFact, let named = slot.beforeCloseNamedFact,
                  slot.parentBeforeCloseFact != nil,
                  OriginalEraseScratchCleanupImageOwnerV1.full(held) == OriginalEraseScratchCleanupImageOwnerV1.full(named) else {
                throw EraseAllServiceError.invalidAuthority
            }
            let cursor = slot.directory
            slot.state = .closeEntered // fence BEFORE the sole close
            let result = cursor.map { Darwin.closedir($0) } ?? Darwin.close(descriptor)
            let saved = errno
            slot.closeResult = result; slot.closeErrno = saved
            if result == 0 { slot.state = .closed }
            else { slot.state = .uncertain; uncertain.append(slot); poisoned = true }
            guard result == 0 else { throw EraseAllServiceError.invalidAuthority }
        }
        func retainAfterFailure(_ slot: Slot) {
            // A failed held/named proof cannot authorize a close of this
            // numeric FD. Retain the real returned FD/cursor and its owner;
            // the uncertain lexical window is never reused or settled.
            slot.state = .uncertain
            retainUncertain(slot)
        }
        func consume(_ slot: Slot) throws {
            guard !poisoned, active.last === slot, slot.state == .closed,
                  slot.closeResult == 0, slot.closeErrno != nil, slot.openResult == slot.descriptor,
                  let beforeParent = slot.parentBeforeCloseFact, let afterParent = slot.parentAfterCloseFact,
                  OriginalEraseScratchCleanupImageOwnerV1.full(beforeParent) == OriginalEraseScratchCleanupImageOwnerV1.full(afterParent) else {
                throw EraseAllServiceError.invalidAuthority
            }
            let next = consumed.addingReportingOverflow(1)
            guard !next.overflow, next.partialValue <= entered else { throw EraseAllServiceError.invalidAuthority }
            // Lexical scanner consumers have returned with their full facts,
            // hashes and values. Only this exact next association retires the
            // previous closed slot; no numeric closed descriptor is reprobed.
            var fields = [slot.sequence.littleEndian, UInt64(UInt32(bitPattern: slot.descriptor!)).littleEndian,
                UInt64(UInt32(bitPattern: slot.openErrno!)).littleEndian,
                UInt64(UInt32(bitPattern: slot.closeErrno!)).littleEndian]
            fields.withUnsafeBufferPointer { transcript.update(bufferPointer: UnsafeRawBufferPointer($0)) }
            lastConsumed = slot; active.removeLast(); consumed = next.partialValue
        }
        func requireCheckedSettlement() throws {
            guard !poisoned, uncertain.isEmpty, active.isEmpty, entered == consumed,
                  entered == 0 || (lastConsumed?.state == .closed && lastConsumed?.closeResult == 0) else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        func poison() { poisoned = true }
    }
    private var coldObservationResources: ColdObservationResources?
    private var coldObservationResourcesLease: ColdEraseScratchMechanicsIndexLeaseV1?
    private enum PublicationKey: Hashable {
        case live(UUID)
        case observed(UInt64)
    }
    private struct Publication {
        let createID: UUID?
        var observedLink: ColdEraseScratchObservedRequestLinkV1?
        var temporaryPath: String
        var finalPath: String
        let bytes: EraseScratchCleanupPayloadOriginV1
        let sha256: String
        let exclusiveFinalRename: Bool
        var written: Int
        var acceptedPolicy: Bool
        var linkID: UUID?
        var replacementID: UUID?
    }
    private var publications: [PublicationKey: Publication] = [:]
    private struct FinalizedReplacement {
        let requestID: UUID
        let sourcePath: String
        let bytes: EraseScratchCleanupPayloadOriginV1
        let sha256: String
        let fullFact: String
    }
    private var finalizedReplacements: [String:FinalizedReplacement] = [:]
    private var pathMapping: [String: String] = [:]
    private var consumed: Set<String> = []
    private var retainedSources: [String: (bytes: EraseScratchCleanupPayloadOriginV1, fullFact: String)] = [:]
    private var originalNodes: [String: EraseSchema2ColdAuxiliaryPhysicalRosterV1.Node] = [:]
    private var lastRaw: RawImage?
    private var lastPolicyNodes: [URL:OriginalEraseScratchTemporalPolicyNodeV1] = [:]
    private var lastPairs: [OriginalEraseScratchTemporalPairV1] = []
    private var activeEffectScope: OriginalEraseScratchCleanupPolicyEffectScopeV1?
    private var retainedEffectScopes: [OriginalEraseScratchCleanupPolicyEffectScopeV1] = []
    private var directorySourcePaths: [String:String] = [:]
    private var originalNodeCount = 0
    private var originalByteCount: Int64 = 0
    private var rawPayloadReadBytes: UInt64 = 0
    private var pairPayloadReadBytes: UInt64 = 0
    private var rawReadCalls: UInt64 = 0
    private var nodeVisits: UInt64 = 0
    private var cursorEntries: UInt64 = 0

    #if DEBUG
    private enum DiagnosticBoundary: String {
        case other, captureInitial, requireInitialImage, requireFinal
        case requireCanonicalSource, willPerform, didPerform
    }
    private enum DiagnosticObservation: String { case none, first, second }
    private enum DiagnosticDelta: String { case none, raw, image }
    private enum DiagnosticStage: String {
        case entry, checkedAdmission, checkedReturn, initialPremises, initialAgreement
        case requestSettlement, requestFrame, publicationRequest, requestValidation
        case outcomeFrame, policySettlement, observationAgreement, imageAgreement
        case publicationRecipes, rawScan, initialRaw, rawDelta, sameRaw
        case outsideBeforePolicy, policyBindings, policyPairs, policyCharge, policyScope
        case pairPolicy, nodePolicy, policyValidation, secondRawScan, rawAgreement
        case outsideAfterPolicy, imageDelta, observationReturn, finalDelta, commit, advance
        case deltaPrimitive, deltaCreatedNode, deltaCreatedFile
        case deltaNamespace, deltaParent, deltaOperations, deltaUntouched
    }
    private var diagnosticBoundary = DiagnosticBoundary.other
    private var diagnosticObservation = DiagnosticObservation.none
    private var diagnosticDelta = DiagnosticDelta.none
    private var diagnosticStage = DiagnosticStage.entry {
        didSet { diagnosticStageStarted = OriginalEraseScratchFirstErrorDiagnosticV1.now() }
    }
    private let diagnosticStarted = OriginalEraseScratchFirstErrorDiagnosticV1.now()
    private var diagnosticStageStarted = OriginalEraseScratchFirstErrorDiagnosticV1.now()
    private var diagnosticFirstErrorRecorded = false
    private func beginDiagnostic(_ boundary: DiagnosticBoundary) {
        diagnosticBoundary = boundary; diagnosticObservation = .none
        diagnosticDelta = .none; diagnosticStage = .entry
    }
    private func recordOriginalFailureDiagnostic(_ error: Error) {
        guard !diagnosticFirstErrorRecorded else { return }
        diagnosticFirstErrorRecorded = true
        OriginalEraseScratchFirstErrorDiagnosticV1.emit(owner: "observer",
            stage: diagnosticBoundary.rawValue + "." + diagnosticObservation.rawValue
                + "." + diagnosticDelta.rawValue + "." + diagnosticStage.rawValue,
            error: error, started: diagnosticStarted, stageStarted: diagnosticStageStarted)
    }
    #endif

    init(admission: OriginalEraseScratchCleanupInitialAdmissionV1) {
        self.admission = .original(admission); operationID = admission.operationID
    }
    init(coldAdmission: ColdEraseScratchCleanupInitialAdmissionV1) throws {
        try coldAdmission.requireHeld()
        admission = .cold(coldAdmission)
        operationID = coldAdmission.operationID
        try coldAdmission.requireHeld()
    }
    /// Called only after the genuine ColdPermit has retained this exact attempt
    /// and bound its range owner. No cold IO precedes the association/charge.
    func bindColdAttempt(_ attempt: OriginalEraseScratchCleanupAttemptV1) throws {
        guard case .cold(let coldAdmission) = admission,
              !attempted, !poisoned,
              coldAttempt == nil || coldAttempt === attempt else {
            throw EraseAllServiceError.invalidAuthority
        }
        try coldAdmission.requireHeld()
        try attempt.requireColdImageOwnerOrigin(admission: coldAdmission)
        try coldAdmission.ranges.requireBound(scope: coldAdmission.heldScope, attempt: attempt)
        coldAttempt = attempt
        guard coldObservationResources == nil, coldObservationResourcesLease == nil else { throw EraseAllServiceError.invalidAuthority }
        let lease = try coldAdmission.ranges.reserveMechanicsIndex(kind: .resourceOrder,
            minimumCapacity: 131, elementStride: UInt64(MemoryLayout<ColdObservationResources.Slot>.stride),
            retainedUTF8Bytes: 0, retainedAuxiliaryStorageBytes: ColdObservationResources.retainedSlotStorageBytes,
            attempt: attempt, scope: coldAdmission.heldScope)
        coldObservationResourcesLease = lease // reservation precedes backing
        let resources = ColdObservationResources()
        coldObservationResources = resources
        try coldAdmission.ranges.recordMechanicsIndex(lease: lease,
            actualCapacity: UInt64(resources.actualReferenceCapacity), retainedUTF8Bytes: 0,
            retainedAuxiliaryStorageBytes: ColdObservationResources.retainedSlotStorageBytes,
            attempt: attempt, scope: coldAdmission.heldScope)
        try coldAdmission.requireHeld()
    }
    /// Actual allocator capacity and retained strings are storage DATA. A
    /// genuine range owner retains every reservation, including failed ones;
    /// no capacity measurement authorizes namespace or policy effects.
    private func reserveColdIndex(kind: ColdEraseScratchMechanicsIndexKindV1,
        minimumCapacity: Int, elementStride: Int, retainedUTF8Bytes: UInt64)
        throws -> ColdEraseScratchMechanicsIndexLeaseV1 {
        guard case .cold(let coldAdmission) = admission, let attempt = coldAttempt,
              let capacity = UInt64(exactly: minimumCapacity),
              let stride = UInt64(exactly: elementStride), stride > 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        try attempt.requireColdImageOwnerOrigin(admission: coldAdmission)
        try coldAdmission.ranges.requireBound(scope: coldAdmission.heldScope, attempt: attempt)
        switch kind {
        case .imageFirstNodes: guard coldFirstNodesLease == nil else { throw EraseAllServiceError.invalidAuthority }
        case .imageMappings: guard coldMappingsLease == nil else { throw EraseAllServiceError.invalidAuthority }
        case .imageConsumedPaths: guard coldConsumedLease == nil else { throw EraseAllServiceError.invalidAuthority }
        case .imagePublications: guard coldPublicationsLease == nil else { throw EraseAllServiceError.invalidAuthority }
        default: throw EraseAllServiceError.invalidAuthority
        }
        let lease = try coldAdmission.ranges.reserveMechanicsIndex(kind: kind,
            minimumCapacity: capacity, elementStride: stride,
            retainedUTF8Bytes: retainedUTF8Bytes, attempt: attempt,
            scope: coldAdmission.heldScope)
        switch kind {
        case .imageFirstNodes: coldFirstNodesLease = lease
        case .imageMappings: coldMappingsLease = lease
        case .imageConsumedPaths: coldConsumedLease = lease
        case .imagePublications: coldPublicationsLease = lease
        default: throw EraseAllServiceError.invalidAuthority
        }
        try coldAdmission.ranges.requireBound(scope: coldAdmission.heldScope, attempt: attempt)
        return lease
    }
    private func recordColdIndex(_ lease: ColdEraseScratchMechanicsIndexLeaseV1,
        actualCapacity: Int, retainedUTF8Bytes: UInt64) throws {
        guard case .cold(let coldAdmission) = admission, let attempt = coldAttempt,
              let capacity = UInt64(exactly: actualCapacity) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try attempt.requireColdImageOwnerOrigin(admission: coldAdmission)
        try coldAdmission.ranges.requireBound(scope: coldAdmission.heldScope, attempt: attempt)
        try coldAdmission.ranges.recordMechanicsIndex(lease: lease,
            actualCapacity: capacity, retainedUTF8Bytes: retainedUTF8Bytes,
            attempt: attempt, scope: coldAdmission.heldScope)
        try coldAdmission.ranges.requireBound(scope: coldAdmission.heldScope, attempt: attempt)
    }
    /// MEMORY-only discharge proof for the actual retained lease. It is
    /// reached only through the genuine ColdPermit and actual Attempt, after
    /// the concrete backing and all helper consumers have been removed.
    func requireColdMechanicsIndexReleased(lease: ColdEraseScratchMechanicsIndexLeaseV1,
        attempt: OriginalEraseScratchCleanupAttemptV1) throws {
        guard case .cold(let coldAdmission) = admission, coldAttempt === attempt,
              !poisoned, uncertainFDs.isEmpty, uncertainDirectories.isEmpty,
              pending == nil, observationOutcome == nil, activeScope == nil,
              activeEffectScope == nil, activeCatalog == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        try coldAdmission.requireHeld()
        try attempt.requireColdCompletedImage(current)
        switch lease.kind {
        case .imageFirstNodes:
            guard coldFirstNodesLease === lease, originalNodes.isEmpty, initial == nil,
                  coldReplaySeed == nil else { throw EraseAllServiceError.invalidAuthority }
        case .imageMappings:
            guard coldMappingsLease === lease, pathMapping.isEmpty, directorySourcePaths.isEmpty,
                  coldReplaySeed == nil else { throw EraseAllServiceError.invalidAuthority }
        case .imageConsumedPaths:
            guard coldConsumedLease === lease, consumed.isEmpty, coldReplaySeed == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
        case .imagePublications:
            guard coldPublicationsLease === lease, publications.isEmpty, finalizedReplacements.isEmpty,
                  coldReplaySeed == nil else { throw EraseAllServiceError.invalidAuthority }
        case .resourceOrder:
            guard coldObservationResourcesLease === lease, coldObservationResources == nil,
                  coldTaskObservationSettlement == nil else { throw EraseAllServiceError.invalidAuthority }
        default: throw EraseAllServiceError.invalidAuthority
        }
        try coldAdmission.requireHeld()
    }

    /// The actual ColdPermit calls only after its identical returned readback
    /// was consumed by Ledger and its final held check returned. No old
    /// revoked policy scope is asked to prove a live obsolete request again.
    func consumeColdMechanicsReadback(outcome: Outcome,
        attempt: OriginalEraseScratchCleanupAttemptV1) throws {
        guard case .cold(let coldAdmission) = admission, coldAttempt === attempt,
              !poisoned, pending == nil, observationOutcome == nil,
              activeScope == nil, activeEffectScope == nil, activeCatalog == nil,
              let current else { throw EraseAllServiceError.invalidAuthority }
        try coldAdmission.requireHeld()
        try attempt.requireColdConsumedReadback(outcome: outcome, after: current)
        if case .requestPolicy = outcome.intent.kind {
            guard let scope = retainedEffectScopes.last, scope.intent === outcome.intent else {
                throw EraseAllServiceError.invalidAuthority
            }
            try scope.consumeColdPositiveOutcome(outcome)
            guard scope.coldProofConsumed else { throw EraseAllServiceError.invalidAuthority }
            retainedEffectScopes.removeLast()
        }
        // Every retained observation callback has returned and its scope
        // naturally revoked before this complete primitive consumption point.
        try settleObservationScopes()
        guard policyAttempts.count == settledPolicyAttemptCount else { throw EraseAllServiceError.invalidAuthority }
        policyAttempts.removeAll(keepingCapacity: false); settledPolicyAttemptCount = 0
        try coldAdmission.requireHeld()
    }

    /// Cold-only terminal helper backing release, never Original retention
    /// pruning or global core/progress infrastructure close. Uncertainty keeps
    /// every original owner/charge; positive actual settlement is necessary.
    func releaseColdMechanicsBackings(attempt: OriginalEraseScratchCleanupAttemptV1) throws {
        guard case .cold(let coldAdmission) = admission, coldAttempt === attempt,
              !poisoned, uncertainFDs.isEmpty, uncertainDirectories.isEmpty,
              pending == nil, observationOutcome == nil, activeScope == nil,
              activeEffectScope == nil, activeCatalog == nil,
              current?.scratch == nil, current?.ingress == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        try coldAdmission.requireHeld()
        try attempt.requireColdCompletedImage(current)
        try coldAdmission.ranges.requireScratchTasksSettled(attempt: attempt, scope: coldAdmission.heldScope)
        try settleObservationScopes()
        guard policyAttempts.count == settledPolicyAttemptCount else { throw EraseAllServiceError.invalidAuthority }
        // Cold catalogs are never issued. Each effect scope must have had its
        // positive proof consumed and naturally revoked by its actual request.
        guard retainedCatalogs.isEmpty, coldTaskObservationSettlement == nil,
              retainedEffectScopes.allSatisfy({ $0.coldProofConsumed }) else { throw EraseAllServiceError.invalidAuthority }
        try coldResourceOwner().requireCheckedSettlement()
        coldObservationResources = nil
        initial = nil; coldReplaySeed = nil; originalNodes.removeAll(keepingCapacity: false)
        pathMapping.removeAll(keepingCapacity: false); directorySourcePaths.removeAll(keepingCapacity: false)
        consumed.removeAll(keepingCapacity: false); retainedSources.removeAll(keepingCapacity: false)
        publications.removeAll(keepingCapacity: false); finalizedReplacements.removeAll(keepingCapacity: false)
        lastRaw = nil; lastPolicyNodes.removeAll(keepingCapacity: false); lastPairs.removeAll(keepingCapacity: false)
        policyAttempts.removeAll(keepingCapacity: false); settledPolicyAttemptCount = 0
        retainedEffectScopes.removeAll(keepingCapacity: false)
        try coldAdmission.requireHeld()
    }
    private static func chargeUTF8(_ string: String, total: inout UInt64) throws {
        guard let count = UInt64(exactly: string.utf8.count) else {
            throw EraseAllServiceError.invalidAuthority
        }
        let next = total.addingReportingOverflow(count)
        guard !next.overflow else { throw EraseAllServiceError.invalidAuthority }
        total = next.partialValue
    }
    fileprivate func poison() {
        poisoned = true; activeScope?.revoke(); activeEffectScope?.revoke(); admission.poisonOnUncertainCleanup()
    }
    private func requireHeld() throws {
        guard !poisoned, uncertainFDs.isEmpty, uncertainDirectories.isEmpty else {
            throw EraseAllServiceError.invalidAuthority
        }
        guard callHeldScope == nil || callHeldScope?.isSame(as: admission.heldScope) == true else {
            throw EraseAllServiceError.invalidAuthority
        }
        try admission.requireHeld()
        if let pending { try admission.requirePrimitiveRequest(intent:pending,outcome:observationOutcome) }
    }
    fileprivate func requireScope(_ scope: OriginalEraseScratchTemporalObservationScopeV1) throws {
        guard activeScope === scope, scope.operationID == operationID,
              scope.heldScope.isSame(as: admission.heldScope) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireHeld()
        if case .cold = admission {
            try scope.requirePairOrigins(admission: admission, attempt: coldAttempt)
            try requireHeld()
        }
    }
    fileprivate func retainPolicyAttempt(_ attempt: OriginalEraseScratchTemporalPolicyAttemptV1) {
        policyAttempts.append(attempt)
    }
    private func checked<T>(_ body: () throws -> T) throws -> T {
        #if DEBUG
        diagnosticStage = .checkedAdmission
        #endif
        guard callHeldScope == nil else {
            #if DEBUG
            recordOriginalFailureDiagnostic(EraseAllServiceError.invalidAuthority)
            #endif
            throw EraseAllServiceError.invalidAuthority
        }
        callHeldScope = admission.heldScope
        defer { callHeldScope = nil }
        do {
            try requireHeld(); let value = try body();
            #if DEBUG
            diagnosticDelta = .none
            diagnosticStage = .checkedReturn
            #endif
            try requireHeld(); return value
        }
        catch {
            #if DEBUG
            recordOriginalFailureDiagnostic(error)
            #endif
            poison(); throw error
        }
    }
    private func add(_ value: UInt64, to destination: inout UInt64) throws {
        let sum = destination.addingReportingOverflow(value)
        guard !sum.overflow else { throw EraseAllServiceError.invalidAuthority }
        destination = sum.partialValue
    }
    fileprivate nonisolated static func fields(_ value: String) -> [String] {
        value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    }
    fileprivate nonisolated static func nine(_ value: String) -> String {
        let a = fields(value)
        guard a.count == 11 else { return "" }
        return ([a[0], a[1], a[2]] + Array(a[5...10])).joined(separator: "|")
    }
    private nonisolated static func full(_ s: stat) -> String {
        "\(s.st_dev)|\(s.st_ino)|\(s.st_mode)|\(s.st_uid)|\(s.st_gid)|\(s.st_nlink)|\(s.st_size)|\(s.st_mtimespec.tv_sec)|\(s.st_mtimespec.tv_nsec)|\(s.st_ctimespec.tv_sec)|\(s.st_ctimespec.tv_nsec)"
    }
    private nonisolated static func path(_ value: String) throws -> [String] {
        let c = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !c.isEmpty, c.count <= 65, c.allSatisfy({ !$0.isEmpty &&
            $0 != "." && $0 != ".." && !$0.utf8.contains(0) }),
            c[0] == "ScratchDataV1" || c[0] == "ProtectedIngressReceiptsV1" else {
            throw EraseAllServiceError.invalidAuthority
        }
        return c
    }
    private nonisolated static func parent(_ path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }
    private nonisolated static func validSHA(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private nonisolated static func stable(_ a: String, _ b: String) -> Bool {
        let x = fields(a), y = fields(b)
        return x.count == 11 && y.count == 11 && Array(x[0...4]) == Array(y[0...4])
    }
    private nonisolated static func directoryMutation(_ a: String, _ b: String,
        linkDelta: Int64, beforeDirectEntryCount: Int, afterDirectEntryCount: Int) -> Bool {
        let x = fields(a), y = fields(b)
        guard stable(a,b), let old = Int64(x[5]), let new = Int64(y[5]),
              EraseDirectoryEntryLinkModelV1.matches(linkCount:old,directEntryCount:beforeDirectEntryCount),
              EraseDirectoryEntryLinkModelV1.matches(linkCount:new,directEntryCount:afterDirectEntryCount),
              let size = Int64(y[6]), size >= 0 else { return false }
        let next = old.addingReportingOverflow(linkDelta)
        return !next.overflow && next.partialValue == new
    }
    fileprivate nonisolated static func ctimeOnly(_ a: String, _ b: String, linkDelta: Int64 = 0) -> Bool {
        let x = fields(a), y = fields(b)
        guard stable(a,b), let old = Int64(x[5]), let new = Int64(y[5]),
              Array(x[6...8]) == Array(y[6...8]) else { return false }
        let next = old.addingReportingOverflow(linkDelta)
        return !next.overflow && next.partialValue == new
    }

    func captureInitial(support: Int32, caches: Int32, temporary: Int32,
        operations: Int32) throws -> Image {
        #if DEBUG
        beginDiagnostic(.captureInitial)
        #endif
        return try checked {
            #if DEBUG
            diagnosticStage = .initialPremises
            #endif
            guard !attempted else { throw EraseAllServiceError.invalidAuthority }
            attempted = true
            guard case .original(let originalAdmission) = admission,
                  try originalAdmission.observer.firstObservation() == admission.firstSnapshot,
                  originalAdmission.policyReceipt.checkedSettled,
                  admission.applicationSupportURL.isFileURL,
                  let tree = admission.physicalRoster.record.trees.first(where: {
                    $0.key == "support/FieldEvidenceOperations"
                  }), tree.state == "present", let nodes = tree.nodes else {
                throw EraseAllServiceError.invalidAuthority
            }
            for node in nodes {
                guard originalNodes.updateValue(node, forKey: node.path) == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let count = originalNodeCount.addingReportingOverflow(1)
                guard !count.overflow else { throw EraseAllServiceError.invalidAuthority }
                originalNodeCount = count.partialValue
                if node.kind == "directory" { directorySourcePaths[node.path] = node.path }
                if let sha = node.sha256 {
                    let f = node.fact.split(separator: "|").map(String.init)
                    guard f.count == 9, let bytes = Int64(f[4]), bytes >= 0,
                          Self.validSHA(sha) else { throw EraseAllServiceError.invalidAuthority }
                    let next = originalByteCount.addingReportingOverflow(bytes)
                    guard !next.overflow else { throw EraseAllServiceError.invalidAuthority }
                    originalByteCount = next.partialValue
                }
            }
            try validateOriginalPremises()
            #if DEBUG
            diagnosticObservation = .first
            #endif
            let one = try observe(support: support, caches: caches, temporary: temporary,
                operations: operations, outcome: nil, initialCapture: true)
            #if DEBUG
            diagnosticObservation = .second
            #endif
            let two = try observe(support: support, caches: caches, temporary: temporary,
                operations: operations, outcome: nil, initialCapture: true)
            #if DEBUG
            diagnosticStage = .initialAgreement
            #endif
            guard one == two else { throw EraseAllServiceError.invalidAuthority }
            initial = one; current = one; return one
        }
    }
    /// A fresh cold process receives only the privately proved current prefix.
    /// Authentic first facts remain a separate range-backed catalog; vanished
    /// first paths are never replaced with invented current ownership fields.
    func captureColdInitial(support: Int32, caches: Int32, temporary: Int32,
        operations: Int32) throws -> Image {
        #if DEBUG
        beginDiagnostic(.captureInitial)
        #endif
        return try checked {
            guard !attempted, case .cold(let coldAdmission) = admission,
                  let attempt = coldAttempt,
                  coldAdmission.applicationSupportURL.isFileURL,
                  let tree = coldAdmission.physicalRoster.record.trees.first(where: {
                    $0.key == "support/FieldEvidenceOperations"
                  }), tree.state == "present", let nodes = tree.nodes else {
                throw EraseAllServiceError.invalidAuthority
            }
            try attempt.requireColdImageOwnerOrigin(admission: coldAdmission)
            try coldAdmission.ranges.requireBound(scope: coldAdmission.heldScope, attempt: attempt)
            attempted = true
            let seed = try coldAdmission.replaySeed()
            var nodeUTF8: UInt64 = 0
            for node in nodes {
                try Self.chargeUTF8(node.path, total: &nodeUTF8)
                try Self.chargeUTF8(node.path, total: &nodeUTF8) // dictionary key and node path
                try Self.chargeUTF8(node.fact, total: &nodeUTF8)
                if let sha = node.sha256 { try Self.chargeUTF8(sha, total: &nodeUTF8) }
                for member in node.members ?? [] { try Self.chargeUTF8(member, total: &nodeUTF8) }
            }
            let firstLease = try reserveColdIndex(kind: .imageFirstNodes,
                minimumCapacity: nodes.count,
                elementStride: MemoryLayout<(String, EraseSchema2ColdAuxiliaryPhysicalRosterV1.Node)>.stride,
                retainedUTF8Bytes: nodeUTF8)
            originalNodes.reserveCapacity(nodes.count)
            try recordColdIndex(firstLease, actualCapacity: originalNodes.capacity,
                retainedUTF8Bytes: nodeUTF8)
            for node in nodes {
                guard originalNodes.updateValue(node, forKey: node.path) == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let count = originalNodeCount.addingReportingOverflow(1)
                guard !count.overflow else { throw EraseAllServiceError.invalidAuthority }
                originalNodeCount = count.partialValue
                if let sha = node.sha256 {
                    let fact = node.fact.split(separator: "|").map(String.init)
                    guard fact.count == 9, let bytes = Int64(fact[4]), bytes >= 0,
                          Self.validSHA(sha) else { throw EraseAllServiceError.invalidAuthority }
                    let sum = originalByteCount.addingReportingOverflow(bytes)
                    guard !sum.overflow else { throw EraseAllServiceError.invalidAuthority }
                    originalByteCount = sum.partialValue
                }
            }
            // The genuine seed has already proved the complete REQUEST/OBS
            // chain and physical prefix; these are comparison indexes only.
            guard seed.consumedFirstPaths.allSatisfy({ originalNodes[$0] != nil }),
                  seed.pathMapping.allSatisfy({ originalNodes[$0.key] != nil }),
                  seed.directorySourcePaths.allSatisfy({ originalNodes[$0.value]?.kind == "directory" }) else {
                throw EraseAllServiceError.invalidAuthority
            }
            var mappingUTF8: UInt64 = 0
            for (from, to) in seed.pathMapping {
                try Self.chargeUTF8(from, total: &mappingUTF8)
                try Self.chargeUTF8(to, total: &mappingUTF8)
            }
            for (from, to) in seed.directorySourcePaths {
                try Self.chargeUTF8(from, total: &mappingUTF8)
                try Self.chargeUTF8(to, total: &mappingUTF8)
            }
            let mappingCount = seed.pathMapping.count.addingReportingOverflow(seed.directorySourcePaths.count)
            guard !mappingCount.overflow else { throw EraseAllServiceError.invalidAuthority }
            let mappingLease = try reserveColdIndex(kind: .imageMappings,
                minimumCapacity: mappingCount.partialValue,
                elementStride: MemoryLayout<(String, String)>.stride,
                retainedUTF8Bytes: mappingUTF8)
            pathMapping = seed.pathMapping; directorySourcePaths = seed.directorySourcePaths
            let mappingCapacity = pathMapping.capacity.addingReportingOverflow(directorySourcePaths.capacity)
            guard !mappingCapacity.overflow else { throw EraseAllServiceError.invalidAuthority }
            try recordColdIndex(mappingLease, actualCapacity: mappingCapacity.partialValue,
                retainedUTF8Bytes: mappingUTF8)
            var consumedUTF8: UInt64 = 0
            for path in seed.consumedFirstPaths { try Self.chargeUTF8(path, total: &consumedUTF8) }
            let consumedLease = try reserveColdIndex(kind: .imageConsumedPaths,
                minimumCapacity: seed.consumedFirstPaths.count,
                elementStride: MemoryLayout<String>.stride,
                retainedUTF8Bytes: consumedUTF8)
            consumed = seed.consumedFirstPaths
            try recordColdIndex(consumedLease, actualCapacity: consumed.capacity,
                retainedUTF8Bytes: consumedUTF8)
            var generatedUTF8: UInt64 = 0
            for lineage in seed.generated {
                try Self.chargeUTF8(lineage.temporaryPath, total: &generatedUTF8)
                try Self.chargeUTF8(lineage.finalPath, total: &generatedUTF8)
                try Self.chargeUTF8(lineage.range.sha256, total: &generatedUTF8)
                try Self.chargeUTF8(lineage.range.originalPath, total: &generatedUTF8)
                try Self.chargeUTF8(lineage.range.firstFullFact, total: &generatedUTF8)
                try Self.chargeUTF8(lineage.sourceRequestSHA256, total: &generatedUTF8)
            }
            let publicationLease = try reserveColdIndex(kind: .imagePublications,
                minimumCapacity: seed.generated.count,
                elementStride: MemoryLayout<(PublicationKey, Publication)>.stride,
                retainedUTF8Bytes: generatedUTF8)
            publications.reserveCapacity(seed.generated.count)
            try recordColdIndex(publicationLease, actualCapacity: publications.capacity,
                retainedUTF8Bytes: generatedUTF8)
            for lineage in seed.generated {
                guard lineage.taskSequence > 0,
                      lineage.range.ownerIdentity == ObjectIdentifier(coldAdmission.ranges),
                      let written = Int(exactly: lineage.writtenCount),
                      written <= (try EraseScratchCleanupPayloadOriginV1.cold(lineage.range).byteCount()),
                      publications[.observed(lineage.taskSequence)] == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
                // An observed prefix uses its genuine retained REQUEST handle;
                // it never fabricates live create/link/close identities.
                let link = lineage.observedRequestLink
                if case .linked = lineage.stage {
                    guard let link else { throw EraseAllServiceError.invalidAuthority }
                    try coldAdmission.ranges.requireObservedRequestLink(handle: link,
                        scope: coldAdmission.heldScope, attempt: attempt)
                } else if link != nil { throw EraseAllServiceError.invalidAuthority }
                publications[.observed(lineage.taskSequence)] = Publication(createID: nil,
                    observedLink: link, temporaryPath: lineage.temporaryPath,
                    finalPath: lineage.finalPath, bytes: .cold(lineage.range),
                    sha256: lineage.range.sha256, exclusiveFinalRename: lineage.exclusiveFinalRename,
                    written: written, acceptedPolicy: lineage.policyAccepted,
                    linkID: nil, replacementID: nil)
            }
            coldReplaySeed = seed
            try attempt.installColdReplaySeed(seed)
            #if DEBUG
            diagnosticObservation = .first
            #endif
            let one = try observe(support: support, caches: caches, temporary: temporary,
                operations: operations, outcome: nil, initialCapture: true)
            #if DEBUG
            diagnosticObservation = .second
            #endif
            let two = try observe(support: support, caches: caches, temporary: temporary,
                operations: operations, outcome: nil, initialCapture: true)
            guard one == two, one == seed.currentImage else { throw EraseAllServiceError.invalidAuthority }
            initial = one; current = one
            try coldAdmission.ranges.requireBound(scope: coldAdmission.heldScope, attempt: attempt)
            return one
        }
    }

    func requireInitialImage(_ image: Image, support: Int32, caches: Int32,
        temporary: Int32, operations: Int32) throws {
        #if DEBUG
        beginDiagnostic(.requireInitialImage)
        #endif
        try checked {
            guard image == initial, current == initial, pending == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireImage(image, support: support, caches: caches,
                temporary: temporary, operations: operations)
        }
    }
    /// Fresh cold task comparison, reached through the actual retained permit
    /// and exact four borrowed parents. It issues neither a cut nor a Plan.
    func currentColdTaskImage(attempt: OriginalEraseScratchCleanupAttemptV1,
        support: Int32, caches: Int32, temporary: Int32, operations: Int32) throws -> Image {
        guard case .cold(let coldAdmission) = admission, coldAttempt === attempt else {
            throw EraseAllServiceError.invalidAuthority
        }
        try attempt.requireColdImageOwnerOrigin(admission: coldAdmission)
        return try checked {
            guard pending == nil, observationOutcome == nil, activeEffectScope == nil,
                  activeScope == nil, activeCatalog == nil, let current else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireImage(current, support: support, caches: caches,
                temporary: temporary, operations: operations)
            try attempt.requireColdTaskImageComparison(image: current)
            try requireHeld()
            return current
        }
    }
    func observeColdTaskSettlement(task: ColdEraseScratchPendingTaskV1,
        attempt: OriginalEraseScratchCleanupAttemptV1, support: Int32,
        caches: Int32, temporary: Int32, operations: Int32)
        throws -> ColdEraseScratchTaskObservationSettlementV1 {
        guard case .cold(let coldAdmission) = admission, coldAttempt === attempt else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try checked {
            guard pending == nil, observationOutcome == nil, activeScope == nil,
                  activeEffectScope == nil, activeCatalog == nil, let current else {
                throw EraseAllServiceError.invalidAuthority
            }
            try attempt.requireColdTaskPostimage(task: task, after: current)
            // This is the actual incumbent complete two-observation check,
            // including every raw byte/hash/full fact/policy/outside branch.
            try requireImage(current, support: support, caches: caches,
                temporary: temporary, operations: operations)
            try settleObservationScopes()
            guard policyAttempts.count == settledPolicyAttemptCount,
                  uncertainFDs.isEmpty, uncertainDirectories.isEmpty,
                  activeScope == nil, activeEffectScope == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            try coldResourceOwner().requireCheckedSettlement()
            try attempt.requireColdTaskPostimage(task: task, after: current)
            let origin = try attempt.coldTaskSettlementOrigin(task: task, after: current)
            try coldAdmission.ranges.requireBound(scope: coldAdmission.heldScope, attempt: attempt)
            try requireHeld()
            if let prior = coldTaskObservationSettlement {
                guard !prior.consumed, prior.task === task,
                      prior.sequence == attempt.checkedPrimitiveSequence,
                      prior.image == current, prior.origin == origin else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try prior.requireBound(task: task, attempt: attempt,
                    scope: coldAdmission.heldScope, after: current)
                return prior // same proof DATA, after a new full live reproof
            }
            let proof = ColdEraseScratchTaskObservationSettlementV1(owner: self,
                task: task, attempt: attempt, scope: coldAdmission.heldScope,
                image: current, origin: origin, sequence: attempt.checkedPrimitiveSequence)
            coldTaskObservationSettlement = proof
            try proof.requireBound(task: task, attempt: attempt,
                scope: coldAdmission.heldScope, after: current)
            try requireHeld(); return proof
        }
    }

    fileprivate func requireColdTaskObservationSettlement(
        _ proof: ColdEraseScratchTaskObservationSettlementV1,
        task: ColdEraseScratchPendingTaskV1, attempt: OriginalEraseScratchCleanupAttemptV1,
        scope: ColdEraseScratchCleanupHeldGScopeV1, after: Image) throws {
        guard case .cold(let coldAdmission) = admission, coldAttempt === attempt,
              coldAdmission.heldScope === scope, coldTaskObservationSettlement === proof,
              !proof.consumed, proof.task === task, proof.image == after,
              proof.sequence == attempt.checkedPrimitiveSequence, current == after,
              !poisoned, pending == nil, observationOutcome == nil,
              activeScope == nil, activeEffectScope == nil, activeCatalog == nil,
              uncertainFDs.isEmpty, uncertainDirectories.isEmpty,
              policyAttempts.count == settledPolicyAttemptCount else {
            throw EraseAllServiceError.invalidAuthority
        }
        try coldAdmission.requireHeld()
        try attempt.requireColdTaskPostimage(task: task, after: after)
        guard try attempt.coldTaskSettlementOrigin(task: task, after: after) == proof.origin else {
            throw EraseAllServiceError.invalidAuthority
        }
        for actual in policyAttempts { try actual.requireCheckedSettlement() }
        try coldResourceOwner().requireCheckedSettlement()
        try coldAdmission.requireHeld()
    }

    func retireColdTaskObservationSettlement(_ proof: ColdEraseScratchTaskObservationSettlementV1,
        task: ColdEraseScratchPendingTaskV1, settled: ColdEraseScratchSettledTaskV1,
        attempt: OriginalEraseScratchCleanupAttemptV1) throws {
        guard case .cold(let coldAdmission) = admission, coldAttempt === attempt,
              coldTaskObservationSettlement === proof, let current else { throw EraseAllServiceError.invalidAuthority }
        try proof.requireBound(task: task, attempt: attempt, scope: coldAdmission.heldScope, after: current)
        try coldAdmission.ranges.requireSettledTask(task: settled, pending: task, proof: proof,
            attempt: attempt, scope: coldAdmission.heldScope)
        try requireHeld()
        try proof.consume(owner: self)
        coldTaskObservationSettlement = nil
        try requireHeld()
    }

    func requireFinal(_ image: Image, support: Int32, caches: Int32,
        temporary: Int32, operations: Int32) throws {
        #if DEBUG
        beginDiagnostic(.requireFinal)
        #endif
        try checked {
            guard pending == nil, image == current else { throw EraseAllServiceError.invalidAuthority }
            try requireImage(image, support: support, caches: caches,
                temporary: temporary, operations: operations)
        }
    }
    private func retainPayload(_ bytes: Data, temporaryPath: String)
        throws -> EraseScratchCleanupPayloadOriginV1 {
        switch admission {
        case .original: return .original(bytes)
        case .cold:
            guard let attempt = coldAttempt else { throw EraseAllServiceError.invalidAuthority }
            return .cold(try attempt.requireColdPendingRecipePayload(
                temporaryPath: temporaryPath, bytes: bytes))
        }
    }
    private func retainCanonicalPayload(_ bytes: Data, path: String, fullFact: String)
        throws -> EraseScratchCleanupPayloadOriginV1 {
        switch admission {
        case .original: return .original(bytes)
        case .cold(let coldAdmission):
            guard let attempt = coldAttempt else { throw EraseAllServiceError.invalidAuthority }
            try coldAdmission.ranges.requireBound(scope: coldAdmission.heldScope, attempt: attempt)
            let range = try coldAdmission.ranges.canonicalSource(path: path, fullFact: fullFact)
            let value = EraseScratchCleanupPayloadOriginV1.cold(range)
            guard try value.matches(bytes: bytes, admission: admission, attempt: attempt) else {
                throw EraseAllServiceError.invalidAuthority
            }
            return value
        }
    }
    private func withPayloadBytes<T>(_ payload: EraseScratchCleanupPayloadOriginV1,
        _ body: (Data) throws -> T) throws -> T {
        switch (payload, admission) {
        case (.original(let bytes), .original): return try body(bytes)
        case (.cold(let range), .cold(let coldAdmission)):
            guard let attempt = coldAttempt else { throw EraseAllServiceError.invalidAuthority }
            return try coldAdmission.ranges.withCanonicalBytes(range: range,
                scope: coldAdmission.heldScope, attempt: attempt, body)
        default: throw EraseAllServiceError.invalidAuthority
        }
    }
    private func withPayloadPairBytes<T>(_ first: EraseScratchCleanupPayloadOriginV1,
        _ second: EraseScratchCleanupPayloadOriginV1,
        _ body: (Data, Data) throws -> T) throws -> T {
        switch (first, second, admission) {
        case (.original(let a), .original(let b), .original): return try body(a, b)
        case (.cold(let a), .cold(let b), .cold(let coldAdmission)):
            guard let attempt = coldAttempt else { throw EraseAllServiceError.invalidAuthority }
            return try coldAdmission.ranges.withCanonicalPairBytes(first: a, second: b,
                scope: coldAdmission.heldScope, attempt: attempt, body)
        default: throw EraseAllServiceError.invalidAuthority
        }
    }
    func requireCanonicalSource(path: String, bytes: Data, fullFact: String) throws {
        #if DEBUG
        beginDiagnostic(.requireCanonicalSource)
        #endif
        try checked {
            _ = try Self.path(path)
            guard let image = current, let node = Self.nodes(image)[path],
                  node.fullFact == fullFact,
                  node.contentSHA256 == StoreMigrationCanonicalJSONV1.sha256(bytes),
                  Int64(bytes.count) == Int64(Self.fields(fullFact)[6]) else {
                throw EraseAllServiceError.invalidAuthority
            }
            let ownVersion = try publications.values.contains {
                guard $0.finalPath == path else { return false }
                guard try $0.bytes.matches(bytes: bytes,
                    admission: admission, attempt: coldAttempt) else { return false }
                return $0.written == bytes.count && $0.acceptedPolicy
            } || finalizedReplacements[path].map {
                (try $0.bytes.matches(bytes: bytes, admission: admission, attempt: coldAttempt))
                    && $0.fullFact == fullFact && $0.sha256 == node.contentSHA256
            } == true
            if !ownVersion {
                try admission.requireCanonicalSource(path: path, bytes: bytes, fullFact: fullFact)
                if let old = retainedSources[path] {
                    guard try old.bytes.matches(bytes: bytes, admission: admission, attempt: coldAttempt),
                          old.fullFact == fullFact else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                } else {
                    retainedSources[path] = (try retainCanonicalPayload(bytes, path: path,
                        fullFact: fullFact), fullFact)
                }
            }
            // Original bytes stay retained; own newer versions are retained in
            // each immutable create recipe, even after their paths disappear.
        }
    }
    func willPerform(_ intent: Intent, support: Int32, caches: Int32,
        temporary: Int32, operations: Int32) throws {
        #if DEBUG
        beginDiagnostic(.willPerform)
        #endif
        try checked {
            #if DEBUG
            diagnosticStage = .requestSettlement
            #endif
            try settleObservationScopes()
            #if DEBUG
            diagnosticStage = .requestFrame
            #endif
            guard activeCatalog == nil, pending == nil, intent.operationID == operationID,
                  intent.before == current,
                  attemptID == nil || attemptID == intent.attemptID,
                  nextSequence == nil || nextSequence == intent.sequence else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireImage(intent.before, support: support, caches: caches,
                temporary: temporary, operations: operations)
            if case .createTemporary = intent.kind {
                #if DEBUG
                diagnosticStage = .publicationRequest
                #endif
                try admission.requirePublicationRequest(intent: intent)
            }
            #if DEBUG
            diagnosticStage = .requestValidation
            #endif
            try validateRequest(intent)
            // Retain exact intent before the first effect; no future outcome.
            attemptID = intent.attemptID; pending = intent
        }
    }
    func didPerform(_ outcome: Outcome, support: Int32, caches: Int32,
        temporary: Int32, operations: Int32) throws -> Image {
        #if DEBUG
        beginDiagnostic(.didPerform)
        diagnosticStage = .outcomeFrame
        #endif
        guard pending === outcome.intent else {
            #if DEBUG
            recordOriginalFailureDiagnostic(EraseAllServiceError.invalidAuthority)
            #endif
            poison(); throw EraseAllServiceError.invalidAuthority
        }
        observationOutcome = outcome
        defer { observationOutcome = nil }
        return try checked {
            #if DEBUG
            diagnosticStage = .outcomeFrame
            #endif
            guard outcome.intent.operationID == operationID,
                  outcome.result >= 0 else { throw EraseAllServiceError.invalidAuthority }
            if case .requestPolicy = outcome.intent.kind {
                #if DEBUG
                diagnosticStage = .policySettlement
                #endif
                guard let scope = activeEffectScope else { throw EraseAllServiceError.invalidAuthority }
                try scope.requireCheckedSettlement()
                if case .cold = admission { try scope.retainColdPositiveOutcome(outcome) }
                scope.revoke(); activeEffectScope = nil
            }
            #if DEBUG
            diagnosticObservation = .first
            #endif
            let one = try observe(support: support, caches: caches, temporary: temporary,
                operations: operations, outcome: outcome, initialCapture: false)
            #if DEBUG
            diagnosticObservation = .second
            #endif
            let two = try observe(support: support, caches: caches, temporary: temporary,
                operations: operations, outcome: outcome, initialCapture: false)
            #if DEBUG
            diagnosticStage = .observationAgreement
            #endif
            guard one == two else { throw EraseAllServiceError.invalidAuthority }
            #if DEBUG
            diagnosticStage = .finalDelta
            #endif
            try requireDelta(outcome, after: one)
            #if DEBUG
            diagnosticStage = .commit
            #endif
            try commit(outcome)
            #if DEBUG
            diagnosticStage = .advance
            #endif
            let next = outcome.intent.sequence.addingReportingOverflow(1)
            guard !next.overflow else { throw EraseAllServiceError.invalidAuthority }
            nextSequence = next.partialValue; current = one; pending = nil
            return one
        }
    }
    private func requireImage(_ image: Image, support: Int32, caches: Int32,
        temporary: Int32, operations: Int32) throws {
        #if DEBUG
        diagnosticObservation = .first
        #endif
        let one = try observe(support: support, caches: caches, temporary: temporary,
            operations: operations, outcome: nil, initialCapture: false)
        #if DEBUG
        diagnosticObservation = .second
        #endif
        let two = try observe(support: support, caches: caches, temporary: temporary,
            operations: operations, outcome: nil, initialCapture: false)
        #if DEBUG
        diagnosticStage = .imageAgreement
        #endif
        guard one == image, two == image else { throw EraseAllServiceError.invalidAuthority }
    }

    private func validateOriginalPremises() throws {
        var covered = Set<String>()
        for premise in admission.originalGenericPairs ?? [] {
            guard premise.originalPaths.count == 2, premise.originalFacts.count == 2,
                  premise.originalPaths == premise.originalPaths.sorted(by: {
                    $0.utf8.lexicographicallyPrecedes($1.utf8)
                  }), Set(premise.originalPaths).count == 2,
                  premise.originalFacts[0] == premise.originalFacts[1],
                  Self.validSHA(premise.sha256), premise.byteCount >= 0,
                  Self.parent(premise.originalPaths[0]) == Self.parent(premise.originalPaths[1]) else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (path, fact) in zip(premise.originalPaths, premise.originalFacts) {
                _ = try Self.path(path)
                guard covered.insert(path).inserted,
                      let original = originalNodes[path], original.kind == "file",
                      original.fact == fact, original.sha256 == premise.sha256 else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let f = fact.split(separator: "|").map(String.init)
                guard f.count == 9, f[3] == "2", Int64(f[4]) == premise.byteCount else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            let parent = Self.parent(premise.originalPaths[0])
            let metadataPath = parent + "/lease.json"
            switch premise.metadata {
            case .validatedLease(let directory, let bytes, let sha):
                guard directory == parent, bytes.count <= 65_536,
                      Self.validSHA(sha), StoreMigrationCanonicalJSONV1.sha256(bytes) == sha,
                      originalNodes[metadataPath]?.sha256 == sha else {
                    throw EraseAllServiceError.invalidAuthority
                }
                // Canonical typed metadata/source ownership was checked by the
                // genuine earlier capture and is independently bound by Router.
            case .ownedOrphan(let directory):
                guard directory == parent, originalNodes[metadataPath] == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            guard originalByteCount >= premise.byteCount else {
                throw EraseAllServiceError.invalidAuthority
            }
            originalByteCount -= premise.byteCount // only this proven two-member row
        }
        for node in originalNodes.values where node.kind == "file" {
            let f = node.fact.split(separator: "|").map(String.init)
            guard f.count == 9, f[3] == "1" || (f[3] == "2" && covered.contains(node.path)) else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }
    private struct RawNode {
        let path: String // Operations relative
        let fact: stat
        let sha256: String?
        let members: [String]?
        var fullFact: String { OriginalEraseScratchCleanupImageOwnerV1.full(fact) }
    }
    private struct RawRoot {
        let name: String
        let digest: String
        let nodes: [RawNode]
        var fullFact: String { nodes.first(where: { $0.path == name })!.fullFact }
    }
    private struct RawImage {
        let operationsFact: stat
        let operationsNames: [String]
        let scratch: RawRoot?
        let ingress: RawRoot?
        let nodes: [String:RawNode]
    }
    private func withOpen<T>(parent: Int32, name: String, flags: Int32,
        _ body: (Int32) throws -> T) throws -> T {
        if case .cold = admission {
            return try withColdOpen(parent: parent, name: name, flags: flags, body)
        }
        try requireHeld()
        let fd = Darwin.openat(parent, name, flags | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw EraseAllServiceError.invalidAuthority }
        var closeAttempted = false
        do {
            try requireHeld(); let value = try body(fd); try requireHeld()
            closeAttempted = true
            guard Darwin.close(fd) == 0 else {
                #if DEBUG
                recordOriginalFailureDiagnostic(EraseAllServiceError.invalidAuthority)
                #endif
                uncertainFDs.append(fd); poison(); throw EraseAllServiceError.invalidAuthority
            }
            try requireHeld(); return value
        } catch {
            #if DEBUG
            recordOriginalFailureDiagnostic(error)
            #endif
            if !closeAttempted {
                closeAttempted = true
                if Darwin.close(fd) != 0 { uncertainFDs.append(fd) }
            }
            poison(); throw error
        }
    }
    private func coldResourceOwner() throws -> ColdObservationResources {
        guard case .cold(let actual) = admission, let attempt = coldAttempt else { throw EraseAllServiceError.invalidAuthority }
        try attempt.requireColdImageOwnerOrigin(admission: actual)
        try actual.requireHeld()
        guard let owner = coldObservationResources else { throw EraseAllServiceError.invalidAuthority }
        return owner
    }
    private func withColdOpen<T>(parent: Int32, name: String, flags: Int32,
        _ body: (Int32) throws -> T) throws -> T {
        let owner = try coldResourceOwner(); try requireHeld()
        let slot = try owner.prepare()
        let fd = Darwin.openat(parent, name, flags | O_NOFOLLOW | O_CLOEXEC)
        let saved = errno
        do {
            try owner.capture(slot, descriptor: fd, savedErrno: saved)
            try requireHeld(); let value = try body(fd); try requireHeld()
            slot.beforeCloseFact = try held(fd)
            slot.beforeCloseNamedFact = try named(parent, name)
            slot.parentBeforeCloseFact = try held(parent)
            try owner.close(slot); try requireHeld()
            slot.parentAfterCloseFact = try held(parent)
            try owner.consume(slot)
            return value
        } catch {
            let failure = error
            if slot.state == .open || slot.state == .cursor || slot.state == .uncertain {
                owner.retainAfterFailure(slot)
                if let directory = slot.directory { uncertainDirectories.append(directory) }
                else if let descriptor = slot.descriptor { uncertainFDs.append(descriptor) }
            }
            owner.poison(); poison(); throw failure
        }
    }
    private func coldNames(_ fd: Int32, maximum: Int) throws -> [String] {
        let owner = try coldResourceOwner(); try requireHeld()
        guard maximum >= 0 else { throw EraseAllServiceError.invalidAuthority }
        let bound = maximum.addingReportingOverflow(3)
        guard !bound.overflow else { throw EraseAllServiceError.invalidAuthority }
        let slot = try owner.prepare()
        let copy = Darwin.openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        let saved = errno
        do {
            try owner.capture(slot, descriptor: copy, savedErrno: saved); try requireHeld()
            let parentFact = try held(fd), cursorFact = try held(copy)
            guard Self.full(parentFact) == Self.full(cursorFact),
                  try named(fd, ".").map(Self.full) == Self.full(cursorFact) else { throw EraseAllServiceError.invalidAuthority }
            try owner.enterCursor(slot)
            let directory = Darwin.fdopendir(copy); let cursorErrno = errno
            try owner.captureCursor(slot, directory: directory, savedErrno: cursorErrno)
            guard let directory else { throw EraseAllServiceError.invalidAuthority }
            var values = [String](), calls = 0
            while true {
                guard calls < bound.partialValue else { throw EraseAllServiceError.invalidAuthority }
                calls += 1; try requireHeld(); errno = 0
                let entry = Darwin.readdir(directory); let actualErrno = errno
                try add(1, to: &cursorEntries); try requireHeld()
                guard let entry else { guard actualErrno == 0 else { throw EraseAllServiceError.invalidAuthority }; break }
                guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else { throw EraseAllServiceError.invalidAuthority }
                if name != "." && name != ".." {
                    guard values.count < maximum else { throw EraseAllServiceError.invalidAuthority }; values.append(name)
                }
            }
            try requireHeld()
            slot.beforeCloseFact = try held(copy)
            slot.beforeCloseNamedFact = try named(fd, ".")
            slot.parentBeforeCloseFact = try held(fd)
            guard slot.beforeCloseFact.map(Self.full) == Self.full(cursorFact),
                  slot.parentBeforeCloseFact.map(Self.full) == Self.full(parentFact),
                  Set(values).count == values.count else { throw EraseAllServiceError.invalidAuthority }
            try owner.close(slot); try requireHeld()
            slot.parentAfterCloseFact = try held(fd)
            try owner.consume(slot); return values.sorted()
        } catch {
            let failure = error
            if slot.state == .open || slot.state == .cursor || slot.state == .uncertain {
                owner.retainAfterFailure(slot)
                if let directory = slot.directory { uncertainDirectories.append(directory) }
                else if let descriptor = slot.descriptor { uncertainFDs.append(descriptor) }
            }
            owner.poison(); poison(); throw failure
        }
    }
    private func named(_ parent: Int32, _ name: String) throws -> stat? {
        try requireHeld(); var s = stat()
        let result = Darwin.fstatat(parent, name, &s, AT_SYMLINK_NOFOLLOW)
        let saved = errno; try requireHeld()
        if result != 0 {
            guard saved == ENOENT else { throw EraseAllServiceError.invalidAuthority }
            return nil
        }
        return s
    }
    private func held(_ fd: Int32) throws -> stat {
        try requireHeld(); var s = stat()
        let result = Darwin.fstat(fd, &s); try requireHeld()
        guard result == 0 else { throw EraseAllServiceError.invalidAuthority }; return s
    }
    private func names(_ fd: Int32, maximum: Int) throws -> [String] {
        if case .cold = admission { return try coldNames(fd, maximum: maximum) }
        try requireHeld()
        let copy = Darwin.openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard copy >= 0 else { throw EraseAllServiceError.invalidAuthority }
        var directory: UnsafeMutablePointer<DIR>?
        var closeAttempted = false
        do {
            try requireHeld(); directory = Darwin.fdopendir(copy)
            guard let directory else { throw EraseAllServiceError.invalidAuthority }
            guard maximum >= 0 else { throw EraseAllServiceError.invalidAuthority }
            let bound = maximum.addingReportingOverflow(3)
            guard !bound.overflow else { throw EraseAllServiceError.invalidAuthority }
            var values = [String](), calls = 0
            while true {
                guard calls < bound.partialValue else { throw EraseAllServiceError.invalidAuthority }
                calls += 1
                try requireHeld(); errno = 0
                let entry = Darwin.readdir(directory); let saved = errno
                try add(1, to: &cursorEntries); try requireHeld()
                guard let entry else {
                    guard saved == 0 else { throw EraseAllServiceError.invalidAuthority }; break
                }
                guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {
                    throw EraseAllServiceError.invalidAuthority
                }
                if name != "." && name != ".." {
                    guard values.count < maximum else { throw EraseAllServiceError.invalidAuthority }
                    values.append(name)
                }
            }
            try requireHeld(); closeAttempted = true
            guard Darwin.closedir(directory) == 0 else {
                #if DEBUG
                recordOriginalFailureDiagnostic(EraseAllServiceError.invalidAuthority)
                #endif
                uncertainDirectories.append(directory); poison()
                throw EraseAllServiceError.invalidAuthority
            }
            try requireHeld()
            guard Set(values).count == values.count else { throw EraseAllServiceError.invalidAuthority }
            return values.sorted()
        } catch {
            #if DEBUG
            recordOriginalFailureDiagnostic(error)
            #endif
            if !closeAttempted {
                if let directory {
                    if Darwin.closedir(directory) != 0 { uncertainDirectories.append(directory) }
                } else if Darwin.close(copy) != 0 { uncertainFDs.append(copy) }
            }
            poison(); throw error
        }
    }
    private func hashFile(_ fd: Int32, _ fact: stat) throws -> String {
        var hash = SHA256(), offset: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while offset < fact.st_size {
            let requested = min(buffer.count, Int(fact.st_size - offset))
            try requireHeld()
            let count = buffer.withUnsafeMutableBytes {
                Darwin.pread(fd, $0.baseAddress, requested, off_t(offset))
            }
            try add(1, to: &rawReadCalls); try requireHeld()
            // A positive short read is charged as actual work. Errors,
            // including EINTR, cannot create an unbounded retry loop.
            guard count > 0, count <= requested else { throw EraseAllServiceError.invalidAuthority }
            offset += Int64(count); try add(UInt64(count), to: &rawPayloadReadBytes)
            buffer.withUnsafeBytes { raw in
                hash.update(bufferPointer: UnsafeRawBufferPointer(start: raw.baseAddress, count: count))
            }
        }
        try requireHeld(); var probe: UInt8 = 0
        let eof = Darwin.pread(fd, &probe, 1, off_t(offset))
        try add(1, to: &rawReadCalls); try requireHeld()
        guard eof == 0 else { throw EraseAllServiceError.invalidAuthority }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func candidatePublications(_ outcome: Outcome?) throws -> [PublicationKey: Publication] {
        var value = publications
        guard let outcome else { return value }
        switch outcome.intent.kind {
        case .createTemporary(let path, let final, let bytes, let sha, _, let exclusive):
            value[.live(outcome.intent.requestID)] = Publication(createID: outcome.intent.requestID,
                observedLink: nil, temporaryPath: path, finalPath: final,
                bytes: try retainPayload(bytes, temporaryPath: path), sha256: sha,
                exclusiveFinalRename: exclusive, written: 0, acceptedPolicy: false,
                linkID: nil, replacementID: nil)
        case .writeTemporary(let path, _, _):
            guard let id = value.first(where: { $0.value.temporaryPath == path })?.key,
                  let count = Int(exactly: outcome.result) else { throw EraseAllServiceError.invalidAuthority }
            guard count >= 0, count <= (try value[id]!.bytes.byteCount()) - value[id]!.written else {
                throw EraseAllServiceError.invalidAuthority
            }
            let next = value[id]!.written.addingReportingOverflow(count)
            guard !next.overflow else { throw EraseAllServiceError.invalidAuthority }
            value[id]!.written = next.partialValue
        case .requestPolicy(let path, _):
            if let id = value.first(where: { $0.value.temporaryPath == path })?.key {
                value[id]!.acceptedPolicy = true
            }
        case .linkPublication(let path, _):
            guard let id = value.first(where: { $0.value.temporaryPath == path })?.key else {
                throw EraseAllServiceError.invalidAuthority
            }
            value[id]!.linkID = outcome.intent.requestID
            if value[id]!.createID == nil {
                guard case .cold(let coldAdmission) = admission, let attempt = coldAttempt,
                      let task = attempt.currentColdPendingTask else { throw EraseAllServiceError.invalidAuthority }
                // The private owner retained this actual new LinkOutcome at
                // its raw outcome hook. Its prospective linked DATA does not
                // advance Pending.cut before the complete consumed readback.
                value[id]!.observedLink = try coldAdmission.ranges.observedRequestLink(
                    task: task, scope: coldAdmission.heldScope, attempt: attempt)
            }
        case .renamePublication(let source, let final, let exclusive):
            if !exclusive {
                if let id = value.first(where: { $0.value.finalPath == source })?.key {
                    value[id]!.finalPath = final
                    value[id]!.replacementID = outcome.intent.requestID
                } else {
                    // A real original staged retry has no live create recipe.
                    // The exact retained catalog source was already positively
                    // admitted by validateRequest and the actual Ledger helper.
                    guard let original = originalNodes[source], original.kind == "file",
                          let staged = retainedSources[source],
                          Self.nine(staged.fullFact) == original.fact,
                          staged.bytes.sha256() == original.sha256 else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
            }
        default: break
        }
        return value
    }
    private func rawScan(operations: Int32, support: Int32,
        publications recipes: [PublicationKey: Publication], outcome: Outcome?) throws -> RawImage {
        let ops = try held(operations), supportFact = try held(support)
        guard ops.st_mode & S_IFMT == S_IFDIR,
              ops.st_mode & 0o7777 == 0o700 || ops.st_mode & 0o7777 == 0o2700,
              ops.st_uid == geteuid(), ops.st_uid == supportFact.st_uid,
              ops.st_gid == ((supportFact.st_mode & S_ISGID) != 0 ? supportFact.st_gid : getegid()),
              ops.st_dev == supportFact.st_dev,
              let namedOps = try named(support, "FieldEvidenceOperations"),
              Self.full(namedOps) == Self.full(ops),
              Self.stable(Self.full(ops), admission.notificationAfter.operations.rootFact ?? "") else {
            throw EraseAllServiceError.invalidAuthority
        }
        _ = try directoryRole(path:"",fullFact:Self.full(ops),outcome:outcome)
        let prospectivePaths = Set(recipes.values.flatMap { [$0.temporaryPath,$0.finalPath] })
            .subtracting(originalNodes.keys)
        let maximumNodes = originalNodeCount.addingReportingOverflow(prospectivePaths.count)
        guard !maximumNodes.overflow, maximumNodes.partialValue > 0 else {
            throw EraseAllServiceError.invalidAuthority
        }
        var maximumBytes = originalByteCount
        for recipe in recipes.values {
            let sum = maximumBytes.addingReportingOverflow(Int64((try recipe.bytes.byteCount())))
            guard !sum.overflow else { throw EraseAllServiceError.invalidAuthority }
            maximumBytes = sum.partialValue
        }
        let namespaceBudget = maximumBytes.multipliedReportingOverflow(by: 2)
        guard !namespaceBudget.overflow else { throw EraseAllServiceError.invalidAuthority }
        let rootNames = try names(operations, maximum: admission.notificationAfter.operationsChildren.count)
        guard let rootLinks = Int64(exactly: ops.st_nlink),
              EraseDirectoryEntryLinkModelV1.matches(linkCount:rootLinks,directEntryCount:rootNames.count) else {
            throw EraseAllServiceError.invalidAuthority
        }
        var visited = 0, namespaceBytes: Int64 = 0
        let admittedOriginalPaths = Set((admission.originalGenericPairs ?? []).flatMap(\.originalPaths)
            .map { currentPath($0,outcome:outcome) })
        let publicationPaths = Set(recipes.values.filter { $0.linkID != nil || $0.observedLink != nil }
            .flatMap { [$0.temporaryPath, $0.finalPath] })
        func walk(parent: Int32, name: String, path: String, depth: Int,
            output: inout [RawNode], tokens: inout [String]) throws {
            guard depth <= 64, visited < maximumNodes.partialValue,
                  let fact = try self.named(parent, name) else { throw EraseAllServiceError.invalidAuthority }
            visited += 1; try add(1, to: &nodeVisits)
            let parentFact = try held(parent)
            guard fact.st_dev == ops.st_dev, fact.st_uid == geteuid(),
                  fact.st_gid == ((parentFact.st_mode & S_ISGID) != 0 ? parentFact.st_gid : getegid()) else { throw EraseAllServiceError.invalidAuthority }
            let directory = fact.st_mode & S_IFMT == S_IFDIR
            guard directory || fact.st_mode & S_IFMT == S_IFREG,
                  (directory ? (fact.st_mode & 0o7777 == 0o700 || fact.st_mode & 0o7777 == 0o2700)
                    : fact.st_mode & 0o7777 == 0o600) else {
                throw EraseAllServiceError.invalidAuthority
            }
            if directory { _ = try directoryRole(path:path,fullFact:Self.full(fact),outcome:outcome) }
            try withOpen(parent: parent, name: name,
                flags: O_RDONLY | O_NONBLOCK | (directory ? O_DIRECTORY : 0)) { fd in
                guard Self.full(try held(fd)) == Self.full(fact),
                      try self.named(parent,name).map(Self.full) == Self.full(fact) else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let relative = path.split(separator: "/").dropFirst().joined(separator: "/")
                func encoded(_ s: String) -> String { s.utf8.map { String(format:"%02x", $0) }.joined() }
                if directory {
                    let entries = try names(fd, maximum: maximumNodes.partialValue)
                    guard let directoryLinks = Int64(exactly: fact.st_nlink),
                          EraseDirectoryEntryLinkModelV1.matches(linkCount:directoryLinks,directEntryCount:entries.count) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    output.append(RawNode(path: path, fact: fact, sha256: nil, members: entries))
                    tokens.append("D|\(encoded(relative))|\(Self.nine(Self.full(fact)))|\(entries.map(encoded).joined(separator:","))")
                    for entry in entries {
                        try walk(parent: fd, name: entry, path: path + "/" + entry,
                            depth: depth + 1, output: &output, tokens: &tokens)
                    }
                    guard try names(fd, maximum: maximumNodes.partialValue) == entries else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                } else {
                    guard fact.st_size >= 0, fact.st_size <= maximumBytes,
                          fact.st_nlink == 1 || (fact.st_nlink == 2 &&
                            (admittedOriginalPaths.contains(path) || publicationPaths.contains(path))) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    let sum = namespaceBytes.addingReportingOverflow(Int64(fact.st_size))
                    guard !sum.overflow, sum.partialValue <= namespaceBudget.partialValue else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    namespaceBytes = sum.partialValue
                    let sha = try hashFile(fd, fact)
                    output.append(RawNode(path: path, fact: fact, sha256: sha, members: nil))
                    tokens.append("F|\(encoded(relative))|\(Self.nine(Self.full(fact)))|\(sha)")
                }
                guard Self.full(try held(fd)) == Self.full(fact),
                      try self.named(parent,name).map(Self.full) == Self.full(fact) else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        func root(_ name: String) throws -> RawRoot? {
            guard rootNames.contains(name) else {
                guard try self.named(operations,name) == nil else { throw EraseAllServiceError.invalidAuthority }
                return nil
            }
            var nodes = [RawNode](), tokens = [String]()
            try walk(parent: operations, name: name, path: name, depth: 1,
                output: &nodes, tokens: &tokens)
            return RawRoot(name: name,
                digest: StoreMigrationCanonicalJSONV1.sha256(Data(tokens.sorted().joined(separator:"\n").utf8)),
                nodes: nodes.sorted { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) })
        }
        let scratch = try root("ScratchDataV1"), ingress = try root("ProtectedIngressReceiptsV1")
        guard Self.full(try held(operations)) == Self.full(ops),
              try named(support,"FieldEvidenceOperations").map(Self.full) == Self.full(ops),
              try names(operations, maximum: admission.notificationAfter.operationsChildren.count) == rootNames else {
            throw EraseAllServiceError.invalidAuthority
        }
        var byPath = [String:RawNode]()
        for node in (scratch?.nodes ?? []) + (ingress?.nodes ?? []) {
            guard byPath.updateValue(node,forKey:node.path) == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        return RawImage(operationsFact: ops, operationsNames: rootNames,
            scratch: scratch, ingress: ingress,nodes:byPath)
    }

    private nonisolated static func nodes(_ image: Image) -> [String: Image.Node] {
        var result = [String: Image.Node]()
        for (name, root) in [("ScratchDataV1",image.scratch),
                             ("ProtectedIngressReceiptsV1",image.ingress)] {
            for node in root?.nodes ?? [] {
                result[node.path.isEmpty ? name : name + "/" + node.path] = node
            }
        }
        return result
    }
    private func currentPath(_ original: String, outcome: Outcome?) -> String {
        let path = pathMapping[original] ?? original
        if let outcome, case .renameLeaseDirectory(let from, let to) = outcome.intent.kind {
            if path == from { return to }
            if path.hasPrefix(from + "/") { return to + String(path.dropFirst(from.count)) }
        }
        return path
    }
    private func requireInitialRaw(_ raw: RawImage) throws {
        guard case .original(let admission) = self.admission else {
            throw EraseAllServiceError.invalidAuthority
        }
        let expectedPaths = Set(originalNodes.keys.filter {
            $0 == "ScratchDataV1" || $0.hasPrefix("ScratchDataV1/") ||
            $0 == "ProtectedIngressReceiptsV1" || $0.hasPrefix("ProtectedIngressReceiptsV1/")
        })
        guard Set(raw.nodes.keys) == expectedPaths,
              Self.full(raw.operationsFact) == admission.notificationAfter.operations.rootFact,
              raw.operationsNames == Array(admission.notificationAfter.operationsChildren.keys).sorted() else {
            throw EraseAllServiceError.invalidAuthority
        }
        for (path,node) in raw.nodes {
            guard let original = originalNodes[path], original.sha256 == node.sha256,
                  original.members == node.members else { throw EraseAllServiceError.invalidAuthority }
            if path == "ScratchDataV1" {
                guard let first = admission.firstSnapshot.operationsChildren[path],
                      case .directory(let originalFact, _) = first,
                      Self.nine(originalFact) == original.fact,
                      let starting = admission.scratchStartingChild,
                      case .directory(let startingFact, let startingDigest) = starting,
                      node.fullFact == startingFact,
                      raw.scratch?.digest == startingDigest else {
                    throw EraseAllServiceError.invalidAuthority
                }
            } else if path == "ProtectedIngressReceiptsV1" {
                guard node.fullFact == admission.policyReceipt.projectedRootFact,
                      raw.ingress?.digest == admission.policyReceipt.projectedTreeDigest,
                      admission.policyReceipt.firstRootFact
                        == admission.notificationAfter.ingressControlNodes?.first(where: { $0.path.isEmpty })?.fullFact else {
                    throw EraseAllServiceError.invalidAuthority
                }
            } else {
                guard Self.nine(node.fullFact) == original.fact else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        if let scratch = raw.scratch {
            guard admission.scratchStartingChild
                    == .directory(rootFact: scratch.fullFact,digest: scratch.digest) else {
                throw EraseAllServiceError.invalidAuthority
            }
        } else {
            guard admission.firstSnapshot.operationsChildren["ScratchDataV1"] == nil,
                  admission.scratchStartingChild == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        if raw.ingress == nil {
            guard admission.policyReceipt.firstRootFact == nil,
                  admission.policyReceipt.projectedRootFact == nil,
                  admission.policyReceipt.projectedTreeDigest == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }
    private func url(_ path: String) -> URL {
        path.split(separator: "/").reduce(admission.applicationSupportURL
            .appendingPathComponent("FieldEvidenceOperations",isDirectory:true)) {
                $0.appendingPathComponent(String($1))
            }
    }
    private func directoryRole(path:String,fullFact:String,outcome:Outcome?) throws -> OriginalEraseScratchPrivateDirectoryRoleV1 {
        var beforePath = path
        if let outcome, case .renameLeaseDirectory(let from,let to) = outcome.intent.kind,
           path == to || path.hasPrefix(to + "/") {
            beforePath = from + String(path.dropFirst(to.count))
        }
        guard let sourcePath = directorySourcePaths[beforePath],
              let source = originalNodes[sourcePath], source.kind == "directory" else {
            throw EraseAllServiceError.invalidAuthority
        }
        let original = source.fact.split(separator:"|").map(String.init)
        let current = Self.fields(fullFact)
        guard original.count == 9, current.count == 11,
              let recorded = UInt32(original[2]), let actual = UInt32(current[2]) else {
            throw EraseAllServiceError.invalidAuthority
        }
        let role = OriginalEraseScratchPrivateDirectoryRoleV1.originalP(sourcePath:sourcePath,recordedFullMode:recorded)
        guard role.admits(fullMode:actual) else { throw EraseAllServiceError.invalidAuthority }; return role
    }
    private func policyNode(_ node: RawNode, raw: RawImage, outcome:Outcome? = nil) throws -> OriginalEraseScratchTemporalPolicyNodeV1 {
        var ancestors = [OriginalEraseScratchTemporalPolicyNodeV1.Ancestor(
            url: url(""), fullFact: Self.full(raw.operationsFact),
            directoryRole:try directoryRole(path:"",fullFact:Self.full(raw.operationsFact),outcome:outcome))]
        var parent = ""
        for component in node.path.split(separator: "/").dropLast() {
            parent = parent.isEmpty ? String(component) : parent + "/" + component
            guard let dir = raw.nodes[parent], dir.sha256 == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            ancestors.append(.init(url: url(parent), fullFact: dir.fullFact,
                directoryRole:try directoryRole(path:parent,fullFact:dir.fullFact,outcome:outcome)))
        }
        guard let last = ancestors.last else { throw EraseAllServiceError.invalidAuthority }
        return OriginalEraseScratchTemporalPolicyNodeV1(
            kind: node.sha256 == nil ? .stagingDirectory : .temporaryFile,
            directoryRole:node.sha256 == nil ? try directoryRole(path:node.path,fullFact:node.fullFact,outcome:outcome) : nil,
            url: url(node.path), fullFact: node.fullFact,
            parentURL: last.url, parentFullFact: last.fullFact, ancestors: ancestors)
    }
    private func pair(_ paths: [String], raw: RawImage, sha: String,
        count: Int64, role: OriginalEraseScratchTemporalPairV1.Role, outcome:Outcome?) throws -> OriginalEraseScratchTemporalPairV1 {
        let sorted = paths.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        guard sorted.count == 2, Set(sorted).count == 2,
              Self.parent(sorted[0]) == Self.parent(sorted[1]),
              let a = raw.nodes[sorted[0]], let b = raw.nodes[sorted[1]],
              a.sha256 == sha, b.sha256 == sha, a.fullFact == b.fullFact,
              a.fact.st_nlink == 2, a.fact.st_size == count,
              a.fact.st_mode & S_IFMT == S_IFREG else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try OriginalEraseScratchTemporalPairV1(
            members: sorted.map { .init(relativePath:$0,url:url($0),fullFact:raw.nodes[$0]!.fullFact) },
            kind: .temporaryFile, sha256: sha, byteCount: count,
            device: UInt64(a.fact.st_dev), inode: UInt64(a.fact.st_ino),
            user: a.fact.st_uid, group: a.fact.st_gid,
            parent: policyNode(a,raw:raw,outcome:outcome), role: role)
    }
    private func observe(support: Int32, caches: Int32, temporary: Int32,
        operations: Int32, outcome: Outcome?, initialCapture: Bool) throws -> Image {
        #if DEBUG
        diagnosticDelta = .none
        diagnosticStage = .publicationRecipes
        #endif
        let recipes = try candidatePublications(outcome)
        #if DEBUG
        diagnosticStage = .rawScan
        #endif
        let raw = try rawScan(operations:operations,support:support,publications:recipes,
            outcome: outcome)
        #if DEBUG
        if initialCapture { diagnosticStage = .initialRaw }
        else if outcome != nil { diagnosticStage = .rawDelta }
        else { diagnosticStage = .sameRaw }
        #endif
        if initialCapture {
            switch admission {
            case .original: try requireInitialRaw(raw)
            case .cold:
                guard let seed = coldReplaySeed else { throw EraseAllServiceError.invalidAuthority }
                try requireSameRaw(seed.currentImage, raw)
            }
        }
        else if let outcome { try requireRawDelta(outcome,after:raw) }
        else {
            guard let current else { throw EraseAllServiceError.invalidAuthority }
            try requireSameRaw(current,raw)
        }
        #if DEBUG
        diagnosticDelta = .none
        diagnosticStage = .outsideBeforePolicy
        #endif
        try admission.requireOutside(operationsFact:Self.full(raw.operationsFact),
            operationsNames:raw.operationsNames,
            support:support,caches:caches,temporary:temporary,operations:operations,
            requireHeld: { try self.requireHeld() })
        #if DEBUG
        diagnosticStage = .policyBindings
        #endif
        var bindings = [URL:OriginalEraseScratchTemporalPolicyNodeV1]()
        var unaccepted = Set<String>()
        for recipe in recipes.values where !recipe.acceptedPolicy && raw.nodes[recipe.temporaryPath] != nil {
            unaccepted.insert(recipe.temporaryPath)
        }
        for node in raw.nodes.values where !unaccepted.contains(node.path) {
            let binding = try policyNode(node,raw:raw,outcome:outcome)
            guard bindings.updateValue(binding,forKey:binding.url) == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        #if DEBUG
        diagnosticStage = .policyPairs
        #endif
        var pairs = [OriginalEraseScratchTemporalPairV1](), pairPaths = Set<String>()
        for (index,premise) in (admission.originalGenericPairs ?? []).enumerated() {
            let paths = premise.originalPaths.map { currentPath($0,outcome:outcome) }
            let present = paths.filter { raw.nodes[$0] != nil }
            if present.count == 2 {
                let value = try pair(paths,raw:raw,sha:premise.sha256,count:premise.byteCount,
                    role:.admittedOriginalOwnedGenericAliases(premiseIndex:index,
                        originalPaths:premise.originalPaths,originalFacts:premise.originalFacts,
                        originalSHA256:premise.sha256,metadata:premise.metadata),outcome:outcome)
                pairs.append(value)
                for p in paths { guard pairPaths.insert(p).inserted else { throw EraseAllServiceError.invalidAuthority } }
            } else {
                for path in present {
                    guard raw.nodes[path]?.fact.st_nlink == 1 else { throw EraseAllServiceError.invalidAuthority }
                }
            }
        }
        for recipe in recipes.values {
            let paths = [recipe.temporaryPath,recipe.finalPath]
            if let link = recipe.linkID, let create = recipe.createID,
               paths.allSatisfy({ raw.nodes[$0] != nil }) {
                guard recipe.acceptedPolicy, recipe.written == (try recipe.bytes.byteCount()) else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let value = try pair(paths,raw:raw,sha:recipe.sha256,count:Int64((try recipe.bytes.byteCount())),
                    role:.declaredLinkPublication(createRequestID:create,linkRequestID:link,
                        temporaryPath:recipe.temporaryPath,finalPath:recipe.finalPath),outcome:outcome)
                pairs.append(value)
                for p in paths { guard pairPaths.insert(p).inserted else { throw EraseAllServiceError.invalidAuthority } }
            } else if let observed = recipe.observedLink,
                      paths.allSatisfy({ raw.nodes[$0] != nil }) {
                guard recipe.createID == nil,
                      recipe.acceptedPolicy, recipe.written == (try recipe.bytes.byteCount()),
                      case .cold(let coldAdmission) = admission, let attempt = coldAttempt else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try coldAdmission.ranges.requireObservedRequestLink(handle: observed,
                    scope: coldAdmission.heldScope, attempt: attempt)
                let value = try pair(paths,raw:raw,sha:recipe.sha256,
                    count:Int64(try recipe.bytes.byteCount()),
                    role:.coldObservedPrefixPublication(observed),outcome:outcome)
                pairs.append(value)
                for p in paths { guard pairPaths.insert(p).inserted else { throw EraseAllServiceError.invalidAuthority } }
            }
        }
        // Physical unique charge is permitted only after exact role/two-path
        // membership, both streamed SHA/current11 and same-inode proof above.
        #if DEBUG
        diagnosticStage = .policyCharge
        #endif
        var uniqueBytes: Int64 = 0
        for node in raw.nodes.values where node.sha256 != nil {
            let next = uniqueBytes.addingReportingOverflow(Int64(node.fact.st_size))
            guard !next.overflow else { throw EraseAllServiceError.invalidAuthority }
            uniqueBytes = next.partialValue
            if node.fact.st_nlink == 2 {
                guard pairPaths.contains(node.path) else { throw EraseAllServiceError.invalidAuthority }
            }
        }
        for pair in pairs { uniqueBytes -= pair.byteCount }
        var byteBound = originalByteCount
        for recipe in recipes.values {
            let sum = byteBound.addingReportingOverflow(Int64((try recipe.bytes.byteCount())))
            guard !sum.overflow else { throw EraseAllServiceError.invalidAuthority }; byteBound = sum.partialValue
        }
        guard uniqueBytes >= 0, uniqueBytes <= byteBound else { throw EraseAllServiceError.invalidAuthority }
        #if DEBUG
        diagnosticStage = .policyScope
        #endif
        let scope = OriginalEraseScratchTemporalObservationScopeV1(owner:self,nodes:bindings,pairs:pairs)
        guard activeScope == nil else { throw EraseAllServiceError.invalidAuthority }
        activeScope = scope
        #if DEBUG
        if case .original = admission {
            OriginalEraseScratchIssuerDataTestsV1.issued(scope, nodes: bindings, pairs: pairs,
                support: admission.applicationSupportURL, supportIdentity: admission.firstSnapshot.supportIdentity)
        }
        #endif
        defer {
            scope.revoke(); activeScope = nil
            #if DEBUG
            if case .original = admission {
                OriginalEraseScratchIssuerDataTestsV1.naturallyRevoked(scope,
                    support: admission.applicationSupportURL)
            }
            #endif
        }
        var policies = [String:TemporalPolicyObservationV1]()
        #if DEBUG
        diagnosticStage = .pairPolicy
        #endif
        for pair in pairs {
            let work = UInt64(pair.byteCount).multipliedReportingOverflow(by:4)
            guard !work.overflow else { throw EraseAllServiceError.invalidAuthority }
            try add(work.partialValue,to:&pairPayloadReadBytes)
            let values = try ProtectedFilePolicyV1.observeOriginalEraseScratchTemporalPairWithCheckedClose(
                aliasURLs:pair.members.map(\.url),scope:scope,
                retainUncertainDescriptor:{ self.uncertainFDs.append($0); self.poison() })
            guard values.count == 2 else { throw EraseAllServiceError.invalidAuthority }
            for (member,value) in zip(pair.members,values) { policies[member.relativePath] = value }
        }
        #if DEBUG
        diagnosticStage = .nodePolicy
        #endif
        for node in raw.nodes.values.sorted(by: { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) })
            where !pairPaths.contains(node.path) && !unaccepted.contains(node.path) {
            guard let binding = bindings[url(node.path)] else { throw EraseAllServiceError.invalidAuthority }
            policies[node.path] = try ProtectedFilePolicyV1.observeOriginalEraseScratchTemporalPolicyWithCheckedClose(
                binding.kind,at:binding.url,fullFact:binding.fullFact,scope:scope,
                retainUncertainDescriptor:{ self.uncertainFDs.append($0); self.poison() })
        }
        #if DEBUG
        diagnosticStage = .policyValidation
        #endif
        for node in raw.nodes.values where !unaccepted.contains(node.path) {
            guard let value = policies[node.path], value.device == UInt64(node.fact.st_dev),
                  value.inode == UInt64(node.fact.st_ino), value.mode == UInt16(node.fact.st_mode),
                  value.linkCount == UInt64(node.fact.st_nlink),
                  value.isDirectory == (node.fact.st_mode & S_IFMT == S_IFDIR),
                  value.backupExcluded == true,
                  value.state == .strictComplete || value.state == .pendingSimulatorRequest else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        #if DEBUG
        diagnosticStage = .secondRawScan
        #endif
        let second = try rawScan(operations:operations,support:support,publications:recipes,
            outcome: outcome)
        #if DEBUG
        diagnosticStage = .rawAgreement
        #endif
        guard Self.sameRaw(raw,second) else { throw EraseAllServiceError.invalidAuthority }
        #if DEBUG
        diagnosticStage = .outsideAfterPolicy
        #endif
        try admission.requireOutside(operationsFact:Self.full(raw.operationsFact),
            operationsNames:raw.operationsNames,
            support:support,caches:caches,temporary:temporary,operations:operations,
            requireHeld:{ try self.requireHeld() })
        func root(_ r: RawRoot?) -> Image.Root? {
            guard let r else { return nil }
            return Image.Root(fullFact:r.fullFact,digest:r.digest,nodes:r.nodes.map { node in
                Image.Node(path:node.path == r.name ? "" : String(node.path.dropFirst(r.name.count + 1)),
                    fullFact:node.fullFact,contentSHA256:node.sha256,policy:policies[node.path])
            })
        }
        let result = Image(operationsFullFact:Self.full(raw.operationsFact),
            operationsNames:raw.operationsNames,scratch:root(raw.scratch),ingress:root(raw.ingress))
        #if DEBUG
        diagnosticStage = .imageDelta
        #endif
        if let outcome { try requireDelta(outcome,after:result) }
        else if !initialCapture, let current, result != current { throw EraseAllServiceError.invalidAuthority }
        lastRaw = raw; lastPolicyNodes = bindings; lastPairs = pairs
        lastMatchedHeldScope = admission.heldScope
        #if DEBUG
        diagnosticDelta = .none
        diagnosticStage = .observationReturn
        #endif
        try requireHeld(); return result
    }
    private nonisolated static func sameRaw(_ a: RawImage, _ b: RawImage) -> Bool {
        guard full(a.operationsFact) == full(b.operationsFact), a.operationsNames == b.operationsNames,
              a.scratch?.digest == b.scratch?.digest, a.ingress?.digest == b.ingress?.digest,
              Set(a.nodes.keys) == Set(b.nodes.keys) else { return false }
        return a.nodes.allSatisfy { path,node in
            b.nodes[path]?.fullFact == node.fullFact && b.nodes[path]?.sha256 == node.sha256 &&
                b.nodes[path]?.members == node.members
        }
    }
    private func requireSameRaw(_ image: Image, _ raw: RawImage) throws {
        let nodes = Self.nodes(image)
        guard image.operationsFullFact == Self.full(raw.operationsFact),
              image.operationsNames == raw.operationsNames,
              image.scratch?.digest == raw.scratch?.digest, image.ingress?.digest == raw.ingress?.digest,
              Set(nodes.keys) == Set(raw.nodes.keys), nodes.allSatisfy({ path,node in
                  raw.nodes[path]?.fullFact == node.fullFact && raw.nodes[path]?.sha256 == node.contentSHA256
              }) else { throw EraseAllServiceError.invalidAuthority }
    }

    private func validateRequest(_ intent: Intent) throws {
        let nodes = Self.nodes(intent.before)
        func existing(_ path: String, directory: Bool) throws {
            _ = try Self.path(path)
            guard let node = nodes[path], (node.contentSHA256 == nil) == directory else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        switch intent.kind {
        case .createTemporary(let path, let final, let bytes, let sha, let mode, let exclusive):
            guard try Self.path(path).count >= 2, try Self.path(final).count >= 2,
                  !exclusive || final == "ProtectedIngressReceiptsV1/scratch-erase.json",
                  path != final, Self.parent(path) == Self.parent(final),
                  nodes[path] == nil, mode == 0o600, Self.validSHA(sha),
                  StoreMigrationCanonicalJSONV1.sha256(bytes) == sha,
                  !publications.values.contains(where: { $0.temporaryPath == path && nodes[path] != nil }) else {
                throw EraseAllServiceError.invalidAuthority
            }
            try existing(Self.parent(path),directory:true)
        case .writeTemporary(let path, let offset, let requested):
            try existing(path,directory:false)
            guard let recipe = publications.values.first(where: { $0.temporaryPath == path }),
                  recipe.linkID == nil, offset == recipe.written,
                  requested > 0, offset >= 0, offset < (try recipe.bytes.byteCount()),
                  requested <= (try recipe.bytes.byteCount()) - offset,
                  Int64(Self.fields(nodes[path]!.fullFact)[6]) == Int64(offset) else {
                throw EraseAllServiceError.invalidAuthority
            }
        case .requestPolicy(let path, let kind):
            _ = try Self.path(path)
            guard let node = nodes[path], kind == (node.contentSHA256 == nil
                ? OwnedFileKindV1.stagingDirectory : .temporaryFile),
                  Self.fields(node.fullFact)[5] == (node.contentSHA256 == nil
                    ? Self.fields(node.fullFact)[5] : "1") else {
                throw EraseAllServiceError.invalidAuthority
            }
        case .linkPublication(let path, let final):
            try existing(path,directory:false)
            guard let recipe = publications.values.first(where: { $0.temporaryPath == path }),
                  recipe.finalPath == final, recipe.written == (try recipe.bytes.byteCount()),
                  !recipe.exclusiveFinalRename, recipe.replacementID == nil,
                  recipe.acceptedPolicy, recipe.linkID == nil, nodes[final] == nil,
                  nodes[path]?.contentSHA256 == recipe.sha256,
                  Self.fields(nodes[path]!.fullFact)[5] == "1" else {
                throw EraseAllServiceError.invalidAuthority
            }
        case .renamePublication(let source, let final, let exclusive):
            try existing(source,directory:false)
            guard Self.parent(source) == Self.parent(final),
                  Self.fields(nodes[source]!.fullFact)[5] == "1" else {
                throw EraseAllServiceError.invalidAuthority
            }
            if exclusive {
                guard let recipe = publications.values.first(where: { $0.temporaryPath == source }),
                      recipe.exclusiveFinalRename, recipe.finalPath == final,
                      final == "ProtectedIngressReceiptsV1/scratch-erase.json",
                      recipe.written == (try recipe.bytes.byteCount()), recipe.acceptedPolicy,
                      recipe.linkID == nil, recipe.replacementID == nil,
                      nodes[source]?.contentSHA256 == recipe.sha256, nodes[final] == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
            } else {
                // The fixed engine's sole overwrite is the checked finalized H
                // staged final. It is not a second mode for an O_EXCL temporary.
                guard source == final + ".finalizing",
                      final.hasPrefix("ProtectedIngressReceiptsV1/"), final.hasSuffix(".prepare.json"),
                      let old = nodes[final], old.contentSHA256 != nil,
                      Self.fields(old.fullFact)[5] == "1",
                      let original = retainedSources[final], original.fullFact == old.fullFact,
                      original.bytes.sha256() == old.contentSHA256 else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let stagedBytes: EraseScratchCleanupPayloadOriginV1
                if let recipe = publications.values.first(where: { $0.finalPath == source }) {
                    guard !recipe.exclusiveFinalRename, recipe.linkID != nil, recipe.replacementID == nil,
                          recipe.written == (try recipe.bytes.byteCount()), recipe.acceptedPolicy,
                          nodes[recipe.temporaryPath] == nil,
                          nodes[source]?.contentSHA256 == recipe.sha256 else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    stagedBytes = recipe.bytes
                } else {
                    // A lawful first-P one-link staged retry is an immutable
                    // catalog source, not a newly adopted current survivor.
                    guard let sourceP = originalNodes[source], sourceP.kind == "file",
                          let staged = retainedSources[source], let node = nodes[source],
                          staged.fullFact == node.fullFact,
                          Self.nine(node.fullFact) == sourceP.fact,
                          node.contentSHA256 == sourceP.sha256,
                          staged.bytes.sha256() == sourceP.sha256,
                          Int64((try staged.bytes.byteCount())) == Int64(Self.fields(node.fullFact)[6]) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    stagedBytes = staged.bytes
                }
                try withPayloadPairBytes(original.bytes, stagedBytes) { originalBytes, staged in
                    try admission.requireFinalizedIngressReplacement(intent:intent,
                        originalBytes:originalBytes,stagedBytes:staged)
                }
            }
        case .renameLeaseDirectory(let from, let to):
            try existing(from,directory:true); _ = try Self.path(to)
            guard nodes[to] == nil, Self.parent(from) == Self.parent(to),
                  from.split(separator:"/").count == 2,
                  String(to.split(separator:"/").last ?? "") == ".deleting-" + String(from.split(separator:"/").last ?? ""),
                  from.hasPrefix("ScratchDataV1/") else { throw EraseAllServiceError.invalidAuthority }
        case .removeLeaf(let path):
            try existing(path,directory:false)
            guard originalNodes.keys.contains(where: { currentPath($0,outcome:nil) == path && !consumed.contains($0) })
                || publications.values.contains(where: { $0.temporaryPath == path || $0.finalPath == path }) else {
                throw EraseAllServiceError.invalidAuthority
            }
        case .removeDirectory(let path):
            try existing(path,directory:true)
            guard !nodes.keys.contains(where: { $0.hasPrefix(path + "/") }) else {
                throw EraseAllServiceError.invalidAuthority
            }
        case .synchronize(let path):
            if path.isEmpty {
                // The fixed Ledger primitive selected the actual borrowed
                // Operations FD. requireImage proved this named/held anchor;
                // its complete full11/names remain unchanged across fsync.
                guard intent.before == current,
                      Self.fields(intent.before.operationsFullFact).count == 11 else {
                    throw EraseAllServiceError.invalidAuthority
                }
            } else if nodes[path]?.contentSHA256 == nil {
                try existing(path,directory:true)
            } else {
                try existing(path,directory:false)
                guard let recipe = publications.values.first(where: {
                    $0.temporaryPath == path || ($0.exclusiveFinalRename && $0.finalPath == path)
                }), recipe.written == (try recipe.bytes.byteCount()),
                      nodes[path]?.contentSHA256 == recipe.sha256,
                      Int64(Self.fields(nodes[path]!.fullFact)[6]) == Int64((try recipe.bytes.byteCount())),
                      Self.fields(nodes[path]!.fullFact)[5] == "1" else {
                    throw EraseAllServiceError.invalidAuthority
                }
                // Policy may still be unaccepted immediately after the actual
                // completed write. This request only binds the owned fsync;
                // it cannot qualify policy or advance namespace/bytes.
            }
        case .lockOwnedDirectory(let path):
            try existing(path,directory:true)
        case .closeOwnedResource(let path, _):
            _ = try Self.path(path)
            // A removed directory/file can remain held solely for checked
            // close. The genuine Ledger attempt owns the exact resourceID.
        }
    }
    private struct View {
        let fact: String
        let sha: String?
        let policy: TemporalPolicyObservationV1?
    }
    #if DEBUG
    /// Describe only captured parent-guard inputs after the unchanged guard failed.
    private func reportFailedParentDeltaDiagnostic(before: View?, after: View?,
        linkDelta: Int64, checkPolicies: Bool) {
        let saved = errno
        defer { errno = saved }
        let beforeFields = before.map { Self.fields($0.fact) }
        let afterFields = after.map { Self.fields($0.fact) }
        let x = beforeFields.flatMap { $0.count == 11 ? $0 : nil }
        let y = afterFields.flatMap { $0.count == 11 ? $0 : nil }
        func equal(_ index: Int) -> Bool? {
            guard let x, let y else { return nil }
            return x[index] == y[index]
        }
        func boolean(_ value: Bool?) -> String {
            value.map { $0 ? "true" : "false" } ?? "unavailable"
        }
        func number(_ value: Int64?) -> String {
            value.map { String($0) } ?? "unavailable"
        }
        let oldLinks = x.flatMap { Int64($0[5]) }
        let newLinks = y.flatMap { Int64($0[5]) }
        let afterSize = y.flatMap { Int64($0[6]) }
        let sum = oldLinks.map { $0.addingReportingOverflow(linkDelta) }
        let expectedLinks = sum.flatMap { $0.overflow ? nil : $0.partialValue }
        let linksMatch = expectedLinks.flatMap { expected in newLinks.map { $0 == expected } }
        let policyCompatible: Bool? = checkPolicies ? before.flatMap { a in
            after.map { b in Self.samePolicy(a.policy,b.policy,allowLinkChange:linkDelta != 0) }
        } : nil
        let policyClausePassed: Bool? = checkPolicies ? policyCompatible : true
        let parts = [
            "V23_ORIGINAL_SCRATCH_PARENT_DELTA_DIAG_V1", "parent=nonempty",
            "beforePresent=\(before != nil)", "afterPresent=\(after != nil)",
            "beforeFieldCount=" + (beforeFields.map { String($0.count) } ?? "unavailable"),
            "afterFieldCount=" + (afterFields.map { String($0.count) } ?? "unavailable"),
            "beforeShape11=" + boolean(beforeFields.map { $0.count == 11 }),
            "afterShape11=" + boolean(afterFields.map { $0.count == 11 }),
            "devEqual=" + boolean(equal(0)), "inodeEqual=" + boolean(equal(1)),
            "modeEqual=" + boolean(equal(2)), "uidEqual=" + boolean(equal(3)),
            "gidEqual=" + boolean(equal(4)),
            "oldLinksParsed=" + boolean(x.map { _ in oldLinks != nil }),
            "newLinksParsed=" + boolean(y.map { _ in newLinks != nil }),
            "oldLinks=" + number(oldLinks), "newLinks=" + number(newLinks),
            "requestedLinkDelta=\(linkDelta)", "expectedLinks=" + number(expectedLinks),
            "linkAddEvaluated=\(sum != nil)",
            "linkAddNoOverflow=" + boolean(sum.map { !$0.overflow }),
            "linkMatchesExpected=" + boolean(linksMatch),
            "afterSizeParsed=" + boolean(y.map { _ in afterSize != nil }),
            "afterSizeNonnegative=" + boolean(afterSize.map { $0 >= 0 }),
            "shaAbsent=" + boolean(after.map { $0.sha == nil }),
            "policyCheckRequired=\(checkPolicies)",
            "policyCompatible=" + boolean(policyCompatible),
            "policyClausePassed=" + boolean(policyClausePassed)
        ]
        FileHandle.standardError.write(Data((parts.joined(separator: " ") + "\n").utf8))
    }
    #endif
    private func requireRawDelta(_ outcome: Outcome, after: RawImage) throws {
        #if DEBUG
        diagnosticDelta = .raw
        #endif
        try verifyDelta(outcome,operationsFact:Self.full(after.operationsFact),
            operationsNames:after.operationsNames,
            after:after.nodes.mapValues { View(fact:$0.fullFact,sha:$0.sha256,policy:nil) },
            checkPolicies:false)
    }
    private func requireDelta(_ outcome: Outcome, after: Image) throws {
        #if DEBUG
        diagnosticDelta = .image
        #endif
        try verifyDelta(outcome,operationsFact:after.operationsFullFact,
            operationsNames:after.operationsNames,
            after:Self.nodes(after).mapValues { View(fact:$0.fullFact,sha:$0.contentSHA256,policy:$0.policy) },
            checkPolicies:true)
    }
    private nonisolated static func samePolicy(_ a: TemporalPolicyObservationV1?,
        _ b: TemporalPolicyObservationV1?, allowLinkChange: Bool = false) -> Bool {
        guard let a, let b else { return a == b }
        return a.device == b.device && a.inode == b.inode && a.mode == b.mode &&
            (allowLinkChange || a.linkCount == b.linkCount) && a.state == b.state &&
            a.urlProtection == b.urlProtection && a.fileManagerProtection == b.fileManagerProtection &&
            a.backupExcluded == b.backupExcluded && a.isDirectory == b.isDirectory &&
            a.volumeSupportsProtection == b.volumeSupportsProtection
    }
    private func verifyDelta(_ outcome: Outcome, operationsFact: String,
        operationsNames: [String], after: [String: View], checkPolicies: Bool) throws {
        #if DEBUG
        diagnosticStage = .deltaPrimitive
        #endif
        let intent = outcome.intent
        let before = Self.nodes(intent.before).mapValues {
            View(fact:$0.fullFact,sha:$0.contentSHA256,policy:$0.policy)
        }
        let beforeKeys = Set(before.keys)
        var expectedKeys = beforeKeys
        var changed = Set<String>()
        var mapped = [String:String]()
        var parentPath: String?
        var expectedRootNames = intent.before.operationsNames
        func node(_ path: String) throws -> View {
            guard let value = after[path] else { throw EraseAllServiceError.invalidAuthority }; return value
        }
        func parentChanged(_ path: String) {
            parentPath = Self.parent(path)
            if let parentPath, !parentPath.isEmpty { changed.insert(parentPath) }
        }
        func ctime(_ path: String, old: View, links: Int64 = 0) throws {
            let value = try node(path)
            guard Self.ctimeOnly(old.fact,value.fact,linkDelta:links), value.sha == old.sha,
                  !checkPolicies || Self.samePolicy(old.policy,value.policy,allowLinkChange:links != 0) else {
                throw EraseAllServiceError.invalidAuthority
            }
            changed.insert(path)
        }
        switch intent.kind {
        case .createTemporary(let path, _, _, _, let mode, _):
            expectedKeys.insert(path); changed.insert(path); parentChanged(path)
            #if DEBUG
            diagnosticStage = .deltaCreatedNode
            #endif
            let value = try node(path), f = Self.fields(value.fact)
            #if DEBUG
            diagnosticStage = .deltaCreatedFile
            #endif
            guard let createdFD = Int32(exactly:outcome.result),
                  Self.full(try held(createdFD)) == value.fact,
                  f.count == 11, f[5] == "1", f[6] == "0",
                  UInt32(f[2]).map({ $0 & 0o7777 }) == UInt32(mode),
                  value.sha == StoreMigrationCanonicalJSONV1.sha256(Data()),
                  !checkPolicies || value.policy == nil else { throw EraseAllServiceError.invalidAuthority }
        case .writeTemporary(let path, let offset, let requested):
            guard let recipe = publications.values.first(where: { $0.temporaryPath == path }),
                  let count = Int(exactly:outcome.result), count >= 0, count <= requested,
                  offset == recipe.written, count <= (try recipe.bytes.byteCount()) - offset,
                  let old = before[path] else { throw EraseAllServiceError.invalidAuthority }
            let value = try node(path), f = Self.fields(value.fact), oldF = Self.fields(old.fact)
            guard Self.stable(old.fact,value.fact), f[5] == oldF[5],
                  Int64(f[6]) == Int64(offset + count),
                  value.sha == (try recipe.bytes.prefixSHA256(byteCount: offset + count,
                    admission: admission, attempt: coldAttempt)),
                  !checkPolicies || value.policy == old.policy else { throw EraseAllServiceError.invalidAuthority }
            changed.insert(path)
        case .requestPolicy(let path, _):
            guard outcome.result == 0, let old = before[path] else { throw EraseAllServiceError.invalidAuthority }
            let value = try node(path)
            guard let scope = retainedEffectScopes.last, scope.intent === intent,
                  scope.finalFullFact == value.fact,
                  Self.ctimeOnly(old.fact,value.fact), value.sha == old.sha,
                  !checkPolicies || value.policy != nil else { throw EraseAllServiceError.invalidAuthority }
            changed.insert(path)
        case .linkPublication(let temporary, let final):
            guard outcome.result == 0, let old = before[temporary] else { throw EraseAllServiceError.invalidAuthority }
            expectedKeys.insert(final); changed.insert(final); parentChanged(final)
            try ctime(temporary,old:old,links:1)
            let a = try node(temporary), b = try node(final)
            guard a.fact == b.fact, a.sha == b.sha,
                  !checkPolicies || a.policy == b.policy else { throw EraseAllServiceError.invalidAuthority }
        case .renamePublication(let source, let final, _):
            guard outcome.result == 0, let old = before[source] else { throw EraseAllServiceError.invalidAuthority }
            expectedKeys.remove(source); expectedKeys.insert(final)
            changed.insert(final); parentChanged(final)
            let value = try node(final)
            guard Self.ctimeOnly(old.fact,value.fact), old.sha == value.sha,
                  !checkPolicies || old.policy == value.policy else { throw EraseAllServiceError.invalidAuthority }
        case .renameLeaseDirectory(let from, let to):
            guard outcome.result == 0, let oldRoot = before[from] else { throw EraseAllServiceError.invalidAuthority }
            for path in before.keys where path == from || path.hasPrefix(from + "/") {
                let target = to + String(path.dropFirst(from.count))
                expectedKeys.remove(path); expectedKeys.insert(target); mapped[path] = target
            }
            changed.insert(to); parentChanged(to)
            let newRoot = try node(to)
            guard Self.ctimeOnly(oldRoot.fact,newRoot.fact), oldRoot.sha == newRoot.sha,
                  !checkPolicies || oldRoot.policy == newRoot.policy else { throw EraseAllServiceError.invalidAuthority }
        case .removeLeaf(let path):
            guard outcome.result == 0, let old = before[path] else { throw EraseAllServiceError.invalidAuthority }
            expectedKeys.remove(path); parentChanged(path)
            let identity = Array(Self.fields(old.fact)[0...1])
            let aliases = before.filter { $0.key != path && Array(Self.fields($0.value.fact)[0...1]) == identity }
            let links = Self.fields(old.fact)[5]
            guard (links == "1" && aliases.isEmpty) || (links == "2" && aliases.count == 1) else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (other,value) in aliases { try ctime(other,old:value,links:-1) }
        case .removeDirectory(let path):
            guard outcome.result == 0 else { throw EraseAllServiceError.invalidAuthority }
            expectedKeys.remove(path); parentChanged(path)
            if Self.parent(path).isEmpty { expectedRootNames.removeAll { $0 == path } }
        case .synchronize, .lockOwnedDirectory, .closeOwnedResource:
            guard outcome.result == 0 else { throw EraseAllServiceError.invalidAuthority }
        }
        #if DEBUG
        diagnosticStage = .deltaNamespace
        #endif
        guard Set(after.keys) == expectedKeys, operationsNames == expectedRootNames else {
            throw EraseAllServiceError.invalidAuthority
        }
        #if DEBUG
        diagnosticStage = .deltaParent
        #endif
        if let parentPath {
            let beforeDirectEntryCount = parentPath.isEmpty
                ? intent.before.operationsNames.count
                : EraseDirectoryEntryLinkModelV1.directEntryCount(paths:beforeKeys,parentPath:parentPath)
            let afterDirectEntryCount = parentPath.isEmpty
                ? expectedRootNames.count
                : EraseDirectoryEntryLinkModelV1.directEntryCount(paths:expectedKeys,parentPath:parentPath)
            guard let parentLinks = EraseDirectoryEntryLinkModelV1.linkDelta(
                beforeDirectEntryCount:beforeDirectEntryCount,
                afterDirectEntryCount:afterDirectEntryCount) else {
                throw EraseAllServiceError.invalidAuthority
            }
            if parentPath.isEmpty {
                guard Self.directoryMutation(intent.before.operationsFullFact,operationsFact,linkDelta:parentLinks,
                    beforeDirectEntryCount:beforeDirectEntryCount,afterDirectEntryCount:afterDirectEntryCount) else {
                    throw EraseAllServiceError.invalidAuthority
                }
            } else {
                guard let a = before[parentPath], let b = after[parentPath],
                      Self.directoryMutation(a.fact,b.fact,linkDelta:parentLinks,
                        beforeDirectEntryCount:beforeDirectEntryCount,afterDirectEntryCount:afterDirectEntryCount), b.sha == nil,
                      !checkPolicies || Self.samePolicy(a.policy,b.policy,allowLinkChange:parentLinks != 0) else {
                    #if DEBUG
                    reportFailedParentDeltaDiagnostic(before:before[parentPath],after:after[parentPath],
                        linkDelta:parentLinks,checkPolicies:checkPolicies)
                    #endif
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        #if DEBUG
        diagnosticStage = .deltaOperations
        #endif
        if parentPath?.isEmpty != true {
            guard operationsFact == intent.before.operationsFullFact else { throw EraseAllServiceError.invalidAuthority }
        }
        #if DEBUG
        diagnosticStage = .deltaUntouched
        #endif
        for (path,value) in before {
            let target = mapped[path] ?? path
            if !expectedKeys.contains(target) || changed.contains(target) { continue }
            guard let actual = after[target], actual.fact == value.fact, actual.sha == value.sha,
                  !checkPolicies || actual.policy == value.policy else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
    }
    private func commit(_ outcome: Outcome) throws {
        publications = try candidatePublications(outcome)
        switch outcome.intent.kind {
        case .renamePublication(let source,let final,let exclusive):
            if !exclusive {
                let bytes: EraseScratchCleanupPayloadOriginV1
                if let recipe = publications.values.first(where: {
                    $0.finalPath == final && $0.replacementID == outcome.intent.requestID
                }) { bytes = recipe.bytes }
                else {
                    guard let staged = retainedSources[source] else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    bytes = staged.bytes
                }
                guard let target = lastRaw?.nodes[final],
                      target.sha256 == bytes.sha256(),
                      Int64(try bytes.byteCount()) == Int64(target.fact.st_size) else {
                    throw EraseAllServiceError.invalidAuthority
                }
                finalizedReplacements[final] = FinalizedReplacement(
                    requestID:outcome.intent.requestID,sourcePath:source,bytes:bytes,
                    sha256:target.sha256!,fullFact:target.fullFact)
                if originalNodes[source] != nil { consumed.insert(source) }
            }
        case .renameLeaseDirectory(let from,let to):
            var nextDirectories = directorySourcePaths
            for (path,source) in directorySourcePaths where path == from || path.hasPrefix(from + "/") {
                nextDirectories.removeValue(forKey:path)
                nextDirectories[to + String(path.dropFirst(from.count))] = source
            }
            directorySourcePaths = nextDirectories
            for original in originalNodes.keys {
                let path = pathMapping[original] ?? original
                if path == from || path.hasPrefix(from + "/") {
                    pathMapping[original] = to + String(path.dropFirst(from.count))
                }
            }
            for id in Array(publications.keys) {
                if publications[id]!.temporaryPath.hasPrefix(from + "/") {
                    publications[id]!.temporaryPath = to + String(publications[id]!.temporaryPath.dropFirst(from.count))
                }
                if publications[id]!.finalPath.hasPrefix(from + "/") {
                    publications[id]!.finalPath = to + String(publications[id]!.finalPath.dropFirst(from.count))
                }
            }
        case .removeLeaf(let path), .removeDirectory(let path):
            for original in originalNodes.keys where (pathMapping[original] ?? original) == path {
                consumed.insert(original)
            }
        default: break
        }
    }
}

/// A distinct effect scope, privately issued for the current retained policy
/// request. Accepted postfacts require real PFP-owned substep outcome objects;
/// a read scope and a caller's result0 cannot supply this authority.
@MainActor
final class OriginalEraseScratchCleanupPolicyEffectScopeV1 {
    let operationID: UUID
    let requestID: UUID
    fileprivate let heldScope: EraseScratchCleanupScopeOriginV1
    let sourceSHA256: String?
    let byteCount: Int64?
    private weak var owner: OriginalEraseScratchCleanupImageOwnerV1?
    fileprivate let intent: OriginalEraseScratchCleanupPrimitiveIntentV1
    private let target: OriginalEraseScratchTemporalPolicyNodeV1
    private var postFact: String
    fileprivate var finalFullFact: String { postFact }
    private var outcomes: [OriginalEraseScratchPublicationPolicyOutcomeV1] = []
    private var attempts: [OriginalEraseScratchPublicationPolicyAttemptV1] = []
    private var revoked = false
    private var coldPositiveOutcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1?
    private var coldConsumedOutcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1?
    fileprivate var coldProofConsumed: Bool {
        revoked && coldPositiveOutcome != nil && coldConsumedOutcome === coldPositiveOutcome
    }
    fileprivate init(owner:OriginalEraseScratchCleanupImageOwnerV1,
        intent:OriginalEraseScratchCleanupPrimitiveIntentV1,
        target:OriginalEraseScratchTemporalPolicyNodeV1,sha:String?,count:Int64?) {
        self.owner = owner; self.intent = intent; self.target = target
        operationID = intent.operationID; requestID = intent.requestID; heldScope = owner.currentHeldScope
        sourceSHA256 = sha; byteCount = count; postFact = target.fullFact
    }
    func requireCurrentBinding() throws {
        guard !revoked, let owner else { throw EraseAllServiceError.invalidAuthority }
        try owner.requireActivePolicyScope(self)
    }
    func requireTarget(_ kind:OwnedFileKindV1, at url:URL,
        initialFullFact:String) throws -> OriginalEraseScratchTemporalPolicyNodeV1 {
        try requireCurrentBinding()
        guard target.kind == kind, target.url == url, target.fullFact == initialFullFact else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireCurrentBinding(); return target
    }
    func retainPolicyAttempt(_ attempt:OriginalEraseScratchPublicationPolicyAttemptV1) {
        attempts.append(attempt)
    }
    func requireOwnedPolicyPostFact(fullFact:String,
        outcome:OriginalEraseScratchPublicationPolicyOutcomeV1) throws {
        try requireCurrentBinding()
        guard !outcomes.contains(where: { $0 === outcome }), outcomes.count < 2,
              outcome.step == (outcomes.isEmpty ? .completeProtection : .backupExclusion),
              OriginalEraseScratchCleanupImageOwnerV1.ctimeOnly(postFact,fullFact) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try outcome.requireBound(scope:self,kind:target.kind,at:target.url,fullFact:fullFact)
        outcomes.append(outcome); postFact = fullFact
        try requireCurrentBinding()
    }
    func poisonOnUncertainPolicy() { revoked = true; owner?.poison() }
    fileprivate func revoke() { revoked = true }
    fileprivate func retainColdPositiveOutcome(_ outcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1) throws {
        guard case .cold = heldScope, !revoked, coldPositiveOutcome == nil,
              outcome.intent === intent, outcome.result == 0 else { throw EraseAllServiceError.invalidAuthority }
        try requireCheckedSettlement() // Actual proof while the scope is live.
        coldPositiveOutcome = outcome
    }
    fileprivate func consumeColdPositiveOutcome(_ outcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1) throws {
        guard case .cold = heldScope, revoked, coldPositiveOutcome === outcome,
              coldConsumedOutcome == nil, outcome.intent === intent else {
            throw EraseAllServiceError.invalidAuthority
        }
        // The owner calls this only after complete raw/image/delta/commit and
        // the genuine bound Ledger readback, after all active aliases retire.
        coldConsumedOutcome = outcome
    }
    fileprivate func requireCheckedSettlement() throws {
        guard !revoked, outcomes.count == 2, attempts.count == 1 else {
            throw EraseAllServiceError.invalidAuthority
        }
        // Pure private closed-resource state. No callback can inspect a closed
        // numeric FD or demand the obsolete pre-outcome active frame.
        try attempts[0].requireCheckedSettlement(scope:self,kind:target.kind,at:target.url)
    }
}

extension OriginalEraseScratchCleanupImageOwnerV1 {
    private func settleObservationScopes() throws {
        while settledPolicyAttemptCount < policyAttempts.count {
            try policyAttempts[settledPolicyAttemptCount].requireCheckedSettlement()
            settledPolicyAttemptCount += 1
        }
        activeScope?.revoke(); activeScope = nil
    }
    func currentTemporalObservationScope() throws -> OriginalEraseScratchTemporalObservationScopeV1 {
        try checked {
            guard current != nil, lastRaw != nil, activeEffectScope == nil,
                  lastMatchedHeldScope?.isSame(as: admission.heldScope) == true else {
                throw EraseAllServiceError.invalidAuthority
            }
            try settleObservationScopes()
            let scope = OriginalEraseScratchTemporalObservationScopeV1(owner:self,
                nodes:lastPolicyNodes,pairs:lastPairs)
            activeScope = scope; return scope
        }
    }
    func policyEffectScope(intent:Intent) throws -> OriginalEraseScratchCleanupPolicyEffectScopeV1 {
        try checked {
            guard pending === intent, observationOutcome == nil, activeEffectScope == nil,
                  let raw = lastRaw, case .requestPolicy(let path,let kind) = intent.kind,
                  let node = raw.nodes[path], let currentNode = Self.nodes(intent.before)[path],
                  node.fullFact == currentNode.fullFact,
                  node.sha256 == currentNode.contentSHA256 else {
                throw EraseAllServiceError.invalidAuthority
            }
            let binding = try policyNode(node,raw:raw)
            guard binding.kind == kind else { throw EraseAllServiceError.invalidAuthority }
            let scope = OriginalEraseScratchCleanupPolicyEffectScopeV1(owner:self,intent:intent,
                target:binding,sha:node.sha256,count:node.sha256 == nil ? nil : Int64(node.fact.st_size))
            retainedEffectScopes.append(scope); activeEffectScope = scope; return scope
        }
    }
    fileprivate func requireActivePolicyScope(_ scope:OriginalEraseScratchCleanupPolicyEffectScopeV1) throws {
        guard activeEffectScope === scope, pending === scope.intent, observationOutcome == nil,
              scope.heldScope.isSame(as: admission.heldScope) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireHeld()
    }
}

/// One read-only catalog window. Each private close records its actual outcome
/// and exact owned resource, without issuing a pretend whole-image readback.
/// Source output is withheld until the independent complete final image proof.
@MainActor
final class OriginalEraseScratchCanonicalSourceCatalogSessionV1 {
    private enum State:Equatable { case active, completed, poisoned }
    private var state = State.active
    private weak var owner: OriginalEraseScratchCleanupImageOwnerV1?
    private weak var attempt: OriginalEraseScratchCleanupAttemptV1?
    fileprivate let heldScope: EraseScratchCleanupScopeOriginV1
    fileprivate let image: OriginalEraseScratchCleanupImageV1
    private var pending: OriginalEraseScratchCleanupPrimitiveIntentV1?
    private var outcomes: [OriginalEraseScratchCleanupPrimitiveOutcomeV1] = []
    private var closedResources = Set<UUID>()
    fileprivate init(owner:OriginalEraseScratchCleanupImageOwnerV1,
        attempt:OriginalEraseScratchCleanupAttemptV1,image:OriginalEraseScratchCleanupImageV1) {
        self.owner = owner; self.attempt = attempt; self.image = image
        heldScope = owner.currentHeldScope
    }
    func requireHeld(attempt:OriginalEraseScratchCleanupAttemptV1) throws {
        guard state == .active, self.attempt === attempt, let owner else {
            throw EraseAllServiceError.invalidAuthority
        }
        try owner.requireCatalog(self,attempt:attempt)
    }
    func retainCloseIntent(_ intent:OriginalEraseScratchCleanupPrimitiveIntentV1,
        attempt:OriginalEraseScratchCleanupAttemptV1) throws {
        do {
            try requireHeld(attempt:attempt)
            guard pending == nil, intent.attemptID == attempt.attemptID,
                  intent.operationID == attempt.operationID, intent.before == image,
                  case .closeOwnedResource(let path,let resourceID) = intent.kind,
                  !closedResources.contains(resourceID) else { throw EraseAllServiceError.invalidAuthority }
            try owner!.requireCatalogCloseSequence(intent,session:self)
            try attempt.requireOwnedCloseRequest(intent:intent,outcome:nil)
            _ = path // actual immutable resource role/path belongs private Ledger producer
            pending = intent; try requireHeld(attempt:attempt)
        } catch { poison(); throw error }
    }
    func recordCloseOutcome(_ outcome:OriginalEraseScratchCleanupPrimitiveOutcomeV1,
        attempt:OriginalEraseScratchCleanupAttemptV1) throws {
        do {
            try requireHeld(attempt:attempt)
            guard pending === outcome.intent, outcome.result == 0,
                  case .closeOwnedResource(_,let resourceID) = outcome.intent.kind else {
                throw EraseAllServiceError.invalidAuthority
            }
            try attempt.requireOwnedCloseRequest(intent:outcome.intent,outcome:outcome)
            guard closedResources.insert(resourceID).inserted else { throw EraseAllServiceError.invalidAuthority }
            outcomes.append(outcome); try owner!.completeCatalogCloseSequence(outcome,session:self)
            pending = nil; try requireHeld(attempt:attempt)
        } catch { poison(); throw error }
    }
    func requireCompleted(attempt:OriginalEraseScratchCleanupAttemptV1) throws {
        guard state == .completed, self.attempt === attempt, pending == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        // Ledger's complete private catalog resource census is memory-only.
        try attempt.requireCatalogResourcesCheckedClosed(session:self)
    }
    fileprivate func finish(attempt:OriginalEraseScratchCleanupAttemptV1) throws {
        try requireHeld(attempt:attempt)
        guard pending == nil else { throw EraseAllServiceError.invalidAuthority }
        try attempt.requireCatalogResourcesCheckedClosed(session:self)
        state = .completed
    }
    fileprivate func poison() { state = .poisoned; owner?.poison() }
}

extension OriginalEraseScratchCleanupImageOwnerV1 {
    /// Current ownership evidence is produced by the complete raw scanner and
    /// actual selected PFP policy. Source9 has no historical uid/gid; no such
    /// fields are invented and no canonical-bytes callback recurses here.
    func requireCanonicalSourceOwnership(path:String,fullFact:String) throws {
        do {
            try requireHeld()
            guard lastMatchedHeldScope?.isSame(as: admission.heldScope) == true,
                  let raw = lastRaw, let node = raw.nodes[path],
                  let current, let selected = Self.nodes(current)[path],
                  node.fullFact == fullFact, selected.fullFact == fullFact,
                  let policy = selected.policy, policy.device == UInt64(node.fact.st_dev),
                  policy.inode == UInt64(node.fact.st_ino), policy.backupExcluded == true,
                  node.fact.st_uid == geteuid() else { throw EraseAllServiceError.invalidAuthority }
            let parentPath = Self.parent(path)
            let parentFact = parentPath.isEmpty ? raw.operationsFact : raw.nodes[parentPath]?.fact
            guard let parentFact,
                  node.fact.st_gid == ((parentFact.st_mode & S_ISGID) != 0 ? parentFact.st_gid : getegid()),
                  node.fact.st_dev == parentFact.st_dev else { throw EraseAllServiceError.invalidAuthority }
            try requireHeld()
        } catch { poison(); throw error }
    }
    func beginCanonicalSourceCatalog(attempt:OriginalEraseScratchCleanupAttemptV1,
        support:Int32,caches:Int32,temporary:Int32,operations:Int32
    ) throws -> OriginalEraseScratchCanonicalSourceCatalogSessionV1 {
        try checked {
            guard activeCatalog == nil, pending == nil, activeEffectScope == nil,
                  attempt.operationID == operationID, let current else {
                throw EraseAllServiceError.invalidAuthority
            }
            try settleObservationScopes()
            try requireImage(current,support:support,caches:caches,temporary:temporary,operations:operations)
            let session = OriginalEraseScratchCanonicalSourceCatalogSessionV1(owner:self,
                attempt:attempt,image:current)
            retainedCatalogs.append(session); activeCatalog = session; return session
        }
    }
    fileprivate func requireCatalog(_ session:OriginalEraseScratchCanonicalSourceCatalogSessionV1,
        attempt:OriginalEraseScratchCleanupAttemptV1) throws {
        guard activeCatalog === session, session.heldScope.isSame(as: admission.heldScope),
              session.image == current, pending == nil, activeEffectScope == nil else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireHeld()
        try admission.requireCatalogFrame(attempt:attempt,session:session)
        try attempt.requireCanonicalCatalogFrame(session:session)
        try requireHeld()
    }
    fileprivate func requireCatalogCloseSequence(_ intent:Intent,
        session:OriginalEraseScratchCanonicalSourceCatalogSessionV1) throws {
        guard activeCatalog === session, intent.operationID == operationID,
              attemptID == nil || attemptID == intent.attemptID,
              nextSequence == nil || nextSequence == intent.sequence else {
            throw EraseAllServiceError.invalidAuthority
        }
        attemptID = intent.attemptID
    }
    fileprivate func completeCatalogCloseSequence(_ outcome:Outcome,
        session:OriginalEraseScratchCanonicalSourceCatalogSessionV1) throws {
        try requireCatalogCloseSequence(outcome.intent,session:session)
        let next = outcome.intent.sequence.addingReportingOverflow(1)
        guard !next.overflow else { throw EraseAllServiceError.invalidAuthority }
        nextSequence = next.partialValue
    }
    func finishCanonicalSourceCatalog(_ session:OriginalEraseScratchCanonicalSourceCatalogSessionV1,
        attempt:OriginalEraseScratchCleanupAttemptV1,support:Int32,caches:Int32,
        temporary:Int32,operations:Int32) throws {
        try checked {
            try requireCatalog(session,attempt:attempt)
            try settleObservationScopes()
            try attempt.requireCatalogResourcesCheckedClosed(session:session)
            try requireImage(session.image,support:support,caches:caches,temporary:temporary,operations:operations)
            try session.finish(attempt:attempt); activeCatalog = nil
        }
    }
}

#if DEBUG
// Fixed genuine-issuer DATA probes. This is test configuration and immutable
// observation DATA, never a scope factory, permission or policy settlement.
enum OriginalEraseScratchIssuerDataProfileV1: String, Equatable {
    case node, declaredPair, earlierPairProjectionMembership
}

enum OriginalEraseScratchIssuerDataProbeV1: String, CaseIterable, Hashable {
    case nodeExact, nodeMissingURL, nodeWrongKind, nodeWrongFact
    case nodeAfterRevoke, nodeCurrentBindingRevoked, nodeAuthorizedRevoked, nodePairProjectionAfterRevoke
    case pairNodeExact, pairExact, pairZeroCount, pairOneCount, pairThreeCount
    case pairReordered, pairDuplicateMember, pairMissingMember, earlierPairProjectionMissing
    case pairNodeAfterRevoke, pairAfterRevoke, pairCurrentBindingRevoked, pairProjectionAfterRevoke
    case pairNodeAuthorizedRevoked, pairAuthorizedRevoked
}

enum OriginalEraseScratchIssuerDataOutcomeV1: Equatable {
    case equalData, invalidAuthority, differentData, unexpectedSuccess
    case unexpectedError(String)
}

enum OriginalEraseScratchIssuerDataTestErrorV1: Error, Equatable {
    case occupied, invalidConfiguration, wrongSlot, unqualifiedRelease
}

struct OriginalEraseScratchIssuerDataReportV1 {
    let profile: OriginalEraseScratchIssuerDataProfileV1
    let operationID: UUID?
    let supportDevice: Int64?
    let supportInode: UInt64?
    let selectedIssuances: UInt64
    let selectedRevokes: UInt64
    let ordinaryIssuances: UInt64
    let ordinaryRevokes: UInt64
    let selectedObservationIDs: [UUID]
    let revokedObservationIDs: [UUID]
    let issuedPairProjections: [[OriginalEraseScratchTemporalPairV1]]
    let revokedPairProjections: [[OriginalEraseScratchTemporalPairV1]]
    let revokedDriverScopeHolderCounts: [Int]
    let completedSelectedProfile: Bool
    let driverScopeHolderCount: Int
    let firstFailure: String?
    let probes: [OriginalEraseScratchIssuerDataProbeV1: OriginalEraseScratchIssuerDataOutcomeV1]
    let expectedNode: OriginalEraseScratchTemporalPolicyNodeV1?
    let observedNode: OriginalEraseScratchTemporalPolicyNodeV1?
    let expectedPairNode: OriginalEraseScratchTemporalPolicyNodeV1?
    let observedPairNode: OriginalEraseScratchTemporalPolicyNodeV1?
    let expectedPair: OriginalEraseScratchTemporalPairV1?
    let observedPair: OriginalEraseScratchTemporalPairV1?
}

@MainActor
fileprivate enum OriginalEraseScratchIssuerPairDataSelectionV1 {
    // The DEBUG Scope API and projection probes share this exact selector.
    // No live scope/owner is accepted, created or consulted here.
    static func select(_ pairs: [OriginalEraseScratchTemporalPairV1],
        aliasURLs: [URL]) throws -> OriginalEraseScratchTemporalPairV1 {
        guard aliasURLs.count == 2,
              let pair = pairs.first(where: { $0.members.map(\.url) == aliasURLs }) else {
            throw EraseAllServiceError.invalidAuthority
        }
        return pair
    }
}

@MainActor
enum OriginalEraseScratchIssuerDataTestsV1 {
    // Occupancy has no implicit/deinit/defer reset. Failed original owners and
    // incomplete profiles cannot grant another test configuration authority.
    fileprivate static var occupied: OriginalEraseScratchIssuerDataDriverV1?

    static func arm(_ profile: OriginalEraseScratchIssuerDataProfileV1,
        support: URL, operation: EraseRouterOperationV1) throws -> UUID {
        guard occupied == nil else { throw OriginalEraseScratchIssuerDataTestErrorV1.occupied }
        guard support.isFileURL, support == support.standardizedFileURL else {
            throw OriginalEraseScratchIssuerDataTestErrorV1.invalidConfiguration
        }
        let driver = OriginalEraseScratchIssuerDataDriverV1(profile: profile,
            support: support, operationID: operation.operationID,
            operationIdentity: ObjectIdentifier(operation))
        occupied = driver
        return driver.slot
    }

    static func report(slot: UUID) throws -> OriginalEraseScratchIssuerDataReportV1 {
        guard let driver = occupied, driver.slot == slot else {
            throw OriginalEraseScratchIssuerDataTestErrorV1.wrongSlot
        }
        return driver.report
    }

    /// DEBUG slot bookkeeping only, in the genuine post-cleanup/pre-activation
    /// window. completedRetirement rechecks actual Router association and a
    /// monotonic released receipt; it is NOT a fresh physical/policy rescan.
    static func restoreAfterCompletedRetirement(slot: UUID, support: URL,
        router: StartupRouter, ticket: StartupRouter.OriginalOperationTicket,
        operation: EraseRouterOperationV1,
        reservation: AppAccessGateV1.EraseAdoptionToken) throws {
        guard let driver = occupied, driver.slot == slot,
              driver.support == support, support == support.standardizedFileURL,
              driver.operationIdentity == ObjectIdentifier(operation),
              driver.expectedOperationID == operation.operationID,
              driver.report.operationID == operation.operationID,
              let supportDevice = driver.report.supportDevice, let supportInode = driver.report.supportInode,
              driver.holderCount == 0, driver.canRestoreBookkeeping else {
            throw OriginalEraseScratchIssuerDataTestErrorV1.unqualifiedRelease
        }
        guard try router.eraseRetirementOperation(for: ticket) === operation else {
            throw OriginalEraseScratchIssuerDataTestErrorV1.unqualifiedRelease
        }
        // Obtain these actual owners internally now; never accept a caller's
        // cached receipt/proof tuple or read/close/unlock a retained descriptor.
        let (retirement, proof, possibleReceipt) = try operation.completedRetirement()
        guard let receipt = possibleReceipt, let actualReservation = receipt.reservation,
              actualReservation == reservation, receipt.subject == reservation.subject,
              retirement.ownsProof(proof), retirement.binding == proof.binding,
              proof.binding.operationID == driver.expectedOperationID,
              proof.binding.subject == receipt.subject,
              receipt.subject.applicationSupportURL == support,
              receipt.subject.applicationSupportDevice == supportDevice,
              receipt.subject.applicationSupportInode == supportInode else {
            throw OriginalEraseScratchIssuerDataTestErrorV1.unqualifiedRelease
        }
        occupied = nil
    }

    fileprivate static func issued(_ scope: OriginalEraseScratchTemporalObservationScopeV1,
        nodes: [URL: OriginalEraseScratchTemporalPolicyNodeV1],
        pairs: [OriginalEraseScratchTemporalPairV1], support: URL,
        supportIdentity: EraseSchema2ColdAuxiliaryFirstObserverV1.ParentIdentity) {
        occupied?.issued(scope, nodes: nodes, pairs: pairs, support: support, supportIdentity: supportIdentity)
    }

    fileprivate static func naturallyRevoked(_ scope: OriginalEraseScratchTemporalObservationScopeV1,
        support: URL) {
        occupied?.naturallyRevoked(scope, support: support)
    }
}

@MainActor
fileprivate final class OriginalEraseScratchIssuerDataDriverV1 {
    private enum Phase: Equatable { case waitingEarliest, waitingPair, earliestActive, pairActive, complete, failed }
    private enum Entry { case ordinary, earliest, pair }
    let slot = UUID()
    let profile: OriginalEraseScratchIssuerDataProfileV1
    let support: URL
    let expectedOperationID: UUID
    let operationIdentity: ObjectIdentifier
    private var actualOperationID: UUID?
    private var supportDevice: Int64?
    private var supportInode: UInt64?
    private var phase: Phase
    private var activeID: UUID?
    private var entry: Entry?
    private var earliestScope: OriginalEraseScratchTemporalObservationScopeV1?
    private var pairScope: OriginalEraseScratchTemporalObservationScopeV1?
    private var node: OriginalEraseScratchTemporalPolicyNodeV1?
    private var observedNode: OriginalEraseScratchTemporalPolicyNodeV1?
    private var pairNode: OriginalEraseScratchTemporalPolicyNodeV1?
    private var observedPairNode: OriginalEraseScratchTemporalPolicyNodeV1?
    private var pair: OriginalEraseScratchTemporalPairV1?
    private var observedPair: OriginalEraseScratchTemporalPairV1?
    private var selectedIDs: [UUID] = []
    private var revokedIDs: [UUID] = []
    private var issuedPairProjections: [[OriginalEraseScratchTemporalPairV1]] = []
    private var revokedPairProjections: [[OriginalEraseScratchTemporalPairV1]] = []
    private var revokedHolderCounts: [Int] = []
    private var selectedIssuances: UInt64 = 0
    private var selectedRevokes: UInt64 = 0
    private var ordinaryIssuances: UInt64 = 0
    private var ordinaryRevokes: UInt64 = 0
    private var firstFailure: String?
    private var probes: [OriginalEraseScratchIssuerDataProbeV1: OriginalEraseScratchIssuerDataOutcomeV1] = [:]

    init(profile: OriginalEraseScratchIssuerDataProfileV1, support: URL,
        operationID: UUID, operationIdentity: ObjectIdentifier) {
        self.profile = profile; self.support = support
        expectedOperationID = operationID; self.operationIdentity = operationIdentity
        phase = profile == .declaredPair ? .waitingPair : .waitingEarliest
    }

    var holderCount: Int { (earliestScope == nil ? 0 : 1) + (pairScope == nil ? 0 : 1) }
    var canRestoreBookkeeping: Bool {
        phase == .complete && firstFailure == nil && activeID == nil && entry == nil &&
        ordinaryIssuances == ordinaryRevokes
    }
    var report: OriginalEraseScratchIssuerDataReportV1 {
        .init(profile: profile, operationID: actualOperationID,
            supportDevice: supportDevice, supportInode: supportInode,
            selectedIssuances: selectedIssuances, selectedRevokes: selectedRevokes,
            ordinaryIssuances: ordinaryIssuances, ordinaryRevokes: ordinaryRevokes,
            selectedObservationIDs: selectedIDs, revokedObservationIDs: revokedIDs,
            issuedPairProjections: issuedPairProjections, revokedPairProjections: revokedPairProjections,
            revokedDriverScopeHolderCounts: revokedHolderCounts,
            completedSelectedProfile: phase == .complete, driverScopeHolderCount: holderCount,
            firstFailure: firstFailure, probes: probes, expectedNode: node,
            observedNode: observedNode, expectedPairNode: pairNode,
            observedPairNode: observedPairNode, expectedPair: pair, observedPair: observedPair)
    }

    private func clearExtraHolders() { earliestScope = nil; pairScope = nil }
    private func fail(_ name: String) {
        if firstFailure == nil { firstFailure = name }
        phase = .failed; clearExtraHolders(); activeID = nil; entry = nil
    }
    private func increment(_ value: UInt64) -> UInt64? {
        let next = value.addingReportingOverflow(1)
        guard !next.overflow else { fail("counter-overflow"); return nil }
        return next.partialValue
    }
    private func record(_ id: OriginalEraseScratchIssuerDataProbeV1,
        _ outcome: OriginalEraseScratchIssuerDataOutcomeV1,
        expecting expected: OriginalEraseScratchIssuerDataOutcomeV1) {
        guard firstFailure == nil else { return }
        guard probes[id] == nil else { fail("repeated-probe"); return }
        probes[id] = outcome
        if outcome != expected { fail("unexpected-probe-result") }
    }
    // Only fixed calls below use this private, nonescaping helper. No caller
    // supplied callback is stored or reaches an authority/physical boundary.
    private func invalid(_ id: OriginalEraseScratchIssuerDataProbeV1,
        _ body: () throws -> Void) {
        guard firstFailure == nil else { return }
        do { try body(); record(id, .unexpectedSuccess, expecting: .invalidAuthority) }
        catch {
            let outcome: OriginalEraseScratchIssuerDataOutcomeV1 =
                error as? EraseAllServiceError == .invalidAuthority ? .invalidAuthority :
                .unexpectedError(String(String(reflecting: error).prefix(256)))
            record(id, outcome, expecting: .invalidAuthority)
        }
    }
    private static func sameNode(_ a: OriginalEraseScratchTemporalPolicyNodeV1,
        _ b: OriginalEraseScratchTemporalPolicyNodeV1) -> Bool {
        a.kind == b.kind && a.url == b.url && a.fullFact == b.fullFact &&
        a.parentURL == b.parentURL && a.parentFullFact == b.parentFullFact &&
        a.directoryRole == b.directoryRole && a.ancestors.count == b.ancestors.count &&
        zip(a.ancestors, b.ancestors).allSatisfy {
            $0.0.url == $0.1.url && $0.0.fullFact == $0.1.fullFact && $0.0.directoryRole == $0.1.directoryRole
        }
    }
    private static func samePair(_ a: OriginalEraseScratchTemporalPairV1,
        _ b: OriginalEraseScratchTemporalPairV1) -> Bool {
        guard a.kind == b.kind, a.sha256 == b.sha256, a.byteCount == b.byteCount,
              a.device == b.device, a.inode == b.inode, a.user == b.user, a.group == b.group,
              a.parentURL == b.parentURL, a.parentFullFact == b.parentFullFact,
              a.members.count == b.members.count, a.ancestors.count == b.ancestors.count,
              zip(a.members, b.members).allSatisfy({ $0.0.relativePath == $0.1.relativePath &&
                  $0.0.url == $0.1.url && $0.0.fullFact == $0.1.fullFact }),
              zip(a.ancestors, b.ancestors).allSatisfy({ $0.0.url == $0.1.url &&
                  $0.0.fullFact == $0.1.fullFact && $0.0.directoryRole == $0.1.directoryRole }) else { return false }
        switch (a.role, b.role) {
        case let (.declaredLinkPublication(ac, al, at, af), .declaredLinkPublication(bc, bl, bt, bf)):
            return ac == bc && al == bl && at == bt && af == bf
        default: return false // The fixed fixture has no generic-original-pair producer.
        }
    }
    private func captureRevokedPairProjection(_ id: OriginalEraseScratchIssuerDataProbeV1,
        scope: OriginalEraseScratchTemporalObservationScopeV1) {
        guard firstFailure == nil, revokedPairProjections.count < issuedPairProjections.count,
              issuedPairProjections.count <= 2 else { fail("unexpected-projection-capture"); return }
        let expected = issuedPairProjections[revokedPairProjections.count]
        let actual = scope.pairDataProjectionForIssuerTests()
        let equal = actual.count == expected.count && zip(actual, expected).allSatisfy {
            Self.samePair($0.0, $0.1)
        }
        record(id, equal ? .equalData : .differentData, expecting: .equalData)
        guard firstFailure == nil else { return }
        revokedPairProjections.append(actual)
    }
    private func clearSelectedHoldersAtNaturalRevoke() {
        clearExtraHolders()
        // Fixed DATA only remains after this selected hook. The original
        // issuer's own Scope/G ownership and real checked unlock are untouched.
        revokedHolderCounts.append(holderCount)
    }
    private func exactNode(_ id: OriginalEraseScratchIssuerDataProbeV1,
        _ expected: OriginalEraseScratchTemporalPolicyNodeV1,
        scope: OriginalEraseScratchTemporalObservationScopeV1)
        -> OriginalEraseScratchTemporalPolicyNodeV1? {
        guard firstFailure == nil else { return nil }
        do {
            let actual = try scope.policyNodeData(expected.kind, at: expected.url, fullFact: expected.fullFact)
            record(id, Self.sameNode(actual, expected) ? .equalData : .differentData, expecting: .equalData)
            return actual
        } catch {
            record(id, .unexpectedError(String(String(reflecting: error).prefix(256))), expecting: .equalData)
            return nil
        }
    }
    private func exactPair(_ id: OriginalEraseScratchIssuerDataProbeV1,
        _ expected: OriginalEraseScratchTemporalPairV1,
        scope: OriginalEraseScratchTemporalObservationScopeV1)
        -> OriginalEraseScratchTemporalPairV1? {
        guard firstFailure == nil else { return nil }
        do {
            let actual = try scope.pairData(aliasURLs: expected.members.map(\.url))
            record(id, Self.samePair(actual, expected) ? .equalData : .differentData, expecting: .equalData)
            return actual
        } catch {
            record(id, .unexpectedError(String(String(reflecting: error).prefix(256))), expecting: .equalData)
            return nil
        }
    }
    private func missingURL(for value: OriginalEraseScratchTemporalPolicyNodeV1) -> URL {
        value.url.deletingLastPathComponent().appendingPathComponent("issuer-data-missing-" + slot.uuidString.lowercased())
    }

    func issued(_ scope: OriginalEraseScratchTemporalObservationScopeV1,
        nodes: [URL: OriginalEraseScratchTemporalPolicyNodeV1],
        pairs: [OriginalEraseScratchTemporalPairV1], support: URL,
        supportIdentity: EraseSchema2ColdAuxiliaryFirstObserverV1.ParentIdentity) {
        guard support == self.support, firstFailure == nil else { return }
        guard scope.operationID == expectedOperationID else { fail("second-or-wrong-operation"); return }
        guard let device = Int64(exactly: supportIdentity.device), device >= 0,
              let inode = UInt64(exactly: supportIdentity.inode), inode > 0 else {
            fail("invalid-captured-support-identity"); return
        }
        if let previousDevice = supportDevice, let previousInode = supportInode {
            guard device == previousDevice, inode == previousInode else {
                fail("captured-support-identity-drift"); return
            }
        } else {
            supportDevice = device; supportInode = inode
        }
        actualOperationID = scope.operationID
        guard activeID == nil, entry == nil else { fail("nested-issuance"); return }
        guard !selectedIDs.contains(scope.observationID) else { fail("repeated-selected-issuance"); return }
        activeID = scope.observationID
        if phase == .waitingEarliest {
            guard pairs.isEmpty, let actual = nodes.values.sorted(by: {
                $0.url.path.utf8.lexicographicallyPrecedes($1.url.path.utf8)
            }).first, nodes[missingURL(for: actual)] == nil,
                  let next = increment(selectedIssuances) else { fail("earliest-fixture-selection"); return }
            node = actual; earliestScope = scope; selectedIDs.append(scope.observationID)
            issuedPairProjections.append(pairs)
            selectedIssuances = next; entry = .earliest; phase = .earliestActive
            observedNode = exactNode(.nodeExact, actual, scope: scope)
            invalid(.nodeMissingURL) { _ = try scope.policyNodeData(actual.kind,
                at: missingURL(for: actual), fullFact: actual.fullFact) }
            invalid(.nodeWrongKind) { _ = try scope.policyNodeData(
                actual.kind == .temporaryFile ? .stagingDirectory : .temporaryFile,
                at: actual.url, fullFact: actual.fullFact) }
            invalid(.nodeWrongFact) { _ = try scope.policyNodeData(actual.kind,
                at: actual.url, fullFact: actual.fullFact + "|wrong-data") }
            return
        }
        if phase == .waitingPair, !pairs.isEmpty {
            guard pairs.count == 1, let actual = pairs.first,
                  case .declaredLinkPublication = actual.role, actual.members.count == 2,
                  actual.members[0].url != actual.members[1].url,
                  let actualNode = nodes[actual.members[0].url], nodes[missingURL(for: actualNode)] == nil,
                  let next = increment(selectedIssuances) else { fail("declared-pair-fixture-selection"); return }
            pair = actual; pairNode = actualNode; pairScope = scope
            issuedPairProjections.append(pairs)
            selectedIDs.append(scope.observationID); selectedIssuances = next
            entry = .pair; phase = .pairActive
            observedPairNode = exactNode(.pairNodeExact, actualNode, scope: scope)
            observedPair = exactPair(.pairExact, actual, scope: scope)
            let urls = actual.members.map(\.url)
            invalid(.pairZeroCount) { _ = try scope.pairData(aliasURLs: []) }
            invalid(.pairOneCount) { _ = try scope.pairData(aliasURLs: [urls[0]]) }
            invalid(.pairThreeCount) { _ = try scope.pairData(aliasURLs: [urls[0], urls[1], urls[0]]) }
            invalid(.pairReordered) { _ = try scope.pairData(aliasURLs: [urls[1], urls[0]]) }
            invalid(.pairDuplicateMember) { _ = try scope.pairData(aliasURLs: [urls[0], urls[0]]) }
            invalid(.pairMissingMember) { _ = try scope.pairData(aliasURLs: [urls[0], missingURL(for: actualNode)]) }
            if profile == .earlierPairProjectionMembership, firstFailure == nil {
                guard earliestScope == nil, revokedIDs.count == 1,
                      revokedIDs.first == selectedIDs.first, revokedPairProjections.count == 1,
                      let earlierPairs = revokedPairProjections.first, earlierPairs.isEmpty,
                      revokedHolderCounts == [0] else { fail("missing-earliest-natural-revoke"); return }
                // Later real UUID/name arguments did not exist at the earliest
                // revoke. This is shared-selector DATA-projection equivalence,
                // not a later API invocation on the released earlier Scope.
                invalid(.earlierPairProjectionMissing) {
                    _ = try OriginalEraseScratchIssuerPairDataSelectionV1.select(earlierPairs, aliasURLs: urls)
                }
            }
            return
        }
        guard phase == .waitingPair || phase == .complete,
              let next = increment(ordinaryIssuances) else { fail("unexpected-issuance-phase"); return }
        ordinaryIssuances = next; entry = .ordinary
    }

    func naturallyRevoked(_ scope: OriginalEraseScratchTemporalObservationScopeV1, support: URL) {
        guard support == self.support, firstFailure == nil else { return }
        guard scope.operationID == expectedOperationID, actualOperationID == scope.operationID,
              activeID == scope.observationID, let currentEntry = entry else {
            fail("unmatched-natural-revoke"); return
        }
        activeID = nil; entry = nil
        switch currentEntry {
        case .ordinary:
            guard let next = increment(ordinaryRevokes) else { return }
            ordinaryRevokes = next
        case .earliest:
            guard phase == .earliestActive, earliestScope === scope, let actual = node,
                  !revokedIDs.contains(scope.observationID), let next = increment(selectedRevokes) else {
                fail("unexpected-earliest-revoke"); return
            }
            _ = exactNode(.nodeAfterRevoke, actual, scope: scope)
            invalid(.nodeCurrentBindingRevoked) { try scope.requireCurrentBinding() }
            invalid(.nodeAuthorizedRevoked) { _ = try scope.requirePolicyNode(actual.kind,
                at: actual.url, fullFact: actual.fullFact) }
            captureRevokedPairProjection(.nodePairProjectionAfterRevoke, scope: scope)
            clearSelectedHoldersAtNaturalRevoke()
            guard firstFailure == nil else { return }
            revokedIDs.append(scope.observationID); selectedRevokes = next
            if profile == .node { completeSelectedProfile() } else { phase = .waitingPair }
        case .pair:
            guard phase == .pairActive, pairScope === scope, let actual = pair, let actualNode = pairNode,
                  !revokedIDs.contains(scope.observationID), let next = increment(selectedRevokes) else {
                fail("unexpected-pair-revoke"); return
            }
            _ = exactNode(.pairNodeAfterRevoke, actualNode, scope: scope)
            _ = exactPair(.pairAfterRevoke, actual, scope: scope)
            invalid(.pairCurrentBindingRevoked) { try scope.requireCurrentBinding() }
            invalid(.pairNodeAuthorizedRevoked) { _ = try scope.requirePolicyNode(actualNode.kind,
                at: actualNode.url, fullFact: actualNode.fullFact) }
            invalid(.pairAuthorizedRevoked) { _ = try scope.requirePair(aliasURLs: actual.members.map(\.url)) }
            captureRevokedPairProjection(.pairProjectionAfterRevoke, scope: scope)
            clearSelectedHoldersAtNaturalRevoke()
            guard firstFailure == nil else { return }
            revokedIDs.append(scope.observationID); selectedRevokes = next
            completeSelectedProfile()
        }
    }

    private func completeSelectedProfile() {
        let expectedCount: UInt64 = profile == .earlierPairProjectionMembership ? 2 : 1
        guard selectedIssuances == expectedCount, selectedRevokes == expectedCount,
              selectedIDs == revokedIDs, holderCount == 0,
              revokedHolderCounts == Array(repeating: 0, count: Int(expectedCount)),
              issuedPairProjections.count == Int(expectedCount),
              revokedPairProjections.count == Int(expectedCount),
              probes.count == (profile == .node ? 8 :
                profile == .declaredPair ? 14 : 23) else { fail("incomplete-selected-profile"); return }
        // Before this hook returns: immutable values only; no extra Scope/G
        // holder survives the selected lexical revoke. This is NOT G release.
        phase = .complete; clearExtraHolders()
    }
}
#endif

// COLD_NOTIFICATION_CONTROL_POLICY_SCOPE_COMPONENT_V1_BEGIN
/// Immutable comparison fields copied only from the SAME actually entered
/// Window node after the genuine preconstructor reservation. No public maker.
@MainActor struct ColdEraseScratchNotificationControlPolicyNodeV1 {
    fileprivate struct Storage {
        let kind: OwnedFileKindV1
        let url: URL
        let fullFact: String
        let parentFullFact: String
        let parentDescriptor: Int32
        let selectedName: String
        let isDirectory: Bool
        let absoluteURLUTF8Count: UInt64
        let fact: ColdEraseScratchNotificationControlFullFactV1
        let parentFact: ColdEraseScratchNotificationControlFullFactV1
    }
    fileprivate let storage: Storage
    var kind: OwnedFileKindV1 { storage.kind }
    var url: URL { storage.url }
    var fullFact: String { storage.fullFact }
    var parentFullFact: String { storage.parentFullFact }
    var parentDescriptor: Int32 { storage.parentDescriptor }
    var selectedName: String { storage.selectedName }
    var isDirectory: Bool { storage.isDirectory }
    var absoluteURLUTF8Count: UInt64 { storage.absoluteURLUTF8Count }
    var fact: ColdEraseScratchNotificationControlFullFactV1 { storage.fact }
    var parentFact: ColdEraseScratchNotificationControlFullFactV1 { storage.parentFact }

    fileprivate init(node: ColdEraseScratchNotificationReadNodeV1) throws {
        try node.requireCurrentBinding()
        let kind = try node.controlPolicyKind()
        let url = try node.pathURL()
        let fullFact = node.fullFact, parentFullFact = node.parentFullFact
        let fact = try ColdEraseScratchNotificationControlFullFactV1(fullFact)
        let parent = try ColdEraseScratchNotificationControlFullFactV1(parentFullFact)
        guard url.isFileURL, url.standardizedFileURL == url,
              !node.selectedName.isEmpty, node.selectedName.utf8.count <= 255,
              !node.selectedName.contains("/"), !node.selectedName.utf8.contains(0),
              node.selectedName != ".", node.selectedName != "..", node.parentDescriptor >= 0,
              kind == .stagingDirectory || kind == .temporaryFile || kind == .journal || kind == .journalTemporary,
              (fact.mode & UInt32(S_IFMT)) == UInt32(node.isDirectory ? S_IFDIR : S_IFREG),
              (parent.mode & UInt32(S_IFMT)) == UInt32(S_IFDIR),
              node.isDirectory || fact.links == 1 else { throw EraseAllServiceError.invalidAuthority }
        storage = Storage(kind: kind, url: url, fullFact: fullFact, parentFullFact: parentFullFact,
            parentDescriptor: node.parentDescriptor, selectedName: node.selectedName,
            isDirectory: node.isDirectory, absoluteURLUTF8Count: UInt64(url.path.utf8.count),
            fact: fact, parentFact: parent)
        try node.requireCurrentBinding()
    }
    func sameActualFields(as other: Self) -> Bool {
        kind == other.kind && url == other.url && fullFact == other.fullFact
            && parentFullFact == other.parentFullFact && parentDescriptor == other.parentDescriptor
            && selectedName == other.selectedName && isDirectory == other.isDirectory
            && absoluteURLUTF8Count == other.absoluteURLUTF8Count
    }
}

/// Ninth-private row issuer. Actual Window/Node registration and capacity
/// precede construction; failed joins retain every entered owner permanently.
@MainActor final class ColdEraseScratchNotificationControlPolicyObservationScopeV1 {
    private enum State { case registered, observing, completed, rowConsumed, rowClosed, released, uncertain }
    private struct Storage {
        var window: ColdEraseScratchNotificationReadWindowV1?
        var node: ColdEraseScratchNotificationReadNodeV1?
        let windowIdentity: ObjectIdentifier
        let nodeIdentity: ObjectIdentifier
        let operationID: UUID
        let policyNode: ColdEraseScratchNotificationControlPolicyNodeV1
        var state: State = .registered
        var observation: ColdEraseScratchNotificationControlPolicyObservationV1?
        var consumedRow: EraseSchema2ColdAuxiliaryFirstObserverV1.ControlNode?
        var uncertainDescriptor: Int32?
        var overflowDescriptor: Int32?
        var releasedObservationIdentity: ObjectIdentifier?
    }
    private var storage: Storage
    var operationID: UUID { storage.operationID }
    static func requiredBackingBytes(absoluteURLUTF8Count: UInt64) throws -> UInt64 {
        guard absoluteURLUTF8Count > 0 else { throw EraseAllServiceError.invalidAuthority }
        let path = absoluteURLUTF8Count.multipliedReportingOverflow(by: 2)
        guard !path.overflow else { throw EraseAllServiceError.invalidAuthority }
        let own = UInt64(MemoryLayout<Storage>.stride
            + MemoryLayout<ColdEraseScratchNotificationControlPolicyNodeV1.Storage>.stride
            + MemoryLayout<EraseSchema2ColdAuxiliaryFirstObserverV1.ControlNode>.stride
            + 22 * MemoryLayout<Substring>.stride
            + 2 * 241 + 255 + 20 + 3 * MemoryLayout<String>.stride)
        let result = own.addingReportingOverflow(path.partialValue)
        guard !result.overflow else { throw EraseAllServiceError.invalidAuthority }
        return result.partialValue
    }
    var actualBackingBytes: UInt64 {
        get throws { try Self.requiredBackingBytes(absoluteURLUTF8Count: storage.policyNode.absoluteURLUTF8Count) }
    }
    private init(window: ColdEraseScratchNotificationReadWindowV1,
        node: ColdEraseScratchNotificationReadNodeV1, policyNode: ColdEraseScratchNotificationControlPolicyNodeV1) {
        storage = Storage(window: window, node: node, windowIdentity: ObjectIdentifier(window),
            nodeIdentity: ObjectIdentifier(node), operationID: window.operationID, policyNode: policyNode)
    }
    fileprivate static func make(window: ColdEraseScratchNotificationReadWindowV1,
        node: ColdEraseScratchNotificationReadNodeV1) throws -> Self {
        try window.requireNode(node)
        try window.reserveControlPolicyScope(node: node) // real profile BEFORE pathURL/Scope allocation
        let value = Self(window: window, node: node, policyNode: try .init(node: node))
        try window.retainControlPolicyScope(value, node: node) // retains before throwing postproof
        try value.requireCurrentBinding()
        return value
    }
    /// Memory-only producer association. Native must independently hold the
    /// true reservation/current frame; this cannot authorize IO or capacity.
    func requireReservationAssociation(window: ColdEraseScratchNotificationReadWindowV1,
        node: ColdEraseScratchNotificationReadNodeV1) throws {
        guard storage.window === window, storage.node === node,
              operationID == window.operationID, operationID == node.operationID,
              storage.state != .uncertain, storage.state != .released else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
    func requireCurrentBinding() throws {
        guard let window = storage.window, let node = storage.node,
              storage.state == .registered || storage.state == .observing || storage.state == .completed else {
            throw EraseAllServiceError.invalidAuthority
        }
        try window.requireControlPolicyScope(self, node: node)
        try window.requireCurrentBinding(); try node.requireCurrentBinding()
        guard operationID == window.operationID, operationID == node.operationID,
              storage.policyNode.fullFact == node.fullFact,
              storage.policyNode.parentFullFact == node.parentFullFact,
              storage.policyNode.parentDescriptor == node.parentDescriptor,
              storage.policyNode.selectedName == node.selectedName,
              storage.policyNode.kind == (try node.controlPolicyKind()) else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
    func requireNode() throws -> ColdEraseScratchNotificationControlPolicyNodeV1 {
        try requireCurrentBinding(); return storage.policyNode
    }
    func requireNode(_ kind: OwnedFileKindV1, at url: URL, fullFact: String)
        throws -> ColdEraseScratchNotificationControlPolicyNodeV1 {
        let value = try requireNode()
        guard value.kind == kind, value.url == url, value.fullFact == fullFact else {
            throw EraseAllServiceError.invalidAuthority
        }
        return value
    }
    func requireKernelDescriptor() throws -> Int32 {
        try requireCurrentBinding()
        return try storage.node!.heldDescriptor
    }
    func requireObservationConstructionCapacity(additionalBytes: UInt64) throws {
        try requireCurrentBinding()
        guard storage.observation == nil, storage.state == .registered,
              let window = storage.window, let node = storage.node else { throw EraseAllServiceError.invalidAuthority }
        let exact = try ColdEraseScratchNotificationControlPolicyObservationV1.requiredBackingBytes(
            absoluteURLUTF8Count: storage.policyNode.absoluteURLUTF8Count)
        guard additionalBytes == exact else { throw EraseAllServiceError.invalidAuthority }
        try window.requirePolicyObservationConstructionCapacity(node: node, scope: self, additionalBytes: exact)
    }
    func retainObservationAttempt(_ actual: ColdEraseScratchNotificationControlPolicyObservationV1) throws {
        guard storage.observation == nil, storage.state == .registered else { throw EraseAllServiceError.invalidAuthority }
        storage.observation = actual; storage.state = .observing // BEFORE PFP pin/getter IO
        try storage.node!.retainPolicyObservation(actual)
        try requireObservationAttempt(actual)
    }
    func requireObservationAttempt(_ actual: ColdEraseScratchNotificationControlPolicyObservationV1) throws {
        guard storage.observation === actual, actual.scopeIdentity == ObjectIdentifier(self),
              actual.operationID == operationID, storage.state == .observing || storage.state == .completed else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireCurrentBinding(); try storage.node!.requirePolicyObservation(actual)
    }
    func requireObservationCapacity(_ actual: ColdEraseScratchNotificationControlPolicyObservationV1,
        additionalBytes: UInt64) throws {
        try requireObservationAttempt(actual)
        let exact = try actual.actualBackingBytes
        guard additionalBytes == exact else { throw EraseAllServiceError.invalidAuthority }
        try storage.window!.requirePolicyObservationCapacity(node: storage.node!, scope: self,
            observation: actual, additionalBytes: exact)
    }
    func completeObservationAttempt(_ actual: ColdEraseScratchNotificationControlPolicyObservationV1) throws {
        try requireObservationAttempt(actual); try actual.requireCheckedSettlement()
        guard storage.state == .observing else { throw EraseAllServiceError.invalidAuthority }
        storage.state = .completed
        try requireObservationAttempt(actual)
    }
    /// Called only by the genuine cold scanner inside the same Node callback.
    /// Target validates actual raw row SHA/EOF and retains both real slots.
    fileprivate func consumeControlRow(_ row: EraseSchema2ColdAuxiliaryFirstObserverV1.ControlNode) throws {
        do {
            guard storage.state == .completed, let actual = storage.observation,
                  let node = storage.node, let window = storage.window else { throw EraseAllServiceError.invalidAuthority }
            try requireObservationAttempt(actual); try actual.requireCheckedSettlement()
            try node.consumeControlRow(row, observation: actual, window: window)
            storage.consumedRow = row; storage.state = .rowConsumed
        } catch { poisonOnUncertainObservation(); throw error }
    }
    /// Actual entered Window calls this ONLY after same Node's checked close,
    /// returned backing-alias consumer and same real policy/control row slots.
    func releaseAfterCheckedReadNode(node: ColdEraseScratchNotificationReadNodeV1,
        window: ColdEraseScratchNotificationReadWindowV1,
        observation: ColdEraseScratchNotificationControlPolicyObservationV1) throws {
        do {
            guard storage.node === node, storage.window === window, storage.observation === observation,
                  storage.state == .rowConsumed, let row = storage.consumedRow else {
                throw EraseAllServiceError.invalidAuthority
            }
            try node.requireConsumedControlRow(row, observation: observation, window: window)
            try observation.requireCheckedSettlement()
            storage.state = .rowClosed
            try observation.releaseConsumedScope(self)
            storage.releasedObservationIdentity = ObjectIdentifier(observation)
            storage.observation = nil; storage.node = nil; storage.window = nil
            storage.consumedRow = nil; storage.state = .released
        } catch { poisonOnUncertainObservation(); throw error }
    }
    func requireConsumedObservationAttempt(_ actual: ColdEraseScratchNotificationControlPolicyObservationV1) throws {
        guard storage.state == .rowClosed, storage.observation === actual,
              actual.scopeIdentity == ObjectIdentifier(self), actual.operationID == operationID,
              let row = storage.consumedRow, let node = storage.node, let window = storage.window else {
            throw EraseAllServiceError.invalidAuthority
        }
        try node.requireConsumedControlRow(row, observation: actual, window: window)
    }
    /// Positive producer memory after the real row helper discharged the
    /// strong cycle. Callers still retain/pass the SAME true objects; neither
    /// weak disappearance nor these identity scalars issue resource authority.
    func requireCheckedRowRelease(node: ColdEraseScratchNotificationReadNodeV1,
        window: ColdEraseScratchNotificationReadWindowV1,
        observation: ColdEraseScratchNotificationControlPolicyObservationV1) throws {
        guard storage.state == .released, storage.window == nil, storage.node == nil,
              storage.observation == nil, storage.consumedRow == nil,
              storage.windowIdentity == ObjectIdentifier(window), storage.nodeIdentity == ObjectIdentifier(node),
              storage.releasedObservationIdentity == ObjectIdentifier(observation),
              operationID == window.operationID, operationID == node.operationID,
              observation.scopeIdentity == ObjectIdentifier(self), observation.operationID == operationID else {
            throw EraseAllServiceError.invalidAuthority
        }
        try observation.requireCheckedSettlement()
    }
    func retainUncertainDescriptor(_ descriptor: Int32) {
        if storage.uncertainDescriptor == nil { storage.uncertainDescriptor = descriptor }
        else { storage.overflowDescriptor = descriptor }
        poisonOnUncertainObservation()
    }
    func poisonOnUncertainObservation() {
        storage.state = .uncertain
        storage.window?.poisonControlPolicyScope(self, node: storage.node)
    }
}

/// Exact complete-field operands derived from the scanner's real typed slots
/// before any result array/dictionary/Snapshot allocation. Source roles and
/// counts are DATA, never observation or effect permission.
@MainActor struct ColdEraseScratchNotificationSnapshotMaterializationProfileV1: Equatable {
    private struct Storage: Equatable, Sendable {
        let windowIdentity: ObjectIdentifier
        let operationID: UUID
        let start: Int, end: Int
        var supportNameCount: UInt64 = 0, supportNameUTF8Bytes: UInt64 = 0
        var supportTreeCount: UInt64 = 0, supportTreeKeyUTF8Bytes: UInt64 = 0
        var operationsChildCount: UInt64 = 0, operationsChildKeyUTF8Bytes: UInt64 = 0
        var ingressControlCount: UInt64 = 0, ingressPathUTF8Bytes: UInt64 = 0
        var notificationControlCount: UInt64 = 0, notificationPathUTF8Bytes: UInt64 = 0
        var factUTF8Bytes: UInt64 = 0, digestUTF8Bytes: UInt64 = 0, policyStringUTF8Bytes: UInt64 = 0
        var stringCount: UInt64 = 0
        var fieldMask: UInt16 = 0
        var ingressPresent = false, notificationPresent = false
        let simultaneousResultCount: UInt64 = 2
    }
    private let storage: Storage
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.storage == rhs.storage }
    static func implementedStoredBackingBytes() -> UInt64 { UInt64(MemoryLayout<Storage>.stride) }
    fileprivate var start: Int { storage.start }
    fileprivate var end: Int { storage.end }
    fileprivate var supportNameCount: Int { Int(storage.supportNameCount) }
    fileprivate var supportTreeCount: Int { Int(storage.supportTreeCount) }
    fileprivate var operationsChildCount: Int { Int(storage.operationsChildCount) }
    fileprivate var ingressControlCount: Int { Int(storage.ingressControlCount) }
    fileprivate var notificationControlCount: Int { Int(storage.notificationControlCount) }
    fileprivate var ingressPresent: Bool { storage.ingressPresent }
    fileprivate var notificationPresent: Bool { storage.notificationPresent }
    fileprivate static func make(window: ColdEraseScratchNotificationReadWindowV1, start: Int, end: Int) throws -> Self {
        guard start >= 0, end > start, end <= window.snapshotSlotCount else { throw EraseAllServiceError.invalidAuthority }
        var actual = Storage(windowIdentity: ObjectIdentifier(window), operationID: window.operationID, start: start, end: end)
        func add(_ lhs: inout UInt64, _ rhs: UInt64) throws { lhs = try ColdEraseControlBinaryV1.adding(lhs, rhs) }
        func string(_ value: String, _ role: UInt8) throws {
            let count = UInt64(value.utf8.count)
            try add(&actual.stringCount, 1)
            switch role {
            case 0: try add(&actual.supportNameUTF8Bytes, count)
            case 1: try add(&actual.supportTreeKeyUTF8Bytes, count)
            case 2: try add(&actual.operationsChildKeyUTF8Bytes, count)
            case 3: try add(&actual.ingressPathUTF8Bytes, count)
            case 4: try add(&actual.notificationPathUTF8Bytes, count)
            case 5: try add(&actual.factUTF8Bytes, count)
            case 6: try add(&actual.digestUTF8Bytes, count)
            case 7: try add(&actual.policyStringUTF8Bytes, count)
            default: throw EraseAllServiceError.invalidAuthority
            }
        }
        func field(_ bit: UInt16) throws {
            guard actual.fieldMask & bit == 0 else { throw EraseAllServiceError.invalidAuthority }
            actual.fieldMask |= bit
        }
        func tree(_ value: EraseSchema2ColdAuxiliaryFirstObserverV1.Tree) throws {
            if case .present(let fact, let digest) = value {
                guard fact.utf8.count <= 241, digest.utf8.count == 64 else { throw EraseAllServiceError.invalidAuthority }
                try string(fact, 5); try string(digest, 6)
            }
        }
        func row(_ value: EraseSchema2ColdAuxiliaryFirstObserverV1.ControlNode, ingress: Bool) throws {
            guard value.path.utf8.count <= 16_639, value.fullFact.utf8.count <= 241,
                  value.policy.backupExcluded == true,
                  value.policy.state == .strictComplete || value.policy.state == .pendingSimulatorRequest else {
                throw EraseAllServiceError.invalidAuthority
            }
            if ingress { try add(&actual.ingressControlCount, 1); try string(value.path, 3) }
            else { try add(&actual.notificationControlCount, 1); try string(value.path, 4) }
            try string(value.fullFact, 5)
            try string(value.policy.state.rawValue, 7)
            try string(value.policy.urlProtection, 7)
            try string(value.policy.fileManagerProtection, 7)
            if let digest = value.contentSHA256 {
                guard digest.utf8.count == 64 else { throw EraseAllServiceError.invalidAuthority }
                try string(digest, 6)
            }
        }
        for ordinal in start..<end {
            try window.withSnapshotSlot(at: ordinal) { slot in
                switch slot {
                case .name(let value):
                    guard value.utf8.count <= 255 else { throw EraseAllServiceError.invalidAuthority }
                    try add(&actual.supportNameCount, 1); try string(value, 0)
                case .supportTree(let key, let value):
                    guard key.utf8.count <= 255 else { throw EraseAllServiceError.invalidAuthority }
                    try add(&actual.supportTreeCount, 1); try string(key, 1); try tree(value)
                case .child(let key, let value):
                    guard key.utf8.count <= 255 else { throw EraseAllServiceError.invalidAuthority }
                    try add(&actual.operationsChildCount, 1); try string(key, 2)
                    switch value {
                    case .directory(let fact, let digest), .regular(let fact, let digest):
                        guard fact.utf8.count <= 241, digest.utf8.count == 64 else { throw EraseAllServiceError.invalidAuthority }
                        try string(fact, 5); try string(digest, 6)
                    }
                case .ingressControl(let value): try row(value, ingress: true)
                case .notificationControl(let value): try row(value, ingress: false)
                case .supportIdentity(_, let fact): try field(1); guard fact.utf8.count <= 241 else { throw EraseAllServiceError.invalidAuthority }; try string(fact, 5)
                case .cacheIdentity: try field(2)
                case .temporaryIdentity: try field(4)
                case .operations(let value): try field(8); try tree(value)
                case .ingressPresence(let value): try field(16); actual.ingressPresent = value
                case .notificationPresence(let value): try field(32); actual.notificationPresent = value
                case .notificationStableDigest(let value):
                    try field(64)
                    if let value { guard value.utf8.count == 64 else { throw EraseAllServiceError.invalidAuthority }; try string(value, 6) }
                case .cacheTree(let value): try field(128); try tree(value)
                case .temporaryTree(let value): try field(256); try tree(value)
                case .control, .checkedNode, .policy: break // real source-owner slots stay separately Native charged
                case .tree: throw EraseAllServiceError.invalidAuthority // no anonymous field role can issue a Snapshot
                }
            }
        }
        guard actual.fieldMask == 511, actual.supportNameCount <= 9,
              actual.supportTreeCount == 6, actual.operationsChildCount <= 100_000,
              actual.ingressControlCount <= 100_000, actual.notificationControlCount <= 11,
              actual.ingressPresent == (actual.ingressControlCount > 0),
              actual.notificationPresent == (actual.notificationControlCount > 0) else { throw EraseAllServiceError.invalidAuthority }
        return Self(storage: actual)
    }
    func requireCurrentSlotBinding(window: ColdEraseScratchNotificationReadWindowV1) throws {
        guard storage.windowIdentity == ObjectIdentifier(window), storage.operationID == window.operationID,
              try Self.make(window: window, start: storage.start, end: storage.end) == self else {
            throw EraseAllServiceError.invalidAuthority
        }
    }
    /// Declared fixed fields, logical elements and UTF8 payload, including
    /// constructor/returned-result overlap. Swift/Foundation/allocator bucket
    /// headers, COW implementation, URL/Error internals and VM are unmeasured.
    func requiredMaterializationBytes() throws -> UInt64 {
        var total = UInt64(MemoryLayout<Storage>.stride)
        func add(_ value: UInt64) throws { total = try ColdEraseControlBinaryV1.adding(total, value) }
        func multiply(_ count: UInt64, _ stride: Int) throws {
            let value = count.multipliedReportingOverflow(by: UInt64(stride))
            guard !value.overflow else { throw EraseAllServiceError.invalidAuthority }; try add(value.partialValue)
        }
        try add(ColdEraseScratchNotificationSnapshotResultV1.implementedStoredBackingBytes())
        try add(UInt64(MemoryLayout<EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot>.stride))
        try multiply(storage.supportNameCount, MemoryLayout<String>.stride)
        try multiply(storage.supportTreeCount, MemoryLayout<(String, EraseSchema2ColdAuxiliaryFirstObserverV1.Tree)>.stride)
        try multiply(storage.operationsChildCount, MemoryLayout<(String, EraseSchema2ColdAuxiliaryFirstObserverV1.OperationsChild)>.stride)
        try multiply(try ColdEraseControlBinaryV1.adding(storage.ingressControlCount, storage.notificationControlCount),
            MemoryLayout<EraseSchema2ColdAuxiliaryFirstObserverV1.ControlNode>.stride)
        try multiply(storage.stringCount, MemoryLayout<String>.stride)
        try add(storage.supportNameUTF8Bytes); try add(storage.supportTreeKeyUTF8Bytes)
        try add(storage.operationsChildKeyUTF8Bytes); try add(storage.ingressPathUTF8Bytes)
        try add(storage.notificationPathUTF8Bytes); try add(storage.factUTF8Bytes)
        try add(storage.digestUTF8Bytes); try add(storage.policyStringUTF8Bytes)
        let overlap = total.multipliedReportingOverflow(by: storage.simultaneousResultCount)
        guard !overlap.overflow else { throw EraseAllServiceError.invalidAuthority }
        return overlap.partialValue
    }
}

/// The real complete Snapshot result. Native retains this owner before its
/// arrays/dictionaries or Snapshot are built; uncertain results retain actual
/// partial fields, source profile and error. No deinit silently settles them.
@MainActor final class ColdEraseScratchNotificationSnapshotResultV1 {
    private enum State { case reserved, building, returned, uncertain }
    private struct Storage {
        let window: ColdEraseScratchNotificationReadWindowV1
        let operationID: UUID
        let constructionProfile: ColdEraseScratchNotificationSnapshotMaterializationProfileV1
        var state: State = .reserved
        var snapshot: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot?
        var actualMaterializationBytes: UInt64 = 0
        var retainedFailure: Error?
        var supportNames: [String] = []
        var supportTrees: [String: EraseSchema2ColdAuxiliaryFirstObserverV1.Tree] = [:]
        var operationsChildren: [String: EraseSchema2ColdAuxiliaryFirstObserverV1.OperationsChild] = [:]
        var ingress: [EraseSchema2ColdAuxiliaryFirstObserverV1.ControlNode] = []
        var notification: [EraseSchema2ColdAuxiliaryFirstObserverV1.ControlNode] = []
    }
    private var storage: Storage
    private init(window: ColdEraseScratchNotificationReadWindowV1,
        profile: ColdEraseScratchNotificationSnapshotMaterializationProfileV1) {
        storage = Storage(window: window, operationID: window.operationID, constructionProfile: profile)
    }
    static func implementedStoredBackingBytes() -> UInt64 { UInt64(MemoryLayout<Storage>.stride) }
    func requireReservationAssociation(window: ColdEraseScratchNotificationReadWindowV1,
        profile: ColdEraseScratchNotificationSnapshotMaterializationProfileV1) throws {
        guard storage.window === window, storage.operationID == window.operationID,
              storage.constructionProfile == profile, storage.state != .uncertain else { throw EraseAllServiceError.invalidAuthority }
    }
    fileprivate static func make(window: ColdEraseScratchNotificationReadWindowV1,
        start: Int, end: Int) throws -> Self {
        let profile = try ColdEraseScratchNotificationSnapshotMaterializationProfileV1.make(window: window, start: start, end: end)
        try window.requireSnapshotResultConstructionCapacity(profile: profile)
        let actual = Self(window: window, profile: profile)
        try window.retainSnapshotResult(actual, profile: profile) // BEFORE real materialization allocations
        do {
            try actual.build()
            try window.recordReturnedSnapshotResult(actual)
            return actual
        } catch {
            actual.storage.retainedFailure = error; actual.storage.state = .uncertain
            window.poisonSnapshotMaterialization(); throw error
        }
    }
    private func build() throws {
        guard storage.state == .reserved else { throw EraseAllServiceError.invalidAuthority }
        let profile = storage.constructionProfile, window = storage.window
        try profile.requireCurrentSlotBinding(window: window)
        storage.actualMaterializationBytes = try profile.requiredMaterializationBytes(); storage.state = .building
        storage.supportNames.reserveCapacity(profile.supportNameCount)
        storage.supportTrees.reserveCapacity(profile.supportTreeCount)
        storage.operationsChildren.reserveCapacity(profile.operationsChildCount)
        storage.ingress.reserveCapacity(profile.ingressControlCount)
        storage.notification.reserveCapacity(profile.notificationControlCount)
        var support: EraseSchema2ColdAuxiliaryFirstObserverV1.ParentIdentity?
        var caches: EraseSchema2ColdAuxiliaryFirstObserverV1.ParentIdentity?
        var temporary: EraseSchema2ColdAuxiliaryFirstObserverV1.ParentIdentity?
        var supportFact: String?, operations: EraseSchema2ColdAuxiliaryFirstObserverV1.Tree?
        var cacheTree: EraseSchema2ColdAuxiliaryFirstObserverV1.Tree?, temporaryTree: EraseSchema2ColdAuxiliaryFirstObserverV1.Tree?
        var stable: String?
        for ordinal in profile.start..<profile.end {
            try window.withSnapshotSlot(at: ordinal) { slot in
                switch slot {
                case .name(let value): storage.supportNames.append(value)
                case .supportTree(let key, let value):
                    guard storage.supportTrees.updateValue(value, forKey: key) == nil else { throw EraseAllServiceError.invalidAuthority }
                case .child(let key, let value):
                    guard storage.operationsChildren.updateValue(value, forKey: key) == nil else { throw EraseAllServiceError.invalidAuthority }
                case .ingressControl(let value): storage.ingress.append(value)
                case .notificationControl(let value): storage.notification.append(value)
                case .supportIdentity(let value, let fact): support = value; supportFact = fact
                case .cacheIdentity(let value): caches = value
                case .temporaryIdentity(let value): temporary = value
                case .operations(let value): operations = value
                case .cacheTree(let value): cacheTree = value
                case .temporaryTree(let value): temporaryTree = value
                case .notificationStableDigest(let value): stable = value
                case .ingressPresence, .notificationPresence, .control, .checkedNode, .policy: break
                case .tree: throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        storage.ingress.sort { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
        storage.notification.sort { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
        func requireUnique(_ rows: [EraseSchema2ColdAuxiliaryFirstObserverV1.ControlNode]) throws {
            if rows.count > 1 {
                for ordinal in 1..<rows.count {
                    guard rows[ordinal - 1].path != rows[ordinal].path else { throw EraseAllServiceError.invalidAuthority }
                }
            }
        }
        try requireUnique(storage.ingress); try requireUnique(storage.notification)
        guard let support, let caches, let temporary, let supportFact, let operations, let cacheTree, let temporaryTree,
              storage.supportNames.count == profile.supportNameCount,
              storage.supportTrees.count == profile.supportTreeCount,
              storage.operationsChildren.count == profile.operationsChildCount,
              storage.ingress.count == profile.ingressControlCount, storage.notification.count == profile.notificationControlCount,
              storage.supportNames == storage.supportNames.sorted(),
              Set(storage.supportNames).count == storage.supportNames.count,
              profile.notificationPresent == (stable != nil) else { throw EraseAllServiceError.invalidAuthority }
        storage.snapshot = .init(supportIdentity: support, cacheIdentity: caches, temporaryIdentity: temporary,
            supportFact: supportFact, supportNames: storage.supportNames, supportTrees: storage.supportTrees,
            operations: operations, operationsChildren: storage.operationsChildren,
            ingressControlNodes: profile.ingressPresent ? storage.ingress : nil,
            notificationControlNodes: profile.notificationPresent ? storage.notification : nil,
            notificationControlStableDigest: stable, cacheTree: cacheTree, temporaryTree: temporaryTree)
        try profile.requireCurrentSlotBinding(window: window)
        storage.state = .returned
    }
    func requireReturnedSnapshot() throws -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot {
        guard storage.state == .returned, storage.retainedFailure == nil,
              storage.actualMaterializationBytes == (try storage.constructionProfile.requiredMaterializationBytes()),
              let snapshot = storage.snapshot else { throw EraseAllServiceError.invalidAuthority }
        return snapshot
    }
}
// COLD_NOTIFICATION_CONTROL_POLICY_SCOPE_COMPONENT_V1_END
