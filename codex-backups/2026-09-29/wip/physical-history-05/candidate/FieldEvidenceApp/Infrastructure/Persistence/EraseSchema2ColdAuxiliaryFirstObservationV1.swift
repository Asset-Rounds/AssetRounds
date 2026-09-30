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
    private var initialC16Scope: OriginalEraseC16InitialObservationScopeV1?
    private var firstCaptureC16Scope: OriginalEraseC16FirstCaptureObservationScopeV1?
    private var firstCaptureOperationID: UUID?
    private var firstCaptureSupportURL: URL?
    private var initialSupportURL: URL?

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

    /// Distinct observation-only pre-plan route. The actual Ledger issuer
    /// binds immutable original-P role facts plus current EX/G and source
    /// controls. This never relaxes the ordinary capture/walker predicates.
    func captureFirstWithInitialC16Scope(support: Int32, caches: Int32, temporary: Int32,
        applicationSupportURL: URL, scope: OriginalEraseC16InitialObservationScopeV1) throws -> Snapshot {
        guard !attempted, firstCaptureC16Scope == nil else { throw EraseAllServiceError.invalidAuthority }
        try scope.requireCurrentBinding()
        initialC16Scope = scope; initialSupportURL = applicationSupportURL.standardizedFileURL
        defer { initialC16Scope = nil; initialSupportURL = nil }
        let value = try captureFirst(support: support, caches: caches, temporary: temporary,
            applicationSupportURL: applicationSupportURL)
        try scope.requireCurrentBinding(); return value
    }

    /// Distinct data origin before the auxiliary P exists. Migration's
    /// genuine first-capture owner supplies the complete producer-role scope
    /// under its real EX/G/phase; no immutable-P or proposed plan is asserted.
    func captureFirstWithFirstCaptureScope(support: Int32, caches: Int32, temporary: Int32,
        applicationSupportURL: URL, scope: OriginalEraseC16FirstCaptureObservationScopeV1) throws -> Snapshot {
        guard !attempted else { throw EraseAllServiceError.invalidAuthority }
        return try withFirstCaptureScope(scope: scope, applicationSupportURL: applicationSupportURL) {
            try captureFirst(support: support, caches: caches, temporary: temporary,
                applicationSupportURL: applicationSupportURL)
        }
    }

    /// Re-enter only a genuine fresh first-owner/G callback. The synchronous
    /// body may reprove the retained first image; this helper never captures,
    /// refreshes or changes it and never holds a G scope across an await.
    func withFirstCaptureScope<Value>(scope: OriginalEraseC16FirstCaptureObservationScopeV1,
        applicationSupportURL: URL, _ body: @MainActor () throws -> Value) throws -> Value {
        guard firstCaptureC16Scope == nil, initialC16Scope == nil, applicationSupportURL.isFileURL,
              firstCaptureOperationID == nil || firstCaptureOperationID == scope.operationID,
              firstCaptureSupportURL == nil || firstCaptureSupportURL == applicationSupportURL.standardizedFileURL else {
            throw EraseAllServiceError.invalidAuthority
        }
        try scope.requireCurrentBinding()
        if firstCaptureOperationID == nil {
            firstCaptureOperationID = scope.operationID
            firstCaptureSupportURL = applicationSupportURL.standardizedFileURL
        }
        firstCaptureC16Scope = scope; initialSupportURL = applicationSupportURL.standardizedFileURL
        defer { firstCaptureC16Scope = nil; initialSupportURL = nil }
        let value = try body()
        try scope.requireCurrentBinding(); try io.requireSettled()
        return value
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
            let scopedTree: EraseAbortCheckedSnapshotIOV1.Schema2ColdCurrentTreeV1?
            if (initialC16Scope != nil || firstCaptureC16Scope != nil), let supportURL = initialSupportURL {
                let initialScope = initialC16Scope, captureScope = firstCaptureC16Scope
                scopedTree = try io.schema2ColdCurrentOwnedTree(parent: parent, name: "FieldEvidenceOperations",
                    rootURL: supportURL.appendingPathComponent("FieldEvidenceOperations", isDirectory: true),
                    expectedUser: held.st_uid, expectedGroup: held.st_gid,
                    initialScope: initialScope, firstCaptureScope: captureScope, operationsRelativePrefix: "",
                    requireBinding: { try initialScope?.requireCurrentBinding(); try captureScope?.requireCurrentBinding() },
                    poison: { initialScope?.poisonOnUncertainObservation(); captureScope?.poisonOnUncertainObservation() })
                guard case .present(_, let expectedDigest) = operations,
                      scopedTree?.rootFact == rootFact, scopedTree?.digest == expectedDigest else { throw EraseAllServiceError.invalidAuthority }
            } else { scopedTree = nil }
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
                            try tree(parent: directory, name: name, operationsChild: true) else {
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
                    if let scopedTree {
                        guard let node = scopedTree.nodes.first(where: { $0.path == name }),
                              node.fullFact == Self.fullFact(initial), node.names == nil,
                              node.policy != nil, let sha = node.sha256 else { throw EraseAllServiceError.invalidAuthority }
                        children[name] = .regular(fact: node.fullFact, digest: sha)
                        continue
                    }
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
        if !notificationControl, initialC16Scope != nil || firstCaptureC16Scope != nil {
            let initialScope = initialC16Scope, captureScope = firstCaptureC16Scope
            func bound() throws { try initialScope?.requireCurrentBinding(); try captureScope?.requireCurrentBinding() }
            func poison() { initialScope?.poisonOnUncertainObservation(); captureScope?.poisonOnUncertainObservation() }
            var parent = stat()
            guard Darwin.fstat(operations, &parent) == 0 else { throw EraseAllServiceError.invalidAuthority }
            let one = try io.schema2ColdCurrentOwnedTree(parent: operations, name: name,
                rootURL: rootURL, expectedUser: parent.st_uid, expectedGroup: parent.st_gid,
                initialScope: initialScope, firstCaptureScope: captureScope, operationsRelativePrefix: name,
                requireBinding: bound, poison: poison)
            guard one.rootFact == expectedRootFact, one.digest == expectedTreeDigest else {
                throw EraseAllServiceError.invalidAuthority
            }
            var values: [ControlNode] = []
            for node in one.nodes {
                guard let policy = node.policy else { throw EraseAllServiceError.invalidAuthority }
                values.append(.init(path: node.path, fullFact: node.fullFact, policy: policy,
                    contentSHA256: node.sha256))
            }
            let two = try io.schema2ColdCurrentOwnedTree(parent: operations, name: name,
                rootURL: rootURL, expectedUser: parent.st_uid, expectedGroup: parent.st_gid,
                initialScope: initialScope, firstCaptureScope: captureScope, operationsRelativePrefix: name,
                requireBinding: bound, poison: poison)
            guard one == two else { throw EraseAllServiceError.invalidAuthority }
            return (values, nil)
        }
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

    private func tree(parent: Int32, name: String, operationsChild: Bool = false) throws -> Tree {
        var before = stat()
        let status = Darwin.fstatat(parent, name, &before, AT_SYMLINK_NOFOLLOW)
        if status != 0 {
            guard errno == ENOENT else { throw EraseAllServiceError.invalidAuthority }
            return .absent
        }
        guard before.st_mode & S_IFMT == S_IFDIR else {
            throw EraseAllServiceError.invalidAuthority
        }
        if let supportURL = initialSupportURL,
           (initialC16Scope != nil || firstCaptureC16Scope != nil),
           name == "FieldEvidenceOperations" || operationsChild {
            let initialScope = initialC16Scope, captureScope = firstCaptureC16Scope
            func bound() throws { try initialScope?.requireCurrentBinding(); try captureScope?.requireCurrentBinding() }
            func poison() { initialScope?.poisonOnUncertainObservation(); captureScope?.poisonOnUncertainObservation() }
            let rootURL: URL
            let rolePrefix: String
            if name == "FieldEvidenceOperations" {
                rootURL = supportURL.appendingPathComponent(name, isDirectory: true); rolePrefix = ""
            } else {
                rootURL = supportURL.appendingPathComponent("FieldEvidenceOperations", isDirectory: true)
                    .appendingPathComponent(name, isDirectory: true); rolePrefix = name
            }
            let parentFact = try directoryFact(parent)
            let value = try io.schema2ColdCurrentOwnedTree(parent: parent, name: name, rootURL: rootURL,
                expectedUser: parentFact.st_uid, expectedGroup: parentFact.st_gid,
                initialScope: initialScope, firstCaptureScope: captureScope, operationsRelativePrefix: rolePrefix,
                requireBinding: bound, poison: poison)
            guard value.rootFact == Self.fullFact(before) else { throw EraseAllServiceError.invalidAuthority }
            return .present(rootFact: value.rootFact, digest: value.digest)
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

/// A receipt is minted only by the retained physical owner after its one
/// declared unlink (or positively original-absent no-effect), sync, complete
/// postimage and every checked close. It is data for the Router's next CAS.
@MainActor
final class EraseSchema2ColdPhysicalEffectReceiptV1 {
    enum Effect: Equatable { case unlinked, originallyAbsent, resumedPreparingAbsence }
    let ownerID: UUID
    let originalPAuxiliaryRosterSHA256: String
    let planSHA256: String
    let progressSHA256: String
    let targetIndex: Int
    let target: EraseSchema2ColdCleanupProgressV1.Target
    let effect: Effect
    let before: [EraseSchema2ColdCleanupProgressV1.Projection]
    let after: [EraseSchema2ColdCleanupProgressV1.Projection]
    fileprivate init(owner: EraseSchema2ColdPhysicalCleanupOwnerV1,
        progressSHA256: String, targetIndex: Int,
        target: EraseSchema2ColdCleanupProgressV1.Target, effect: Effect,
        before: [EraseSchema2ColdCleanupProgressV1.Projection],
        after: [EraseSchema2ColdCleanupProgressV1.Projection]) {
        ownerID = owner.ownerID; originalPAuxiliaryRosterSHA256 = owner.originalP.canonicalSHA256
        planSHA256 = owner.planSHA256; self.progressSHA256 = progressSHA256
        self.targetIndex = targetIndex; self.target = target; self.effect = effect
        self.before = before; self.after = after
    }
    func requireBound(owner: EraseSchema2ColdPhysicalCleanupOwnerV1,
        progress: EraseSchema2ColdCleanupProgressV1) throws {
        try owner.requireReceipt(self, progress: progress)
    }
}

/// Complete auxiliary namespace witness and one-effect postorder executor.
/// This owner owns only its transient checked IO; all three root descriptors
/// are lent by the actual cold/original operation, never closed or duplicated
/// into an independent EX owner here. Router's private permit is indispensable
/// at every boundary and authenticates current Store, Registry, Search,
/// Notification and retirement receipts. Neither a snapshot nor this class
/// can create EX/G, an OS result, a source receipt or a retirement proof.
@MainActor
final class EraseSchema2ColdPhysicalCleanupOwnerV1 {
    typealias Progress = EraseSchema2ColdCleanupProgressV1
    typealias Node = EraseAbortCheckedSnapshotIOV1.Schema2ColdCurrentTreeV1.Node
    fileprivate let ownerID = UUID()
    fileprivate let originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1
    fileprivate let planSHA256: String
    private let plan: OriginalEraseC16PlanV1
    private let originalPairAccounting: EraseSchema2ColdOriginalPairAccountingRosterV1?
    private let initial: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot
    private let supportURL: URL, cachesURL: URL, temporaryURL: URL
    private let targets: [Progress.Target]
    private let targetsSHA256: String
    private let io = EraseAbortCheckedSnapshotIOV1()
    private var closed = false, closeAttempted = false, uncertain = false
    private var inFlight = false
    private var lastEffect: EraseSchema2ColdPhysicalEffectReceiptV1?
    private var attemptedTargetIndices = Set<Int>()

    private struct Image: Equatable {
        let projection: [Progress.Projection]
        let nodes: [String: Node]
        let supportNames: [String]
    }

    init(originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
        initial: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        applicationSupportURL: URL, cachesURL: URL, temporaryURL: URL,
        fixedTargets: [Progress.Target], c16Plan: OriginalEraseC16PlanV1,
        targetGenerationID: UUID, planSHA256: String,
        originalPairAccounting: EraseSchema2ColdOriginalPairAccountingRosterV1? = nil) throws {
        try c16Plan.validate()
        guard applicationSupportURL.isFileURL, cachesURL.isFileURL, temporaryURL.isFileURL,
              originalP.canonicalBytes == (try StoreMigrationCanonicalJSONV1.encode(originalP.record)),
              originalP.canonicalSHA256 == StoreMigrationCanonicalJSONV1.sha256(originalP.canonicalBytes),
              planSHA256 == (try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(c16Plan))) else { throw EraseAllServiceError.invalidAuthority }
        let c16 = fixedTargets.filter { $0.kind == .c16 }
        guard c16.count == c16Plan.steps.count,
              c16.map(\.ordinal) == Array(c16Plan.steps.indices),
              fixedTargets.filter({ $0.kind != .c16 }) == (try Self.fixedNonC16Targets(originalP: originalP, c16Plan: c16Plan, targetGenerationID: targetGenerationID, originalPairAccounting: originalPairAccounting)),
              Int64(initial.supportIdentity.device) == originalP.record.supportDevice,
              UInt64(initial.supportIdentity.inode) == originalP.record.supportInode,
              UInt32(initial.supportIdentity.mode) == originalP.record.supportMode,
              UInt32(initial.supportIdentity.user) == originalP.record.supportUser,
              UInt32(initial.supportIdentity.group) == originalP.record.supportGroup,
              Int64(initial.cacheIdentity.device) == originalP.record.cachesDevice,
              UInt64(initial.cacheIdentity.inode) == originalP.record.cachesInode,
              UInt32(initial.cacheIdentity.mode) == originalP.record.cachesMode,
              UInt32(initial.cacheIdentity.user) == originalP.record.cachesUser,
              UInt32(initial.cacheIdentity.group) == originalP.record.cachesGroup,
              Int64(initial.temporaryIdentity.device) == originalP.record.temporaryDevice,
              UInt64(initial.temporaryIdentity.inode) == originalP.record.temporaryInode,
              UInt32(initial.temporaryIdentity.mode) == originalP.record.temporaryMode,
              UInt32(initial.temporaryIdentity.user) == originalP.record.temporaryUser,
              UInt32(initial.temporaryIdentity.group) == originalP.record.temporaryGroup else {
            throw EraseAllServiceError.invalidAuthority
        }
        for (ordinal, target) in c16.enumerated() {
            guard target.semanticSHA256 == (try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(c16Plan.steps[ordinal]))) else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        self.originalP = originalP; self.initial = initial; self.plan = c16Plan
        self.originalPairAccounting = originalPairAccounting
        self.planSHA256 = planSHA256; targets = fixedTargets
        targetsSHA256 = StoreMigrationCanonicalJSONV1.sha256(try StoreMigrationCanonicalJSONV1.encode(fixedTargets))
        supportURL = applicationSupportURL.standardizedFileURL
        self.cachesURL = cachesURL.standardizedFileURL; self.temporaryURL = temporaryURL.standardizedFileURL
    }

    /// These are the immutable roster's nine domains, in its wire order.
    /// The three named parents are projection roles, never additional trees.
    static let recordedRootKeys = [
        "support/FieldEvidenceRestore", "support/FieldEvidenceCommerce",
        "support/FieldEvidenceDiagnostics", "support/LocalSearchIndexV1",
        "support/PortableReviewExchangeV2", "support/local-jobs-v1",
        "support/FieldEvidenceOperations", "caches/FieldEvidenceApp",
        "temporary/FieldEvidenceApp"
    ]
    struct RecordedRootCensusV1: Codable, Equatable {
        let key: String
        let originalNodeCount: Int
        let originalRegularBytes: Int64
        let genericTargetCount: Int
    }
    private static func relativePath(_ path: String, root: String) throws -> String {
        guard path == root || path.hasPrefix(root + "/") else {
            throw EraseAllServiceError.invalidAuthority
        }
        let relative = path == root ? "" : String(path.dropFirst(root.count + 1))
        if !relative.isEmpty {
            let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        return relative
    }
    private static func requireOriginalRootCensus(_ originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
        originalPairAccounting: EraseSchema2ColdOriginalPairAccountingRosterV1? = nil) throws -> [(Int, Int64)] {
        guard originalP.canonicalBytes == (try StoreMigrationCanonicalJSONV1.encode(originalP.record)),
              originalP.canonicalSHA256 == StoreMigrationCanonicalJSONV1.sha256(originalP.canonicalBytes),
              originalP.record.trees.map(\.key) == recordedRootKeys else {
            throw EraseAllServiceError.invalidAuthority
        }
        try originalPairAccounting?.requireOriginalPBinding(originalPAuxiliaryRosterSHA256: originalP.canonicalSHA256)
        var typedPairByPath: [String: EraseAbortCheckedSnapshotIOV1.Schema2ColdAuthenticatedPairObservationV1] = [:]
        for pair in originalPairAccounting?.pairs ?? [] {
            guard pair.operationsRelativeMemberPaths.count == 2, pair.observedFacts.count == 2,
                  pair.observedFacts[0] == pair.observedFacts[1], pair.byteCount >= 0,
                  pair.byteCount <= 1_073_741_824,
                  StoreMigrationCanonicalJSONV1.isLowercaseSHA256(pair.sha256) else { throw EraseAllServiceError.invalidAuthority }
            for path in pair.operationsRelativeMemberPaths {
                guard typedPairByPath.updateValue(pair, forKey: "support/FieldEvidenceOperations/" + path) == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        return try originalP.record.trees.map { tree in
            if tree.state == "absent" {
                guard tree.rootFact == nil, tree.digest == nil, tree.nodes == nil, tree.deletionOrder == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
                return (0, 0)
            }
            guard tree.state == "present", let nodes = tree.nodes, !nodes.isEmpty,
                  nodes.count < 100_000, nodes.first?.path == "", nodes.first?.kind == "directory",
                  let rootFact = tree.rootFact, let digest = tree.digest,
                  StoreMigrationCanonicalJSONV1.isLowercaseSHA256(digest),
                  nodes.map(\.path) == nodes.map(\.path).sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }),
                  Set(nodes.map(\.path)).count == nodes.count,
                  let order = tree.deletionOrder, Set(order) == Set(nodes.map(\.path)), order.count == nodes.count,
                  try nine(rootFact) == nodes[0].fact else { throw EraseAllServiceError.invalidAuthority }
            let byPath = Dictionary(uniqueKeysWithValues: nodes.map { ($0.path, $0) })
            var directChildren: [String: [String]] = [:]
            for node in nodes where !node.path.isEmpty {
                let qualified = tree.key + "/" + node.path
                let relative = try relativePath(qualified, root: tree.key)
                let parts = relative.split(separator: "/").map(String.init)
                guard let child = parts.last else { throw EraseAllServiceError.invalidAuthority }
                directChildren[parts.dropLast().joined(separator: "/"), default: []].append(child)
            }
            var bytes: Int64 = 0
            var chargedTypedPairs = Set<String>()
            for node in nodes {
                let qualified = node.path.isEmpty ? tree.key : tree.key + "/" + node.path
                let relative = try relativePath(qualified, root: tree.key)
                let parts = relative.isEmpty ? [] : relative.split(separator: "/").map(String.init)
                let f = try fields(node.fact, count: 9)
                guard let mode = UInt32(f[2]), parts.count <= (node.kind == "directory" ? 64 : 65),
                      relative.isEmpty || byPath[parts.dropLast().joined(separator: "/")]?.kind == "directory" else {
                    throw EraseAllServiceError.invalidAuthority
                }
                if node.kind == "directory" {
                    guard mode & UInt32(S_IFMT) == UInt32(S_IFDIR), node.sha256 == nil,
                          let members = node.members, members == members.sorted(),
                          Set(members).count == members.count else { throw EraseAllServiceError.invalidAuthority }
                    guard members == (directChildren[relative] ?? []).sorted() else { throw EraseAllServiceError.invalidAuthority }
                } else {
                    guard node.kind == "file", mode & UInt32(S_IFMT) == UInt32(S_IFREG),
                          node.members == nil, let sha = node.sha256,
                          StoreMigrationCanonicalJSONV1.isLowercaseSHA256(sha),
                          let size = Int64(f[4]), size <= 1_073_741_824, let links = UInt64(f[3]) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    if let pair = typedPairByPath[qualified] {
                        guard links == 2, pair.observedFacts.contains(node.fact), pair.sha256 == sha,
                              pair.byteCount == size, pair.device == UInt64(f[0]), pair.inode == UInt64(f[1]),
                              pair.operationsRelativeMemberPaths.allSatisfy({ member in
                                  byPath[member]?.fact == node.fact && byPath[member]?.sha256 == sha
                              }) else { throw EraseAllServiceError.invalidAuthority }
                        let key = String(pair.device) + "|" + String(pair.inode)
                        if chargedTypedPairs.insert(key).inserted {
                            guard bytes <= 1_073_741_824 - size else { throw EraseAllServiceError.invalidAuthority }
                            bytes += size
                        }
                    } else {
                        guard links == 1, bytes <= 1_073_741_824 - size else { throw EraseAllServiceError.invalidAuthority }
                        bytes += size
                    }
                }
            }
            let expectedOrder = nodes.map(\.path).sorted { lhs, rhs in
                let left = lhs.isEmpty ? 0 : lhs.split(separator: "/").count
                let right = rhs.isEmpty ? 0 : rhs.split(separator: "/").count
                return left == right ? lhs.utf8.lexicographicallyPrecedes(rhs.utf8) : left > right
            }
            guard order == expectedOrder else { throw EraseAllServiceError.invalidAuthority }
            return (nodes.count, bytes)
        }
    }
    /// Pure source data for losslessly segmented controls. The logical mixed
    /// stream is C16's independently bounded steps plus these exact counts;
    /// no global node limit narrows the nine admitted original trees.
    static func fixedRootCensus(originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
        c16Plan: OriginalEraseC16PlanV1, targetGenerationID: UUID,
        originalPairAccounting: EraseSchema2ColdOriginalPairAccountingRosterV1? = nil) throws -> [RecordedRootCensusV1] {
        let original = try requireOriginalRootCensus(originalP, originalPairAccounting: originalPairAccounting)
        let generic = try fixedNonC16Targets(originalP: originalP, c16Plan: c16Plan, targetGenerationID: targetGenerationID, originalPairAccounting: originalPairAccounting)
        return recordedRootKeys.enumerated().map { index, key in
            RecordedRootCensusV1(key: key, originalNodeCount: original[index].0,
                originalRegularBytes: original[index].1,
                genericTargetCount: generic.filter { $0.path == key || $0.path.hasPrefix(key + "/") }.count)
        }
    }
    /// This is a grammar/bounds check of actual data, never an EX, source,
    /// policy, OS, birth or current-progress receipt. Those remain mandatory
    /// in the enclosing retained scope and physical permit at every IO.
    static func requireRecordedProjectionCensus(originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
        projection: [Progress.Projection], originalPairAccounting: EraseSchema2ColdOriginalPairAccountingRosterV1? = nil,
        currentTypedPairs: [EraseAbortCheckedSnapshotIOV1.Schema2ColdAuthenticatedPairObservationV1] = []) throws {
        _ = try requireOriginalRootCensus(originalP, originalPairAccounting: originalPairAccounting)
        try requireCurrentProjectionBounds(originalP: originalP, projection: projection, currentTypedPairs: currentTypedPairs)
    }
    private static func requireCurrentProjectionBounds(originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
        projection: [Progress.Projection],
        currentTypedPairs: [EraseAbortCheckedSnapshotIOV1.Schema2ColdAuthenticatedPairObservationV1]) throws {
        // The retained owner's initializer already validates its immutable P.
        // Rechecking this actual image never caches a scope/permit decision.
        guard projection.map(\.path) == projection.map(\.path).sorted(),
              Set(projection.map(\.path)).count == projection.count else { throw EraseAllServiceError.invalidAuthority }
        let parents = ["support", "caches", "temporary"]
        let byPath = Dictionary(uniqueKeysWithValues: projection.map { ($0.path, $0) })
        for (index, parent) in parents.enumerated() {
            guard let node = byPath[parent], node.sha256 == nil else { throw EraseAllServiceError.invalidAuthority }
            let f = try fields(node.fullFact)
            let expected: (Int64, UInt64, UInt32, UInt32, UInt32)
            switch index {
            case 0: expected = (originalP.record.supportDevice, originalP.record.supportInode, originalP.record.supportMode, originalP.record.supportUser, originalP.record.supportGroup)
            case 1: expected = (originalP.record.cachesDevice, originalP.record.cachesInode, originalP.record.cachesMode, originalP.record.cachesUser, originalP.record.cachesGroup)
            default: expected = (originalP.record.temporaryDevice, originalP.record.temporaryInode, originalP.record.temporaryMode, originalP.record.temporaryUser, originalP.record.temporaryGroup)
            }
            guard Int64(f[0]) == expected.0, UInt64(f[1]) == expected.1, UInt32(f[2]) == expected.2,
                  UInt32(f[3]) == expected.3, UInt32(f[4]) == expected.4,
                  expected.2 & UInt32(S_IFMT) == UInt32(S_IFDIR) else { throw EraseAllServiceError.invalidAuthority }
        }
        guard projection.allSatisfy({ item in parents.contains(item.path)
            || recordedRootKeys.contains(where: { item.path == $0 || item.path.hasPrefix($0 + "/") }) }) else {
            throw EraseAllServiceError.invalidAuthority
        }
        var typedPairByPath: [String: EraseAbortCheckedSnapshotIOV1.Schema2ColdAuthenticatedPairObservationV1] = [:]
        for pair in currentTypedPairs {
            guard pair.operationsRelativeMemberPaths.count == 2, pair.fullFacts.count == 2,
                  pair.fullFacts[0] == pair.fullFacts[1], pair.byteCount >= 0, pair.byteCount <= 1_073_741_824 else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (index, path) in pair.operationsRelativeMemberPaths.enumerated() {
                let qualified = "support/FieldEvidenceOperations/" + path
                guard typedPairByPath.updateValue(pair, forKey: qualified) == nil,
                      byPath[qualified]?.fullFact == pair.fullFacts[index], byPath[qualified]?.sha256 == pair.sha256 else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
        for root in recordedRootKeys {
            let nodes = projection.filter { $0.path == root || $0.path.hasPrefix(root + "/") }
            guard nodes.count <= 100_000 else { throw EraseAllServiceError.invalidAuthority }
            if nodes.isEmpty { continue }
            guard let rootNode = byPath[root], rootNode.sha256 == nil,
                  let parent = byPath[String(root.split(separator: "/").first!) ] else { throw EraseAllServiceError.invalidAuthority }
            let parentFields = try fields(parent.fullFact)
            var bytes: Int64 = 0
            var chargedTypedPairs = Set<String>()
            for node in nodes {
                let relative = try relativePath(node.path, root: root)
                let parts = relative.isEmpty ? [] : relative.split(separator: "/").map(String.init)
                let f = try fields(node.fullFact)
                guard let mode = UInt32(f[2]), f[0] == parentFields[0], f[3] == parentFields[3], f[4] == parentFields[4] else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let directory = mode & UInt32(S_IFMT) == UInt32(S_IFDIR)
                guard parts.count <= (directory ? 64 : 65), mode & 0o7777 == (directory ? 0o700 : 0o600) else {
                    throw EraseAllServiceError.invalidAuthority
                }
                if !relative.isEmpty {
                    let parentPath = parts.count == 1 ? root : root + "/" + parts.dropLast().joined(separator: "/")
                    guard let enclosing = byPath[parentPath] else { throw EraseAllServiceError.invalidAuthority }
                    let enclosingFields = try fields(enclosing.fullFact)
                    guard let enclosingMode = UInt32(enclosingFields[2]),
                          enclosingMode & UInt32(S_IFMT) == UInt32(S_IFDIR) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
                if directory {
                    guard node.sha256 == nil else { throw EraseAllServiceError.invalidAuthority }
                } else {
                    guard mode & UInt32(S_IFMT) == UInt32(S_IFREG), let sha = node.sha256,
                          StoreMigrationCanonicalJSONV1.isLowercaseSHA256(sha),
                          let size = Int64(f[6]), size <= 1_073_741_824, let links = UInt64(f[5]) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    if let pair = typedPairByPath[node.path] {
                        guard links == 2, pair.byteCount == size, pair.sha256 == sha,
                              pair.device == UInt64(f[0]), pair.inode == UInt64(f[1]) else { throw EraseAllServiceError.invalidAuthority }
                        let key = String(pair.device) + "|" + String(pair.inode)
                        if chargedTypedPairs.insert(key).inserted {
                            guard bytes <= 1_073_741_824 - size else { throw EraseAllServiceError.invalidAuthority }
                            bytes += size
                        }
                    } else {
                        guard links == 1, bytes <= 1_073_741_824 - size else { throw EraseAllServiceError.invalidAuthority }
                        bytes += size
                    }
                }
            }
        }
    }

    /// Construct once from the immutable original record and canonical plan.
    /// No surviving Q/R name is enumerated to mint another target. Prospective
    /// Search/Notification leaves are fixed owner-produced names; their actual
    /// presence/content/absence still requires the respective typed receipt.
    static func fixedNonC16Targets(originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
        c16Plan: OriginalEraseC16PlanV1, targetGenerationID: UUID,
        originalPairAccounting: EraseSchema2ColdOriginalPairAccountingRosterV1? = nil) throws -> [Progress.Target] {
        try c16Plan.validate()
        var result: [Progress.Target] = []
        func add(_ kind: Progress.Target.Kind, _ path: String,
            source: EraseSchema2ColdAuxiliaryPhysicalRosterV1.Node?) throws {
            struct Binding: Codable { let rosterSHA256: String; let path: String; let source: EraseSchema2ColdAuxiliaryPhysicalRosterV1.Node? }
            let bytes = try StoreMigrationCanonicalJSONV1.encode(Binding(
                rosterSHA256: originalP.canonicalSHA256, path: path, source: source))
            result.append(.init(kind: kind, ordinal: result.count, path: path,
                semanticSHA256: StoreMigrationCanonicalJSONV1.sha256(bytes),
                dependencyPaths: [], allowedBirthPaths: []))
        }
        _ = try requireOriginalRootCensus(originalP, originalPairAccounting: originalPairAccounting)
        let operationsKey = "support/FieldEvidenceOperations"
        guard let operations = originalP.record.trees.first(where: { $0.key == operationsKey }) else {
            throw EraseAllServiceError.invalidAuthority
        }
        let ownNames = Set(c16Plan.ownedLeaseNames)
        let operationsNodes = Dictionary(uniqueKeysWithValues: (operations.nodes ?? []).map { ($0.path, $0) })
        let scratchPrefix = "ScratchDataV1/"
        for path in operations.deletionOrder ?? [] where path.hasPrefix(scratchPrefix) {
            let suffix = String(path.dropFirst(scratchPrefix.count))
            guard let rootName = suffix.split(separator: "/").first else { throw EraseAllServiceError.invalidAuthority }
            if ownNames.contains(String(rootName)) { continue }
            let isLease = operationsNodes[scratchPrefix + String(rootName)]?.kind == "directory"
            try add(isLease ? .scratchLease : .scratchOrphan, operationsKey + "/" + path, source: operationsNodes[path])
        }
        for tree in originalP.record.trees where tree.key != operationsKey {
            let nodes = Dictionary(uniqueKeysWithValues: (tree.nodes ?? []).map { ($0.path, $0) })
            var order = tree.deletionOrder ?? [""]
            if tree.key == "support/" + LocalSearchIndexStoreV1.directoryName,
               !order.contains(LocalSearchIndexStoreV1.fileName) {
                order.insert(LocalSearchIndexStoreV1.fileName, at: max(0, order.count - 1))
            }
            for path in order {
                try add(path.isEmpty ? .auxiliaryRoot : .auxiliaryNode,
                    path.isEmpty ? tree.key : tree.key + "/" + path, source: nodes[path])
            }
        }
        // C16 has already consumed its semantic descendants. Registry's
        // actual drain consumes owner-token descendants. Notification's
        // authentic removal consumes its obsolete mapping/record leaves.
        let excluded = ["ScratchDataV1/", "ProtectedIngressReceiptsV1/", "generation-leases/",
            AppLockNotificationControlStoreV1.rootName + "/"]
        for path in operations.deletionOrder ?? [] where !path.isEmpty {
            if excluded.contains(where: { path.hasPrefix($0) }) { continue }
            if path == "schema-migration/manifest-" + targetGenerationID.uuidString.lowercased() + ".json" { continue }
            if path == AppLockNotificationControlStoreV1.rootName {
                try add(.auxiliaryNode, operationsKey + "/" + path + "/" + AppLockNotificationControlStoreV1.eraseName, source: nil)
            }
            try add(.auxiliaryNode, operationsKey + "/" + path, source: operationsNodes[path])
        }
        if operationsNodes[AppLockNotificationControlStoreV1.rootName] == nil {
            try add(.auxiliaryNode, operationsKey + "/" + AppLockNotificationControlStoreV1.rootName + "/" + AppLockNotificationControlStoreV1.eraseName, source: nil)
            try add(.auxiliaryNode, operationsKey + "/" + AppLockNotificationControlStoreV1.rootName, source: nil)
        }
        try add(.auxiliaryRoot, operationsKey, source: operationsNodes[""])
        guard Set(result.map(\.path)).count == result.count else {
            throw EraseAllServiceError.invalidAuthority
        }
        return result
    }

    private func requireMemory() throws {
        guard !closed, !closeAttempted, !uncertain else { throw EraseAllServiceError.invalidAuthority }
        try io.requireSettled()
    }
    private func requireBinding(_ permit: EraseSchema2ColdPhysicalPermitV1,
        progress: Progress) throws {
        try requireMemory()
        guard progress.originalPAuxiliaryRosterSHA256 == originalP.canonicalSHA256,
              progress.targets == targets, progress.eraseID == originalP.record.eraseID,
              progress.completedPrefixCount >= 0, progress.completedPrefixCount <= targets.count else {
            throw EraseAllServiceError.invalidAuthority
        }
        try permit.requireBinding(originalPAuxiliaryRosterSHA256: originalP.canonicalSHA256,
            planSHA256: planSHA256,
            progressSHA256: StoreMigrationCanonicalJSONV1.sha256(try StoreMigrationCanonicalJSONV1.encode(progress)),
            mixedTargetIndex: progress.activeTargetIndex)
    }
    private static func fact(_ f: stat) -> String {
        [String(f.st_dev), String(f.st_ino), String(f.st_mode), String(f.st_uid), String(f.st_gid),
         String(f.st_nlink), String(f.st_size), String(f.st_mtimespec.tv_sec), String(f.st_mtimespec.tv_nsec),
         String(f.st_ctimespec.tv_sec), String(f.st_ctimespec.tv_nsec)].joined(separator: "|")
    }
    private static func fields(_ fact: String, count: Int = 11) throws -> [String] {
        let values = fact.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard values.count == count, count == 9 || count == 11,
              let device = Int64(values[0]), device >= 0,
              let inode = UInt64(values[1]), inode > 0,
              let mode = UInt32(values[2]), mode > 0 else { throw EraseAllServiceError.invalidAuthority }
        let linkIndex = count == 11 ? 5 : 3, sizeIndex = count == 11 ? 6 : 4
        let modifiedIndex = count == 11 ? 7 : 5, changedIndex = count == 11 ? 9 : 7
        guard let links = UInt64(values[linkIndex]), links > 0,
              let size = Int64(values[sizeIndex]), size >= 0,
              Int64(values[modifiedIndex]) != nil, Int64(values[changedIndex]) != nil,
              let modifiedNanos = Int64(values[modifiedIndex + 1]), (0..<1_000_000_000).contains(modifiedNanos),
              let changedNanos = Int64(values[changedIndex + 1]), (0..<1_000_000_000).contains(changedNanos),
              count != 11 || (UInt32(values[3]) != nil && UInt32(values[4]) != nil) else {
            throw EraseAllServiceError.invalidAuthority
        }
        return values
    }
    private static func nine(_ full: String) throws -> String {
        let f = try fields(full); return [f[0],f[1],f[2],f[5],f[6],f[7],f[8],f[9],f[10]].joined(separator: "|")
    }
    private static func stable(_ actual: String, _ expected: String) throws -> Bool {
        Array(try fields(actual).prefix(5)) == Array(try fields(expected).prefix(5))
    }
    private func external(_ path: String) -> Bool {
        path == "support/" + LocalSearchIndexStoreV1.directoryName || path.hasPrefix("support/" + LocalSearchIndexStoreV1.directoryName + "/")
            || path == "support/FieldEvidenceOperations/generation-leases" || path.hasPrefix("support/FieldEvidenceOperations/generation-leases/")
            || path == "support/FieldEvidenceOperations/schema-migration" || path.hasPrefix("support/FieldEvidenceOperations/schema-migration/")
            || path == "support/FieldEvidenceOperations/" + AppLockNotificationControlStoreV1.rootName
            || path.hasPrefix("support/FieldEvidenceOperations/" + AppLockNotificationControlStoreV1.rootName + "/")
    }
    private func c16(_ path: String) -> Bool {
        ["ScratchDataV1", "ProtectedIngressReceiptsV1"].contains { name in
            path == "support/FieldEvidenceOperations/" + name || path.hasPrefix("support/FieldEvidenceOperations/" + name + "/")
        }
    }

    private func requireScanBinding(_ permit: EraseSchema2ColdPhysicalPermitV1,
        progress: Progress?) throws {
        if let progress { try requireBinding(permit, progress: progress) }
        else {
            try requireMemory()
            try permit.requireBootstrapBinding(originalPAuxiliaryRosterSHA256: originalP.canonicalSHA256,
                planSHA256: planSHA256,
                targetsSHA256: targetsSHA256)
        }
    }

    private func scan(support: Int32, caches: Int32, temporary: Int32,
        c16Scope: OriginalEraseC16CurrentObservationScopeV1?, permit: EraseSchema2ColdPhysicalPermitV1,
        progress: Progress?, initialScope: OriginalEraseC16InitialObservationScopeV1? = nil) throws -> Image {
        guard initialScope == nil || (progress == nil && c16Scope == nil) else { throw EraseAllServiceError.invalidAuthority }
        try requireScanBinding(permit, progress: progress)
        let canonicalProgressSHA = try progress.map { StoreMigrationCanonicalJSONV1.sha256(try StoreMigrationCanonicalJSONV1.encode($0)) }
        func bound() throws {
            try requireMemory()
            if let progress, let canonicalProgressSHA {
                try permit.requireBinding(originalPAuxiliaryRosterSHA256: originalP.canonicalSHA256,
                    planSHA256: planSHA256, progressSHA256: canonicalProgressSHA,
                    mixedTargetIndex: progress.activeTargetIndex)
            } else {
                try permit.requireBootstrapBinding(originalPAuxiliaryRosterSHA256: originalP.canonicalSHA256,
                    planSHA256: planSHA256, targetsSHA256: targetsSHA256)
            }
        }
        var values: [Progress.Projection] = [], nodes: [String: Node] = [:]
        var currentTypedPairs: [EraseAbortCheckedSnapshotIOV1.Schema2ColdAuthenticatedPairObservationV1] = []
        let parents: [(String,Int32,URL,Int64,UInt64,UInt32,UInt32,UInt32)] = [
            ("support", support, supportURL, originalP.record.supportDevice, originalP.record.supportInode,
                originalP.record.supportMode, originalP.record.supportUser, originalP.record.supportGroup),
            ("caches", caches, cachesURL, originalP.record.cachesDevice, originalP.record.cachesInode,
                originalP.record.cachesMode, originalP.record.cachesUser, originalP.record.cachesGroup),
            ("temporary", temporary, temporaryURL, originalP.record.temporaryDevice, originalP.record.temporaryInode,
                originalP.record.temporaryMode, originalP.record.temporaryUser, originalP.record.temporaryGroup)]
        func poison() { self.uncertain = true; permit.poisonOnUncertainEffect() }
        var parentFacts: [String: String] = [:]
        for (key, fd, _, dev, ino, mode, user, group) in parents {
            try bound()
            var held = stat()
            guard Darwin.fstat(fd, &held) == 0, Int64(held.st_dev) == dev,
                  UInt64(held.st_ino) == ino, UInt32(held.st_mode) == mode,
                  UInt32(held.st_uid) == user, UInt32(held.st_gid) == group,
                  held.st_uid == Darwin.geteuid(), held.st_mode & S_IFMT == S_IFDIR else {
                throw EraseAllServiceError.invalidAuthority
            }
            parentFacts[key] = Self.fact(held)
            values.append(.init(path: key, fullFact: Self.fact(held), sha256: nil))
        }
        let supportNames = try io.schema2ColdNames(in: support, requireBinding: bound, poison: poison)
        let assigned = Set(originalP.record.trees.filter { $0.key.hasPrefix("support/") }
            .map { String($0.key.dropFirst("support/".count)) }).union(["FieldEvidenceData", "FieldEvidenceErase"])
        guard Set(supportNames).isSubset(of: assigned), Set(supportNames).isSuperset(of: ["FieldEvidenceData", "FieldEvidenceErase"]) else {
            throw EraseAllServiceError.invalidAuthority
        }
        for tree in originalP.record.trees {
            let parts = tree.key.split(separator: "/").map(String.init)
            guard parts.count == 2, let parent = parents.first(where: { $0.0 == parts[0] }) else {
                throw EraseAllServiceError.invalidAuthority
            }
            try bound()
            var named = stat()
            let status = Darwin.fstatat(parent.1, parts[1], &named, AT_SYMLINK_NOFOLLOW)
            let namedError = errno
            try bound()
            if status != 0 {
                guard namedError == ENOENT else { throw EraseAllServiceError.invalidAuthority }
                continue
            }
            let isOperations = tree.key == "support/FieldEvidenceOperations"
            let observed = try io.schema2ColdCurrentOwnedTree(parent: parent.1, name: parts[1],
                rootURL: parent.2.appendingPathComponent(parts[1], isDirectory: true),
                expectedUser: uid_t(parent.6), expectedGroup: gid_t(parent.7),
                scope: isOperations ? c16Scope : nil,
                initialScope: isOperations ? initialScope : nil,
                operationsRelativePrefix: isOperations && (c16Scope != nil || initialScope != nil) ? "" : nil,
                requireBinding: bound,
                poison: { self.uncertain = true; permit.poisonOnUncertainEffect() })
            if isOperations { currentTypedPairs.append(contentsOf: observed.typedPairs) }
            for node in observed.nodes {
                let path = node.path.isEmpty ? tree.key : tree.key + "/" + node.path
                guard nodes.updateValue(node, forKey: path) == nil else { throw EraseAllServiceError.invalidAuthority }
                values.append(.init(path: path, fullFact: node.fullFact, sha256: node.sha256))
            }
        }
        guard try io.schema2ColdNames(in: support, requireBinding: bound, poison: poison) == supportNames else { throw EraseAllServiceError.invalidAuthority }
        for (key, fd, _, _, _, _, _, _) in parents {
            try bound()
            var held = stat()
            guard Darwin.fstat(fd, &held) == 0,
                  Self.fact(held) == parentFacts[key] else { throw EraseAllServiceError.invalidAuthority }
        }
        try bound()
        let projection = values.sorted { $0.path < $1.path }
        guard Set(projection.map(\.path)).count == projection.count else { throw EraseAllServiceError.invalidAuthority }
        // Data/Erase descendants are the actual generation/Store owners'
        // independent typed domains. Parent identities and closed child names
        // are checked here; no self-containing Store leaf digest is invented.
        try Self.requireCurrentProjectionBounds(originalP: originalP, projection: projection, currentTypedPairs: currentTypedPairs)
        try permit.requireExternalBranches(projection)
        return Image(projection: projection, nodes: nodes, supportNames: supportNames)
    }

    private func originalNodes() -> [String: EraseSchema2ColdAuxiliaryPhysicalRosterV1.Node] {
        Dictionary(uniqueKeysWithValues: originalP.record.trees.flatMap { tree in
            (tree.nodes ?? []).map { (node: EraseSchema2ColdAuxiliaryPhysicalRosterV1.Node) in
                (node.path.isEmpty ? tree.key : tree.key + "/" + node.path, node)
            }
        })
    }
    private func currentCutDeleted(_ image: Image, progress: Progress) throws -> Set<String> {
        var removed = Set(targets.prefix(progress.completedPrefixCount).filter { $0.kind != .c16 }.map(\.path))
        if let index = progress.activeTargetIndex, targets.indices.contains(index), targets[index].kind != .c16,
           image.nodes[targets[index].path] == nil {
            guard index == progress.completedPrefixCount,
                  progress.stage == .preparing || progress.stage == .preparingCaptured else {
                throw EraseAllServiceError.invalidAuthority
            }
            removed.insert(targets[index].path)
        }
        return removed
    }
    private func requireFinite(_ image: Image, boundary: OriginalEraseC16BoundaryObservationV1?,
        progress: Progress) throws {
        let original = originalNodes(), deleted = try currentCutDeleted(image, progress: progress)
        let originalInodes = Dictionary(grouping: original.filter { $0.value.kind == "file" }, by: { entry in
            entry.value.fact.split(separator: "|").prefix(2).joined(separator: "|")
        })
        let expected = Dictionary(uniqueKeysWithValues: progress.physicalProjection.map { ($0.path, $0) })
        guard expected.count == progress.physicalProjection.count else { throw EraseAllServiceError.invalidAuthority }
        var activeParent: String?
        if let index = progress.activeTargetIndex, targets.indices.contains(index), targets[index].kind != .c16,
           deleted.contains(targets[index].path) {
            activeParent = targets[index].path.split(separator: "/").dropLast().joined(separator: "/")
        }
        // Exactly the original immutable subtree survives after the declared
        // mixed prefix. The active PREPARING cut may have lost its ONE node;
        // no later target absence, unrecorded birth or current-name rebase.
        for (path, node) in original where !external(path) && !c16(path) {
            if deleted.contains(path) {
                guard image.nodes[path] == nil else { throw EraseAllServiceError.invalidAuthority }
                continue
            }
            guard let actual = image.nodes[path], actual.sha256 == node.sha256 else {
                throw EraseAllServiceError.invalidAuthority
            }
            if node.kind == "file" {
                guard try Self.nine(actual.fullFact) == node.fact else { throw EraseAllServiceError.invalidAuthority }
            } else {
                let old = try Self.fields(node.fact, count: 9), now = try Self.fields(actual.fullFact)
                guard old[0] == now[0], old[1] == now[1], old[2] == now[2] else { throw EraseAllServiceError.invalidAuthority }
                var members = node.members ?? []
                members.removeAll { deleted.contains(path + "/" + $0) }
                if path == "support/FieldEvidenceOperations" {
                    members = Array(Set(members).subtracting(["ScratchDataV1", "ProtectedIngressReceiptsV1", "generation-leases", "schema-migration", AppLockNotificationControlStoreV1.rootName]))
                    for name in ["ScratchDataV1", "ProtectedIngressReceiptsV1", "generation-leases", "schema-migration", AppLockNotificationControlStoreV1.rootName]
                        where image.nodes[path + "/" + name] != nil { members.append(name) }
                }
                guard actual.names == members.sorted() else { throw EraseAllServiceError.invalidAuthority }
            }
        }
        for path in image.nodes.keys where !external(path) && !c16(path) {
            guard original[path] != nil else { throw EraseAllServiceError.invalidAuthority }
        }
        if let boundary {
            guard boundary.planSHA256 == planSHA256, boundary.ordinal == progress.activeC16Ordinal,
                  boundary.projection.currentOrdinal == boundary.ordinal else { throw EraseAllServiceError.invalidAuthority }
            guard boundary.stepSHA256 == (try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(plan.steps[boundary.ordinal]))) else {
                throw EraseAllServiceError.invalidAuthority
            }
            if let born = boundary.bornSource {
                guard let index = progress.activeTargetIndex, targets.indices.contains(index),
                      targets[index].allowedBirthPaths.contains(born.path),
                      progress.stage == .preparing || progress.stage == .preparingCaptured,
                      let actual = image.nodes["support/FieldEvidenceOperations/" + born.path],
                      actual.fullFact == born.fullFact, actual.sha256 == born.sha256,
                      born.sha256 == (try CompatibilityCanonicalV1.sha256(born.bytes)) else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            let prefix = "support/FieldEvidenceOperations/"
            let finite = boundary.projection
            var expectedPaths = Set(finite.files.map { prefix + $0.path }).union(finite.directories.map { prefix + $0.path })
            // Generic leases/orphans coexist in the same Scratch root; they
            // remain immutable except their separately declared mixed prefix.
            let generic = original.filter { path, _ in path.hasPrefix(prefix + "ScratchDataV1/") && !plan.ownedLeaseNames.contains(String(path.dropFirst((prefix + "ScratchDataV1/").count).split(separator: "/").first ?? "")) }
            expectedPaths.formUnion(generic.keys.filter { !deleted.contains($0) })
            if image.nodes[prefix + "ScratchDataV1"] != nil { expectedPaths.insert(prefix + "ScratchDataV1") }
            guard Set(image.nodes.keys.filter(c16)) == expectedPaths else { throw EraseAllServiceError.invalidAuthority }
            for file in finite.files {
                guard let actual = image.nodes[prefix + file.path], actual.names == nil,
                      let sha = actual.sha256 else { throw EraseAllServiceError.invalidAuthority }
                switch file.source {
                case let .firstP(sourcePath, allowSettlement):
                    guard let first = original[prefix + sourcePath], first.kind == "file", first.sha256 == sha else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    let nine = try Self.nine(actual.fullFact)
                    if nine != first.fact {
                        let a = try Self.fields(nine, count: 9), b = try Self.fields(first.fact, count: 9)
                        // An assigned exact first-P pair settlement may change
                        // only nlink2→1 and ctime, never bytes/mtime/identity.
                        let partial = originalInodes[b.prefix(2).joined(separator: "|")]?.first { candidate in
                            candidate.key != prefix + sourcePath && candidate.value.kind == "file"
                                && candidate.value.fact == first.fact && candidate.value.sha256 == first.sha256
                        }
                        guard allowSettlement, b[3] == "2", a[3] == "1",
                              Array(a.prefix(3)) == Array(b.prefix(3)), Array(a[4...6]) == Array(b[4...6]),
                              let partial, finite.consumedFirstPPaths.contains(String(partial.key.dropFirst(prefix.count))),
                              plan.steps.prefix(boundary.ordinal + 1).contains(where: { step in
                                  if case let .settleFirstPPartial(_, name, device, inode, _) = step {
                                      return partial.key.hasSuffix("/" + name) && b[0] == String(device) && b[1] == String(inode)
                                  }; return false
                              }) else { throw EraseAllServiceError.invalidAuthority }
                    }
                case let .postPDeterministic(_, fact, expectedSHA):
                    guard actual.fullFact == fact, sha == expectedSHA else { throw EraseAllServiceError.invalidAuthority }
                }
            }
            for directory in finite.directories {
                guard let actual = image.nodes[prefix + directory.path],
                      actual.names == directory.expectedMembers,
                      let first = original[prefix + directory.firstPSourcePath] else { throw EraseAllServiceError.invalidAuthority }
                let a = try Self.fields(actual.fullFact), b = try Self.fields(first.fact, count: 9)
                guard a[0] == b[0], a[1] == b[1], a[2] == b[2],
                      a[5] == String(directory.expectedLinkCount) else { throw EraseAllServiceError.invalidAuthority }
            }
            for (path, node) in generic where !deleted.contains(path) {
                guard let actual = image.nodes[path], actual.sha256 == node.sha256,
                      let prior = expected[path], actual.fullFact == prior.fullFact else {
                    throw EraseAllServiceError.invalidAuthority
                }
                if node.kind == "file" {
                    guard try Self.nine(actual.fullFact) == node.fact else { throw EraseAllServiceError.invalidAuthority }
                } else {
                    let first = try Self.fields(node.fact, count: 9), current = try Self.fields(actual.fullFact)
                    let members = (node.members ?? []).filter { !deleted.contains(path + "/" + $0) }
                    guard first[0] == current[0], first[1] == current[1], first[2] == current[2],
                          actual.names == members.sorted() else { throw EraseAllServiceError.invalidAuthority }
                }
            }
            if let scratch = image.nodes[prefix + "ScratchDataV1"] {
                let names = expectedPaths.filter { $0.hasPrefix(prefix + "ScratchDataV1/") }
                    .map { String($0.dropFirst((prefix + "ScratchDataV1/").count).split(separator: "/").first!) }
                guard scratch.names == Array(Set(names)).sorted() else { throw EraseAllServiceError.invalidAuthority }
            }
            for consumed in finite.consumedFirstPPaths {
                guard original[prefix + consumed] != nil,
                      !finite.files.contains(where: { $0.path == consumed }),
                      image.nodes[prefix + consumed] == nil else { throw EraseAllServiceError.invalidAuthority }
            }
        } else {
            // Outside an active C16 boundary, the authenticated canonical
            // postimage is exact for every C16 path. Later generic deletions
            // have their own one-node/prefix proof below.
            for (path, actual) in image.nodes where c16(path) && !deleted.contains(path) && path != activeParent {
                guard let old = expected[path], actual.fullFact == old.fullFact, actual.sha256 == old.sha256 else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
            for path in expected.keys where c16(path) && !deleted.contains(path) && path != activeParent {
                guard image.nodes[path] != nil else { throw EraseAllServiceError.invalidAuthority }
            }
        }
        let expectedSupportRoots = Set(expected.keys.filter { $0.hasPrefix("support/") && $0.split(separator: "/").count == 2 }
            .filter { !deleted.contains($0) }.map { String($0.dropFirst("support/".count)) })
        let observedExternalSearch = image.nodes["support/" + LocalSearchIndexStoreV1.directoryName] != nil
        var expectedSupportNames = expectedSupportRoots.union(["FieldEvidenceData", "FieldEvidenceErase"])
        if observedExternalSearch { expectedSupportNames.insert(LocalSearchIndexStoreV1.directoryName) }
        guard Set(image.supportNames) == expectedSupportNames else { throw EraseAllServiceError.invalidAuthority }
        if let activeParent, let node = image.nodes[activeParent], let names = node.names {
            let direct = expected.keys.filter {
                $0.split(separator: "/").dropLast().joined(separator: "/") == activeParent && !deleted.contains($0)
            }.map { String($0.split(separator: "/").last!) }
            guard names == direct.sorted() else { throw EraseAllServiceError.invalidAuthority }
        }
        for value in image.projection where !external(value.path) && !(boundary != nil && c16(value.path)) {
            guard let old = expected[value.path] else { throw EraseAllServiceError.invalidAuthority }
            let c16OperationsParent = boundary != nil && value.path == "support/FieldEvidenceOperations"
            if value.path == activeParent || c16OperationsParent {
                guard try Self.stable(value.fullFact, old.fullFact), value.sha256 == old.sha256 else {
                    throw EraseAllServiceError.invalidAuthority
                }
                // Child membership above, plus actual link law, constrain
                // parent metadata drift to this one declared child effect.
                if let node = image.nodes[value.path], let names = node.names {
                    let prior = try Self.fields(old.fullFact), now = try Self.fields(value.fullFact)
                    let oldChildDirectories = expected.values.filter { entry in
                        entry.path.split(separator: "/").dropLast().joined(separator: "/") == value.path
                            && entry.sha256 == nil
                    }.count
                    let newChildDirectories = names.filter { image.nodes[value.path + "/" + $0]?.names != nil }.count
                    guard let oldLinks = Int64(prior[5]), let newLinks = Int64(now[5]),
                          newLinks == oldLinks || newLinks == oldLinks + Int64(newChildDirectories - oldChildDirectories) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
            } else if value.path == "caches" || value.path == "temporary" {
                // Sibling apps are outside our ownership; exact identity is
                // held while only their FieldEvidenceApp child is compared.
                guard try Self.stable(value.fullFact, old.fullFact) else { throw EraseAllServiceError.invalidAuthority }
            } else {
                guard value == old else { throw EraseAllServiceError.invalidAuthority }
            }
        }
        let actualPaths = Set(image.projection.map(\.path))
        for path in expected.keys where !actualPaths.contains(path)
            && !external(path) && !(boundary != nil && c16(path)) {
            guard deleted.contains(path) else { throw EraseAllServiceError.invalidAuthority }
        }
    }

    /// Initial source/bootstrap witness precedes createProgress. The permit
    /// authenticates existing canonical Transfer/Sources/Plan and progress
    /// absence, never a hash of a yet-unpublished future record.
    func observeInitialComplete(support: Int32, caches: Int32, temporary: Int32,
        initialScope: OriginalEraseC16InitialObservationScopeV1?,
        permit: EraseSchema2ColdPhysicalPermitV1) throws -> [Progress.Projection] {
        let one = try scan(support: support, caches: caches, temporary: temporary,
            c16Scope: nil, permit: permit, progress: nil, initialScope: initialScope)
        let original = originalNodes()
        for (path, node) in original where !external(path) {
            guard let actual = one.nodes[path], try Self.nine(actual.fullFact) == node.fact,
                  actual.names == node.members, actual.sha256 == node.sha256 else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        for path in one.nodes.keys where !external(path) {
            guard original[path] != nil else { throw EraseAllServiceError.invalidAuthority }
        }
        guard let supportFact = one.projection.first(where: { $0.path == "support" }),
              supportFact.fullFact == originalP.record.firstSupportFact else { throw EraseAllServiceError.invalidAuthority }
        let two = try scan(support: support, caches: caches, temporary: temporary,
            c16Scope: nil, permit: permit, progress: nil, initialScope: initialScope)
        guard one == two else { throw EraseAllServiceError.invalidAuthority }
        return two.projection
    }

    func observeComplete(support: Int32, caches: Int32, temporary: Int32,
        c16Scope: OriginalEraseC16CurrentObservationScopeV1?,
        permit: EraseSchema2ColdPhysicalPermitV1, progress: Progress) throws -> [Progress.Projection] {
        let one = try scan(support: support, caches: caches, temporary: temporary,
            c16Scope: c16Scope, permit: permit, progress: progress)
        let two = try scan(support: support, caches: caches, temporary: temporary,
            c16Scope: c16Scope, permit: permit, progress: progress)
        guard one == two else { throw EraseAllServiceError.invalidAuthority }
        return two.projection
    }
    func requireComplete(support: Int32, caches: Int32, temporary: Int32,
        c16Scope: OriginalEraseC16CurrentObservationScopeV1?,
        permit: EraseSchema2ColdPhysicalPermitV1, boundary: OriginalEraseC16BoundaryObservationV1?,
        progress: Progress) throws -> [Progress.Projection] {
        let one = try scan(support: support, caches: caches, temporary: temporary,
            c16Scope: c16Scope, permit: permit, progress: progress)
        try requireFinite(one, boundary: boundary, progress: progress)
        let two = try scan(support: support, caches: caches, temporary: temporary,
            c16Scope: c16Scope, permit: permit, progress: progress)
        guard one == two else { throw EraseAllServiceError.invalidAuthority }
        try requireBinding(permit, progress: progress)
        return two.projection
    }

    private func withTargetParent<Value>(path: String, image: Image,
        support: Int32, caches: Int32, temporary: Int32,
        requireBinding: @MainActor () throws -> Void, poison: @MainActor () -> Void,
        _ body: @MainActor (Int32,String) throws -> Value) throws -> Value {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts.count <= 67,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.utf8.contains(0) }) else {
            throw EraseAllServiceError.invalidAuthority
        }
        let root: Int32
        switch parts[0] { case "support": root = support; case "caches": root = caches; case "temporary": root = temporary
        default: throw EraseAllServiceError.invalidAuthority }
        func descend(_ fd: Int32, _ index: Int) throws -> Value {
            try requireBinding()
            if index == parts.count - 1 { return try body(fd, parts[index]) }
            let prefix = parts.prefix(index + 1).joined(separator: "/")
            guard let expected = image.nodes[prefix], expected.names != nil else { throw EraseAllServiceError.invalidAuthority }
            return try io.schema2ColdWithOpen(parent: fd, name: parts[index], flags: O_RDONLY | O_DIRECTORY | O_NONBLOCK,
                requireBinding: requireBinding, poison: poison) { child in
                var held = stat(), named = stat()
                try requireBinding()
                guard Darwin.fstat(child, &held) == 0 else { throw EraseAllServiceError.invalidAuthority }
                try requireBinding()
                guard Darwin.fstatat(fd, parts[index], &named, AT_SYMLINK_NOFOLLOW) == 0,
                      Self.fact(held) == expected.fullFact, Self.fact(named) == expected.fullFact,
                      try io.schema2ColdNames(in: child, requireBinding: requireBinding, poison: poison) == expected.names else { throw EraseAllServiceError.invalidAuthority }
                let value = try descend(child, index + 1)
                try requireBinding()
                return value
            }
        }
        return try descend(root, 1)
    }

    /// One fixed mixed ordinal, including fresh-process PREPARING replay of
    /// its exact already-absent node. Parent sync and actual ENOENT are checked
    /// even on that replay. The finite suffix prevents skipping a later node.
    func performOneTarget(support: Int32, caches: Int32, temporary: Int32,
        progress: Progress, c16Scope: OriginalEraseC16CurrentObservationScopeV1?,
        permit: EraseSchema2ColdPhysicalPermitV1) throws -> EraseSchema2ColdPhysicalEffectReceiptV1 {
        try requireBinding(permit, progress: progress)
        guard !inFlight, let index = progress.activeTargetIndex, targets.indices.contains(index),
              index == progress.completedPrefixCount, targets[index].kind != .c16,
              progress.stage == .preparing || progress.stage == .preparingCaptured,
              !attemptedTargetIndices.contains(index) else { throw EraseAllServiceError.invalidAuthority }
        func bound() throws { try self.requireBinding(permit, progress: progress); try c16Scope?.requireCurrentBinding() }
        func poison() { self.uncertain = true; permit.poisonOnUncertainEffect(); c16Scope?.poisonOnUncertainObservation() }
        let target = targets[index]
        let before = try scan(support: support, caches: caches, temporary: temporary,
            c16Scope: c16Scope, permit: permit, progress: progress)
        try requireFinite(before, boundary: nil, progress: progress)
        let beforeAgain = try scan(support: support, caches: caches, temporary: temporary,
            c16Scope: c16Scope, permit: permit, progress: progress)
        guard before == beforeAgain else { throw EraseAllServiceError.invalidAuthority }
        let progressSHA = StoreMigrationCanonicalJSONV1.sha256(try StoreMigrationCanonicalJSONV1.encode(progress))
        attemptedTargetIndices.insert(index); inFlight = true
        defer { inFlight = false }
        do {
            var effect: EraseSchema2ColdPhysicalEffectReceiptV1.Effect = .originallyAbsent
            // If a prospective owner root is positively absent, prove the
            // nearest absent ancestor with nofollow and sync its actual held
            // parent. Never traverse an unexplained path through a symlink.
            var physicalPath = target.path
            if before.nodes[target.path] == nil {
                let components = target.path.split(separator: "/").map(String.init)
                for depth in 2...components.count {
                    let candidate = components.prefix(depth).joined(separator: "/")
                    if before.nodes[candidate] == nil { physicalPath = candidate; break }
                }
            }
            try withTargetParent(path: physicalPath, image: before, support: support, caches: caches, temporary: temporary,
                requireBinding: bound, poison: poison) { parent, name in
                try requireBinding(permit, progress: progress)
                if let node = before.nodes[target.path] {
                    let directory = node.names != nil
                    guard !directory || node.names == [] else { throw EraseAllServiceError.invalidAuthority }
                    try io.schema2ColdWithOpen(parent: parent, name: name,
                        flags: O_RDONLY | O_NONBLOCK | (directory ? O_DIRECTORY : 0), requireBinding: bound, poison: poison) { fd in
                        var held = stat(), named = stat()
                        try bound()
                        guard Darwin.fstat(fd, &held) == 0 else { throw EraseAllServiceError.invalidAuthority }
                        try bound()
                        guard Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                              Self.fact(held) == node.fullFact, Self.fact(named) == node.fullFact,
                              directory ? held.st_mode & S_IFMT == S_IFDIR : held.st_mode & S_IFMT == S_IFREG && held.st_nlink == 1,
                              !directory || (try io.schema2ColdNames(in: fd, requireBinding: bound, poison: poison)).isEmpty else { throw EraseAllServiceError.invalidAuthority }
                        try requireBinding(permit, progress: progress)
                        guard Darwin.unlinkat(parent, name, directory ? AT_REMOVEDIR : 0) == 0 else {
                            throw EraseAllServiceError.cleanupFailed
                        }
                        effect = .unlinked
                        try bound()
                        guard Darwin.fsync(parent) == 0 else { throw EraseAllServiceError.cleanupFailed }
                        try bound()
                        guard Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) != 0,
                              errno == ENOENT else { throw EraseAllServiceError.cleanupFailed }
                        try requireBinding(permit, progress: progress)
                    }
                } else {
                    var named = stat()
                    try bound()
                    guard Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) != 0,
                          errno == ENOENT else { throw EraseAllServiceError.cleanupFailed }
                    try bound()
                    guard Darwin.fsync(parent) == 0 else { throw EraseAllServiceError.cleanupFailed }
                    try bound()
                    if originalNodes()[target.path] != nil { effect = .resumedPreparingAbsence }
                }
                try requireBinding(permit, progress: progress)
            }
            let after = try scan(support: support, caches: caches, temporary: temporary,
                c16Scope: c16Scope, permit: permit, progress: progress)
            try requireFinite(after, boundary: nil, progress: progress)
            let afterAgain = try scan(support: support, caches: caches, temporary: temporary,
                c16Scope: c16Scope, permit: permit, progress: progress)
            guard after == afterAgain, after.nodes[target.path] == nil else { throw EraseAllServiceError.invalidAuthority }
            let parentPath = target.path.split(separator: "/").dropLast().joined(separator: "/")
            for (path, node) in before.nodes where path != target.path && path != parentPath {
                guard after.nodes[path] == node else { throw EraseAllServiceError.invalidAuthority }
            }
            guard Set(after.nodes.keys) == Set(before.nodes.keys).subtracting([target.path]) else {
                throw EraseAllServiceError.invalidAuthority
            }
            try io.requireSettled(); try requireBinding(permit, progress: progress)
            let receipt = EraseSchema2ColdPhysicalEffectReceiptV1(owner: self, progressSHA256: progressSHA,
                targetIndex: index, target: target, effect: effect, before: before.projection, after: after.projection)
            lastEffect = receipt
            return receipt
        } catch {
            // A failed syscall, close or postimage check is permanent. Neither
            // this owner nor deinit inspects/retries a possibly reused FD.
            uncertain = true; permit.poisonOnUncertainEffect(); throw error
        }
    }

    fileprivate func requireReceipt(_ receipt: EraseSchema2ColdPhysicalEffectReceiptV1, progress: Progress) throws {
        try requireMemory()
        guard lastEffect === receipt, receipt.ownerID == ownerID,
              receipt.originalPAuxiliaryRosterSHA256 == originalP.canonicalSHA256,
              receipt.planSHA256 == planSHA256, targets.indices.contains(receipt.targetIndex),
              receipt.target == targets[receipt.targetIndex],
              receipt.progressSHA256 == StoreMigrationCanonicalJSONV1.sha256(try StoreMigrationCanonicalJSONV1.encode(progress)),
              progress.activeTargetIndex == receipt.targetIndex else { throw EraseAllServiceError.invalidAuthority }
    }

    /// All transient descriptors have already been checked-closed per scan
    /// and effect. This closes the observer lifetime only; the genuine owner
    /// remains the sole closer of borrowed EX/Support/cache/temp resources.
    func closeObservationChecked(permit: EraseSchema2ColdPhysicalPermitV1, progress: Progress) throws {
        try requireBinding(permit, progress: progress)
        guard !inFlight else { throw EraseAllServiceError.invalidAuthority }
        closeAttempted = true // Permanent memory fence precedes any further IO.
        do { try io.requireSettled(); closed = true }
        catch { uncertain = true; permit.poisonOnUncertainEffect(); throw error }
    }
}
