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
/// Primitive callbacks reprove actual G/frame and lifetime, never a payload
/// rescan. PFP independently pins all declared named/held ancestors and nodes.
@MainActor
final class OriginalEraseScratchTemporalObservationScopeV1 {
    let operationID: UUID
    let observationID = UUID()
    fileprivate let heldScope: OriginalEraseScratchCleanupHeldGScopeV1
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
    func requirePolicyNode(_ kind: OwnedFileKindV1, at url: URL,
        fullFact: String) throws -> OriginalEraseScratchTemporalPolicyNodeV1 {
        try requireCurrentBinding()
        guard let node = nodes[url], node.url == url,
              node.kind == kind, node.fullFact == fullFact else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireCurrentBinding(); return node
    }
    func requirePair(aliasURLs: [URL]) throws -> OriginalEraseScratchTemporalPairV1 {
        try requireCurrentBinding()
        guard aliasURLs.count == 2,
              let pair = pairs.first(where: { $0.members.map(\.url) == aliasURLs }) else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireCurrentBinding(); return pair
    }
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

/// Retained before IO; no descriptor, effect permit, Registry or current-image
/// authority escapes. The only image advance is one matched closed primitive.
@MainActor
final class OriginalEraseScratchCleanupImageOwnerV1 {
    typealias Image = OriginalEraseScratchCleanupImageV1
    typealias Intent = OriginalEraseScratchCleanupPrimitiveIntentV1
    typealias Outcome = OriginalEraseScratchCleanupPrimitiveOutcomeV1
    fileprivate let operationID: UUID
    private let admission: OriginalEraseScratchCleanupInitialAdmissionV1
    private var callHeldScope: OriginalEraseScratchCleanupHeldGScopeV1?
    private var lastMatchedHeldScope: OriginalEraseScratchCleanupHeldGScopeV1?
    fileprivate var currentHeldScope: OriginalEraseScratchCleanupHeldGScopeV1 { admission.heldScope }
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
    private struct Publication {
        let createID: UUID
        var temporaryPath: String
        var finalPath: String
        let bytes: Data
        let sha256: String
        let exclusiveFinalRename: Bool
        var written: Int
        var acceptedPolicy: Bool
        var linkID: UUID?
        var replacementID: UUID?
    }
    private var publications: [UUID: Publication] = [:]
    private var pathMapping: [String: String] = [:]
    private var consumed: Set<String> = []
    private var retainedSources: [String: (bytes: Data, fullFact: String)] = [:]
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

    init(admission: OriginalEraseScratchCleanupInitialAdmissionV1) {
        self.admission = admission; operationID = admission.operationID
    }
    fileprivate func poison() {
        poisoned = true; activeScope?.revoke(); activeEffectScope?.revoke(); admission.poisonOnUncertainCleanup()
    }
    private func requireHeld() throws {
        guard !poisoned, uncertainFDs.isEmpty, uncertainDirectories.isEmpty else {
            throw EraseAllServiceError.invalidAuthority
        }
        guard callHeldScope == nil || callHeldScope === admission.heldScope else {
            throw EraseAllServiceError.invalidAuthority
        }
        try admission.requireHeld()
        if let pending { try admission.requirePrimitiveRequest(intent:pending,outcome:observationOutcome) }
    }
    fileprivate func requireScope(_ scope: OriginalEraseScratchTemporalObservationScopeV1) throws {
        guard activeScope === scope, scope.operationID == operationID,
              scope.heldScope === admission.heldScope else {
            throw EraseAllServiceError.invalidAuthority
        }
        try requireHeld()
    }
    fileprivate func retainPolicyAttempt(_ attempt: OriginalEraseScratchTemporalPolicyAttemptV1) {
        policyAttempts.append(attempt)
    }
    private func checked<T>(_ body: () throws -> T) throws -> T {
        guard callHeldScope == nil else { throw EraseAllServiceError.invalidAuthority }
        callHeldScope = admission.heldScope
        defer { callHeldScope = nil }
        do { try requireHeld(); let value = try body(); try requireHeld(); return value }
        catch { poison(); throw error }
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
    private nonisolated static func directoryMutation(_ a: String, _ b: String, linkDelta: Int64) -> Bool {
        let x = fields(a), y = fields(b)
        guard stable(a,b), let old = Int64(x[5]), let new = Int64(y[5]),
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
        try checked {
            guard !attempted else { throw EraseAllServiceError.invalidAuthority }
            attempted = true
            guard try admission.observer.firstObservation() == admission.firstSnapshot,
                  admission.policyReceipt.checkedSettled,
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
            let one = try observe(support: support, caches: caches, temporary: temporary,
                operations: operations, outcome: nil, initialCapture: true)
            let two = try observe(support: support, caches: caches, temporary: temporary,
                operations: operations, outcome: nil, initialCapture: true)
            guard one == two else { throw EraseAllServiceError.invalidAuthority }
            initial = one; current = one; return one
        }
    }
    func requireInitialImage(_ image: Image, support: Int32, caches: Int32,
        temporary: Int32, operations: Int32) throws {
        try checked {
            guard image == initial, current == initial, pending == nil else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireImage(image, support: support, caches: caches,
                temporary: temporary, operations: operations)
        }
    }
    func requireFinal(_ image: Image, support: Int32, caches: Int32,
        temporary: Int32, operations: Int32) throws {
        try checked {
            guard pending == nil, image == current else { throw EraseAllServiceError.invalidAuthority }
            try requireImage(image, support: support, caches: caches,
                temporary: temporary, operations: operations)
        }
    }
    func requireCanonicalSource(path: String, bytes: Data, fullFact: String) throws {
        try checked {
            _ = try Self.path(path)
            guard let image = current, let node = Self.nodes(image)[path],
                  node.fullFact == fullFact,
                  node.contentSHA256 == StoreMigrationCanonicalJSONV1.sha256(bytes),
                  Int64(bytes.count) == Int64(Self.fields(fullFact)[6]) else {
                throw EraseAllServiceError.invalidAuthority
            }
            let ownVersion = publications.values.contains {
                $0.finalPath == path && $0.bytes == bytes && $0.written == bytes.count && $0.acceptedPolicy
            }
            if !ownVersion {
                try admission.requireCanonicalSource(path: path, bytes: bytes, fullFact: fullFact)
                if let old = retainedSources[path] {
                    guard old.bytes == bytes, old.fullFact == fullFact else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                } else { retainedSources[path] = (bytes, fullFact) }
            }
            // Original bytes stay retained; own newer versions are retained in
            // each immutable create recipe, even after their paths disappear.
        }
    }
    func willPerform(_ intent: Intent, support: Int32, caches: Int32,
        temporary: Int32, operations: Int32) throws {
        try checked {
            try settleObservationScopes()
            guard activeCatalog == nil, pending == nil, intent.operationID == operationID,
                  intent.before == current,
                  attemptID == nil || attemptID == intent.attemptID,
                  nextSequence == nil || nextSequence == intent.sequence else {
                throw EraseAllServiceError.invalidAuthority
            }
            try requireImage(intent.before, support: support, caches: caches,
                temporary: temporary, operations: operations)
            if case .createTemporary = intent.kind {
                try admission.requirePublicationRequest(intent: intent)
            }
            try validateRequest(intent)
            // Retain exact intent before the first effect; no future outcome.
            attemptID = intent.attemptID; pending = intent
        }
    }
    func didPerform(_ outcome: Outcome, support: Int32, caches: Int32,
        temporary: Int32, operations: Int32) throws -> Image {
        guard pending === outcome.intent else { poison(); throw EraseAllServiceError.invalidAuthority }
        observationOutcome = outcome
        defer { observationOutcome = nil }
        return try checked {
            guard outcome.intent.operationID == operationID,
                  outcome.result >= 0 else { throw EraseAllServiceError.invalidAuthority }
            if case .requestPolicy = outcome.intent.kind {
                guard let scope = activeEffectScope else { throw EraseAllServiceError.invalidAuthority }
                try scope.requireCheckedSettlement()
                scope.revoke(); activeEffectScope = nil
            }
            let one = try observe(support: support, caches: caches, temporary: temporary,
                operations: operations, outcome: outcome, initialCapture: false)
            let two = try observe(support: support, caches: caches, temporary: temporary,
                operations: operations, outcome: outcome, initialCapture: false)
            guard one == two else { throw EraseAllServiceError.invalidAuthority }
            try requireDelta(outcome, after: one)
            try commit(outcome)
            let next = outcome.intent.sequence.addingReportingOverflow(1)
            guard !next.overflow else { throw EraseAllServiceError.invalidAuthority }
            nextSequence = next.partialValue; current = one; pending = nil
            return one
        }
    }
    private func requireImage(_ image: Image, support: Int32, caches: Int32,
        temporary: Int32, operations: Int32) throws {
        let one = try observe(support: support, caches: caches, temporary: temporary,
            operations: operations, outcome: nil, initialCapture: false)
        let two = try observe(support: support, caches: caches, temporary: temporary,
            operations: operations, outcome: nil, initialCapture: false)
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
        try requireHeld()
        let fd = Darwin.openat(parent, name, flags | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw EraseAllServiceError.invalidAuthority }
        var closeAttempted = false
        do {
            try requireHeld(); let value = try body(fd); try requireHeld()
            closeAttempted = true
            guard Darwin.close(fd) == 0 else {
                uncertainFDs.append(fd); poison(); throw EraseAllServiceError.invalidAuthority
            }
            try requireHeld(); return value
        } catch {
            if !closeAttempted {
                closeAttempted = true
                if Darwin.close(fd) != 0 { uncertainFDs.append(fd) }
            }
            poison(); throw error
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
                uncertainDirectories.append(directory); poison()
                throw EraseAllServiceError.invalidAuthority
            }
            try requireHeld()
            guard Set(values).count == values.count else { throw EraseAllServiceError.invalidAuthority }
            return values.sorted()
        } catch {
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
    private func candidatePublications(_ outcome: Outcome?) throws -> [UUID: Publication] {
        var value = publications
        guard let outcome else { return value }
        switch outcome.intent.kind {
        case .createTemporary(let path, let final, let bytes, let sha, _, let exclusive):
            value[outcome.intent.requestID] = Publication(createID: outcome.intent.requestID,
                temporaryPath: path, finalPath: final, bytes: bytes, sha256: sha,
                exclusiveFinalRename: exclusive, written: 0, acceptedPolicy: false,
                linkID: nil, replacementID: nil)
        case .writeTemporary(let path, _, _):
            guard let id = value.first(where: { $0.value.temporaryPath == path })?.key,
                  let count = Int(exactly: outcome.result) else { throw EraseAllServiceError.invalidAuthority }
            guard count >= 0, count <= value[id]!.bytes.count - value[id]!.written else {
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
        case .renamePublication(let source, let final, let exclusive):
            if !exclusive {
                guard let id = value.first(where: { $0.value.finalPath == source })?.key else {
                    throw EraseAllServiceError.invalidAuthority
                }
                value[id]!.finalPath = final
                value[id]!.replacementID = outcome.intent.requestID
            }
        default: break
        }
        return value
    }
    private func rawScan(operations: Int32, support: Int32,
        publications recipes: [UUID: Publication], outcome: Outcome?) throws -> RawImage {
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
            let sum = maximumBytes.addingReportingOverflow(Int64(recipe.bytes.count))
            guard !sum.overflow else { throw EraseAllServiceError.invalidAuthority }
            maximumBytes = sum.partialValue
        }
        let namespaceBudget = maximumBytes.multipliedReportingOverflow(by: 2)
        guard !namespaceBudget.overflow else { throw EraseAllServiceError.invalidAuthority }
        let rootNames = try names(operations, maximum: admission.notificationAfter.operationsChildren.count)
        var visited = 0, namespaceBytes: Int64 = 0
        let admittedOriginalPaths = Set((admission.originalGenericPairs ?? []).flatMap(\.originalPaths)
            .map { currentPath($0,outcome:outcome) })
        let publicationPaths = Set(recipes.values.filter { $0.linkID != nil }
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
            if path == "ProtectedIngressReceiptsV1" {
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
            guard admission.firstSnapshot.operationsChildren["ScratchDataV1"]
                    == .directory(rootFact: scratch.fullFact,digest: scratch.digest) else {
                throw EraseAllServiceError.invalidAuthority
            }
        } else {
            guard admission.firstSnapshot.operationsChildren["ScratchDataV1"] == nil else {
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
        let recipes = try candidatePublications(outcome)
        let raw = try rawScan(operations:operations,support:support,publications:recipes,
            outcome: outcome)
        if initialCapture { try requireInitialRaw(raw) }
        else if let outcome { try requireRawDelta(outcome,after:raw) }
        else {
            guard let current else { throw EraseAllServiceError.invalidAuthority }
            try requireSameRaw(current,raw)
        }
        try admission.observer.requireOriginalScratchOutside(anchor:admission.notificationAfter,
            operationsFact:Self.full(raw.operationsFact),operationsNames:raw.operationsNames,
            support:support,caches:caches,temporary:temporary,operations:operations,
            requireHeld: { try self.requireHeld() })
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
            if let link = recipe.linkID, paths.allSatisfy({ raw.nodes[$0] != nil }) {
                guard recipe.acceptedPolicy, recipe.written == recipe.bytes.count else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let value = try pair(paths,raw:raw,sha:recipe.sha256,count:Int64(recipe.bytes.count),
                    role:.declaredLinkPublication(createRequestID:recipe.createID,linkRequestID:link,
                        temporaryPath:recipe.temporaryPath,finalPath:recipe.finalPath),outcome:outcome)
                pairs.append(value)
                for p in paths { guard pairPaths.insert(p).inserted else { throw EraseAllServiceError.invalidAuthority } }
            }
        }
        // Physical unique charge is permitted only after exact role/two-path
        // membership, both streamed SHA/current11 and same-inode proof above.
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
            let sum = byteBound.addingReportingOverflow(Int64(recipe.bytes.count))
            guard !sum.overflow else { throw EraseAllServiceError.invalidAuthority }; byteBound = sum.partialValue
        }
        guard uniqueBytes >= 0, uniqueBytes <= byteBound else { throw EraseAllServiceError.invalidAuthority }
        let scope = OriginalEraseScratchTemporalObservationScopeV1(owner:self,nodes:bindings,pairs:pairs)
        guard activeScope == nil else { throw EraseAllServiceError.invalidAuthority }
        activeScope = scope
        defer { scope.revoke(); activeScope = nil }
        var policies = [String:TemporalPolicyObservationV1]()
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
        for node in raw.nodes.values.sorted(by: { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) })
            where !pairPaths.contains(node.path) && !unaccepted.contains(node.path) {
            guard let binding = bindings[url(node.path)] else { throw EraseAllServiceError.invalidAuthority }
            policies[node.path] = try ProtectedFilePolicyV1.observeOriginalEraseScratchTemporalPolicyWithCheckedClose(
                binding.kind,at:binding.url,fullFact:binding.fullFact,scope:scope,
                retainUncertainDescriptor:{ self.uncertainFDs.append($0); self.poison() })
        }
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
        let second = try rawScan(operations:operations,support:support,publications:recipes,
            outcome: outcome)
        guard Self.sameRaw(raw,second) else { throw EraseAllServiceError.invalidAuthority }
        try admission.observer.requireOriginalScratchOutside(anchor:admission.notificationAfter,
            operationsFact:Self.full(raw.operationsFact),operationsNames:raw.operationsNames,
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
        if let outcome { try requireDelta(outcome,after:result) }
        else if !initialCapture, let current, result != current { throw EraseAllServiceError.invalidAuthority }
        lastRaw = raw; lastPolicyNodes = bindings; lastPairs = pairs
        lastMatchedHeldScope = admission.heldScope
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
                  requested > 0, offset >= 0, offset < recipe.bytes.count,
                  requested <= recipe.bytes.count - offset,
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
                  recipe.finalPath == final, recipe.written == recipe.bytes.count,
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
                      recipe.written == recipe.bytes.count, recipe.acceptedPolicy,
                      recipe.linkID == nil, recipe.replacementID == nil,
                      nodes[source]?.contentSHA256 == recipe.sha256, nodes[final] == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
            } else {
                // The fixed engine's sole overwrite is the checked finalized H
                // staged final. It is not a second mode for an O_EXCL temporary.
                guard source == final + ".finalizing",
                      final.hasPrefix("ProtectedIngressReceiptsV1/"), final.hasSuffix(".prepare.json"),
                      let recipe = publications.values.first(where: { $0.finalPath == source }),
                      !recipe.exclusiveFinalRename, recipe.linkID != nil, recipe.replacementID == nil,
                      recipe.written == recipe.bytes.count, recipe.acceptedPolicy,
                      nodes[recipe.temporaryPath] == nil,
                      nodes[source]?.contentSHA256 == recipe.sha256,
                      let old = nodes[final], old.contentSHA256 != nil,
                      Self.fields(old.fullFact)[5] == "1",
                      let original = retainedSources[final], original.fullFact == old.fullFact,
                      StoreMigrationCanonicalJSONV1.sha256(original.bytes) == old.contentSHA256 else {
                    throw EraseAllServiceError.invalidAuthority
                }
                try admission.requireFinalizedIngressReplacement(intent:intent,
                    originalBytes:original.bytes,stagedBytes:recipe.bytes)
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
        case .synchronize(let path), .lockOwnedDirectory(let path):
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
    private func requireRawDelta(_ outcome: Outcome, after: RawImage) throws {
        try verifyDelta(outcome,operationsFact:Self.full(after.operationsFact),
            operationsNames:after.operationsNames,
            after:after.nodes.mapValues { View(fact:$0.fullFact,sha:$0.sha256,policy:nil) },
            checkPolicies:false)
    }
    private func requireDelta(_ outcome: Outcome, after: Image) throws {
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
        let intent = outcome.intent
        let before = Self.nodes(intent.before).mapValues {
            View(fact:$0.fullFact,sha:$0.contentSHA256,policy:$0.policy)
        }
        var expectedKeys = Set(before.keys)
        var changed = Set<String>()
        var mapped = [String:String]()
        var parentPath: String?
        var parentLinks: Int64 = 0
        var expectedRootNames = intent.before.operationsNames
        func node(_ path: String) throws -> View {
            guard let value = after[path] else { throw EraseAllServiceError.invalidAuthority }; return value
        }
        func parentChanged(_ path: String, links: Int64 = 0) {
            parentPath = Self.parent(path); parentLinks = links
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
            let value = try node(path), f = Self.fields(value.fact)
            guard let createdFD = Int32(exactly:outcome.result),
                  Self.full(try held(createdFD)) == value.fact,
                  f.count == 11, f[5] == "1", f[6] == "0",
                  UInt32(f[2]).map({ $0 & 0o7777 }) == UInt32(mode),
                  value.sha == StoreMigrationCanonicalJSONV1.sha256(Data()),
                  !checkPolicies || value.policy == nil else { throw EraseAllServiceError.invalidAuthority }
        case .writeTemporary(let path, let offset, let requested):
            guard let recipe = publications.values.first(where: { $0.temporaryPath == path }),
                  let count = Int(exactly:outcome.result), count >= 0, count <= requested,
                  offset == recipe.written, count <= recipe.bytes.count - offset,
                  let old = before[path] else { throw EraseAllServiceError.invalidAuthority }
            let value = try node(path), f = Self.fields(value.fact), oldF = Self.fields(old.fact)
            guard Self.stable(old.fact,value.fact), f[5] == oldF[5],
                  Int64(f[6]) == Int64(offset + count),
                  value.sha == StoreMigrationCanonicalJSONV1.sha256(Data(recipe.bytes.prefix(offset + count))),
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
            expectedKeys.remove(path); parentChanged(path,links:-1)
            if Self.parent(path).isEmpty { expectedRootNames.removeAll { $0 == path } }
        case .synchronize, .lockOwnedDirectory, .closeOwnedResource:
            guard outcome.result == 0 else { throw EraseAllServiceError.invalidAuthority }
        }
        guard Set(after.keys) == expectedKeys, operationsNames == expectedRootNames else {
            throw EraseAllServiceError.invalidAuthority
        }
        if let parentPath {
            if parentPath.isEmpty {
                guard Self.directoryMutation(intent.before.operationsFullFact,operationsFact,linkDelta:parentLinks) else {
                    throw EraseAllServiceError.invalidAuthority
                }
            } else {
                guard let a = before[parentPath], let b = after[parentPath],
                      Self.directoryMutation(a.fact,b.fact,linkDelta:parentLinks), b.sha == nil,
                      !checkPolicies || Self.samePolicy(a.policy,b.policy,allowLinkChange:parentLinks != 0) else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        if parentPath?.isEmpty != true {
            guard operationsFact == intent.before.operationsFullFact else { throw EraseAllServiceError.invalidAuthority }
        }
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
    fileprivate let heldScope: OriginalEraseScratchCleanupHeldGScopeV1
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
                  lastMatchedHeldScope === admission.heldScope else {
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
              scope.heldScope === admission.heldScope else {
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
    fileprivate let heldScope: OriginalEraseScratchCleanupHeldGScopeV1
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
            guard lastMatchedHeldScope === admission.heldScope,
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
        guard activeCatalog === session, session.heldScope === admission.heldScope,
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
