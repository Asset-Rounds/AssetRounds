import Darwin
import CryptoKit
import Foundation

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
    private var ingressControlURL: URL?
    private var notificationControlURL: URL?

    /// Borrowed descriptors must not be closed or retained here. The caller
    /// brackets this entire synchronous call with its genuine named-root proof.
    /// Cache/temp sibling activity is outside our ownership: only each parent
    /// identity and the exact FieldEvidenceApp child are observed there.
    func captureFirst(support: Int32, caches: Int32, temporary: Int32,
        applicationSupportURL: URL) throws -> Snapshot {
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
    /// physical child; only the existing empty ScratchData root may advance
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
        for receipt in receipts {
            try receipt.requireCheckedSettlement()
            guard receipt.operationsFact == operationsFact,
                  receipt.beforeScratchRootFact == priorFact,
                  receipt.beforeScratchDigest == priorDigest else {
                throw EraseAllServiceError.invalidAuthority
            }
            priorFact = receipt.afterScratchRootFact
            priorDigest = receipt.afterScratchDigest
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
        guard two == one else { throw EraseAllServiceError.invalidAuthority }
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
