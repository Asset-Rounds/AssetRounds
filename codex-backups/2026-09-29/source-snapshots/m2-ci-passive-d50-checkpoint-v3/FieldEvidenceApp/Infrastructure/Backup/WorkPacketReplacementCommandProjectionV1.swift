import Foundation

enum WorkPacketReplacementCommandProjectionFailureV1: Error, Equatable {
    case invalidIdentity, invalidSource, collision, missingDependency, incompleteProjection
}

/// Projects authenticated historical coordination commands before the global
/// replacement sequencer emits receipts. Original items and result attribution
/// remain immutable; this projection owns neither result remapping nor storage.
enum WorkPacketReplacementCommandProjectionV1 {
    struct Command: Equatable, Sendable {
        let source: ReferenceOwnerReplacementSourceV1.Entry
        let mutation: WorkPacketMutationV1
        let postImage: MutationPostImageV1
        let sourceDependencyMutationIDs: [MutationIDV1]
        let targetDependencyMutationIDs: [MutationIDV1]

        fileprivate init(source: ReferenceOwnerReplacementSourceV1.Entry,
                         mutation: WorkPacketMutationV1, postImage: MutationPostImageV1,
                         sourceDependencyMutationIDs: [MutationIDV1],
                         targetDependencyMutationIDs: [MutationIDV1]) {
            self.source = source; self.mutation = mutation; self.postImage = postImage
            self.sourceDependencyMutationIDs = sourceDependencyMutationIDs
            self.targetDependencyMutationIDs = targetDependencyMutationIDs
        }
    }

    struct ManifestBinding: Equatable, Sendable {
        let source: WorkPacketManifestV1
        let target: WorkPacketManifestV1
        let sourceMutationID: MutationIDV1
        let targetMutationID: MutationIDV1

        fileprivate init(source: WorkPacketManifestV1, target: WorkPacketManifestV1) {
            self.source = source; self.target = target
            sourceMutationID = source.mutationID; targetMutationID = target.mutationID
        }
    }

    struct Projection: Equatable, Sendable {
        let source: ReferenceOwnerReplacementSourceV1.Source
        let identity: RestoreIdentityV1
        let commands: [Command]
        let manifests: [ManifestBinding]

        fileprivate init(source: ReferenceOwnerReplacementSourceV1.Source,
                         identity: RestoreIdentityV1, commands: [Command],
                         manifests: [ManifestBinding]) {
            self.source = source; self.identity = identity
            self.commands = commands; self.manifests = manifests
        }

        func targetManifest(for reference: WorkPacketManifestReferenceV1) throws -> WorkPacketManifestV1 {
            try reference.validate()
            let matches = try manifests.filter { try WorkPacketManifestReferenceV1($0.source) == reference }
            guard matches.count == 1 else {
                throw WorkPacketReplacementCommandProjectionFailureV1.missingDependency
            }
            return matches[0].target
        }
    }

    static func project(source: ReferenceOwnerReplacementSourceV1.Source,
                        identity: RestoreIdentityV1) throws -> Projection {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard identity.mode == .replaceExisting,
              source.workspaceID.rawValue == identity.source.workspaceID,
              source.workspaceID.rawValue != zero,
              identity.targetPointer.workspaceID == identity.oldPointer.workspaceID,
              identity.targetPointer.workspaceID != zero,
              identity.targetPointer.generationID != zero,
              identity.targetPointer.generationID != identity.oldPointer.generationID else {
            throw WorkPacketReplacementCommandProjectionFailureV1.invalidIdentity
        }
        let originals = try source.entries.filter { $0.family == .workPacket }.map { entry in
            guard case let .applyWorkPacket(mutation) = entry.envelope.command else {
                throw WorkPacketReplacementCommandProjectionFailureV1.invalidSource
            }
            return Original(entry: entry, mutation: mutation)
        }
        guard Set(try originals.map { try $0.mutation.affectedIdentity }).count == originals.count else {
            throw WorkPacketReplacementCommandProjectionFailureV1.collision
        }
        let originalMutationIDs = try Set(source.history.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData).mutationID
        })
        var state = State(identity: identity, originalMutationIDs: originalMutationIDs)
        let manifests = originals.filter { if case .appendManifest = $0.mutation.postImage { true } else { false } }
        let claims = originals.filter {
            switch $0.mutation.postImage { case .appendClaim, .supersedeClaim: true; default: false }
        }.sorted(by: predecessorOrder)
        let leases = originals.filter {
            switch $0.mutation.postImage { case .appendLease, .supersedeLease: true; default: false }
        }.sorted(by: predecessorOrder)
        let releases = originals.filter { if case .recordRelease = $0.mutation.postImage { true } else { false } }
        let handoffs = originals.filter { if case .recordHandoff = $0.mutation.postImage { true } else { false } }
        guard [manifests.count, claims.count, leases.count, releases.count, handoffs.count]
            .allSatisfy({ $0 <= WorkPacketLimitsV1.maximumHistory }) else { throw WorkPacketFailureV1.limitExceeded }
        for original in manifests { try state.appendManifest(original) }
        for original in claims { try state.appendClaim(original) }
        for original in leases { try state.appendLease(original) }
        for original in releases { try state.appendRelease(original) }
        for original in handoffs { try state.appendHandoff(original) }
        guard state.commands.count == originals.count else {
            throw WorkPacketReplacementCommandProjectionFailureV1.incompleteProjection
        }
        let commands = try originals.map { original in
            guard let command = state.commands[original.mutation.mutationID] else {
                throw WorkPacketReplacementCommandProjectionFailureV1.incompleteProjection
            }
            return command
        }
        let bindings = try manifests.map { original in
            guard case let .appendManifest(value) = original.mutation.postImage,
                  let pair = state.manifests[value.manifestID] else {
                throw WorkPacketReplacementCommandProjectionFailureV1.incompleteProjection
            }
            return ManifestBinding(source: pair.source, target: pair.target)
        }
        return Projection(source: source, identity: identity, commands: commands, manifests: bindings)
    }
}

private extension WorkPacketReplacementCommandProjectionV1 {
    struct Original {
        let entry: ReferenceOwnerReplacementSourceV1.Entry
        let mutation: WorkPacketMutationV1
    }

    struct Pair<Value> {
        let original: Original
        let source: Value
        let target: Value
    }

    static func predecessorOrder(_ left: Original, _ right: Original) -> Bool {
        if left.mutation.postImage.revision != right.mutation.postImage.revision {
            return left.mutation.postImage.revision < right.mutation.postImage.revision
        }
        return left.entry.receipt.identity.stableKey < right.entry.receipt.identity.stableKey
    }

    struct State {
        let identity: RestoreIdentityV1
        let originalMutationIDs: Set<MutationIDV1>
        var commands: [MutationIDV1: Command] = [:]
        var targetMutationIDs = Set<MutationIDV1>()
        var manifests: [UUID: Pair<WorkPacketManifestV1>] = [:]
        var claims: [UUID: Pair<WorkItemClaimV1>] = [:]
        var leases: [UUID: Pair<WorkLeaseV1>] = [:]
        var releases: [UUID: Pair<WorkReleaseV1>] = [:]
        var workspaceID: WorkspaceID { WorkspaceID(rawValue: identity.targetPointer.workspaceID) }

        func mutationID(_ original: Original) throws -> MutationIDV1 {
            try identity.destinationWorkPacketMutationID(for: original.mutation.mutationID)
        }

        func actor(_ value: ActorSnapshotV1) throws -> ActorSnapshotV1 {
            try .init(snapshotID: value.snapshotID, workspaceID: workspaceID,
                      actor: LocalActorReferenceV1(actorReferenceID: value.actor.actorReferenceID,
                                                  workspaceID: workspaceID, partyID: value.actor.partyID,
                                                  displayName: value.actor.displayName),
                      responsibility: value.responsibility, displayNameAtTime: value.displayNameAtTime,
                      capturedAt: value.capturedAt)
        }

        func manifest(_ reference: WorkPacketManifestReferenceV1) throws -> Pair<WorkPacketManifestV1> {
            guard let pair = manifests[reference.manifestID],
                  try WorkPacketManifestReferenceV1(pair.source) == reference else {
                throw WorkPacketReplacementCommandProjectionFailureV1.missingDependency
            }
            return pair
        }

        func item(_ reference: WorkPacketItemReferenceV1) throws -> WorkPacketItemReferenceV1 {
            let matches = manifests.values.filter {
                $0.source.workspaceID == reference.workspaceID && $0.source.packetID == reference.packetID
                    && $0.source.packetVersion == reference.packetVersion
                    && $0.source.manifestSHA256 == reference.manifestSHA256
            }
            guard matches.count == 1, let pair = matches.first,
                  let value = pair.source.items.first(where: { $0.itemID == reference.itemID }),
                  try WorkPacketItemReferenceV1(manifest: pair.source, item: value) == reference else {
                throw WorkPacketReplacementCommandProjectionFailureV1.missingDependency
            }
            return try WorkPacketItemReferenceV1(manifest: pair.target, item: value)
        }

        mutating func record(_ original: Original, payload: WorkPacketMutationPayloadV1,
                             dependencies: [Original]) throws {
            let target = try WorkPacketMutationV1(workspaceID: workspaceID,
                expectedRevision: original.mutation.expectedRevision,
                mutationID: mutationID(original), postImage: payload)
            guard commands[original.mutation.mutationID] == nil,
                  !originalMutationIDs.contains(target.mutationID),
                  targetMutationIDs.insert(target.mutationID).inserted else {
                throw WorkPacketReplacementCommandProjectionFailureV1.collision
            }
            let sourceIDs = Set(dependencies.map { $0.mutation.mutationID }).sorted {
                $0.rawValue.uuidString < $1.rawValue.uuidString
            }
            let targetIDs = try sourceIDs.map { sourceID in
                guard let dependency = commands[sourceID] else {
                    throw WorkPacketReplacementCommandProjectionFailureV1.missingDependency
                }
                return dependency.mutation.mutationID
            }.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
            commands[original.mutation.mutationID] = Command(source: original.entry, mutation: target,
                postImage: try payload.mutationPostImage, sourceDependencyMutationIDs: sourceIDs,
                targetDependencyMutationIDs: targetIDs)
        }

        mutating func appendManifest(_ original: Original) throws {
            guard case let .appendManifest(source) = original.mutation.postImage else {
                throw WorkPacketReplacementCommandProjectionFailureV1.invalidSource
            }
            let target = try WorkPacketManifestV1(manifestID: source.manifestID, packetID: source.packetID,
                packetVersion: source.packetVersion, workspaceID: workspaceID, items: source.items,
                packageReleases: source.packageReleases, creationBasis: source.creationBasis,
                creator: actor(source.creator), createdAt: source.createdAt,
                revision: source.revision, mutationID: mutationID(original))
            try record(original, payload: .appendManifest(target), dependencies: [])
            manifests[source.manifestID] = Pair(original: original, source: source, target: target)
        }

        mutating func appendClaim(_ original: Original) throws {
            let source: WorkItemClaimV1
            switch original.mutation.postImage {
            case let .appendClaim(value), let .supersedeClaim(value): source = value
            default: throw WorkPacketReplacementCommandProjectionFailureV1.invalidSource
            }
            let manifest = try manifest(source.manifest)
            let target = try WorkItemClaimV1(claimID: source.claimID, workspaceID: workspaceID,
                manifest: WorkPacketManifestReferenceV1(manifest.target), item: item(source.item),
                holder: actor(source.holder), claimSequence: source.claimSequence, claimedAt: source.claimedAt,
                supersedesClaimID: source.supersedesClaimID, revision: source.revision,
                mutationID: mutationID(original))
            var dependencies = [manifest.original]
            if let predecessorID = source.supersedesClaimID {
                guard let predecessor = claims[predecessorID] else {
                    throw WorkPacketReplacementCommandProjectionFailureV1.missingDependency
                }
                try source.validateSuccessor(of: predecessor.source)
                try target.validateSuccessor(of: predecessor.target)
                dependencies.append(predecessor.original)
            }
            try record(original, payload: source.supersedesClaimID == nil
                ? .appendClaim(target) : .supersedeClaim(target), dependencies: dependencies)
            claims[source.claimID] = Pair(original: original, source: source, target: target)
        }

        mutating func appendLease(_ original: Original) throws {
            let source: WorkLeaseV1
            switch original.mutation.postImage {
            case let .appendLease(value), let .supersedeLease(value): source = value
            default: throw WorkPacketReplacementCommandProjectionFailureV1.invalidSource
            }
            guard let claim = claims[source.claimID], claim.source.item == source.item,
                  claim.source.holder.actor == source.holder.actor else {
                throw WorkPacketReplacementCommandProjectionFailureV1.missingDependency
            }
            let target = try WorkLeaseV1(leaseID: source.leaseID, workspaceID: workspaceID,
                claimID: source.claimID, item: item(source.item), holder: actor(source.holder),
                leaseSequence: source.leaseSequence, startsAt: source.startsAt, expiresAt: source.expiresAt,
                supersedesLeaseID: source.supersedesLeaseID, revision: source.revision,
                mutationID: mutationID(original))
            var dependencies = [claim.original]
            if let predecessorID = source.supersedesLeaseID {
                guard let predecessor = leases[predecessorID] else {
                    throw WorkPacketReplacementCommandProjectionFailureV1.missingDependency
                }
                try source.validateSuccessor(of: predecessor.source)
                try target.validateSuccessor(of: predecessor.target)
                dependencies.append(predecessor.original)
            }
            try record(original, payload: source.supersedesLeaseID == nil
                ? .appendLease(target) : .supersedeLease(target), dependencies: dependencies)
            leases[source.leaseID] = Pair(original: original, source: source, target: target)
        }

        mutating func appendRelease(_ original: Original) throws {
            guard case let .recordRelease(source) = original.mutation.postImage,
                  let claim = claims[source.claimID], let lease = leases[source.leaseID] else {
                throw WorkPacketReplacementCommandProjectionFailureV1.missingDependency
            }
            let manifest = try manifest(claim.source.manifest)
            try source.validate(claim: claim.source, lease: lease.source, manifest: manifest.source)
            let target = try WorkReleaseV1(releaseID: source.releaseID, workspaceID: workspaceID,
                claimID: source.claimID, leaseID: source.leaseID, item: item(source.item), holder: actor(source.holder),
                reason: source.reason, resultLinks: source.resultLinks, releasedAt: source.releasedAt,
                revision: source.revision, mutationID: mutationID(original))
            try target.validate(claim: claim.target, lease: lease.target, manifest: manifest.target)
            try record(original, payload: .recordRelease(target),
                       dependencies: [claim.original, lease.original, manifest.original])
            releases[source.releaseID] = Pair(original: original, source: source, target: target)
        }

        mutating func appendHandoff(_ original: Original) throws {
            guard case let .recordHandoff(source) = original.mutation.postImage,
                  let release = releases[source.releaseID] else {
                throw WorkPacketReplacementCommandProjectionFailureV1.missingDependency
            }
            try source.validate(release: release.source)
            let target = try WorkHandoffV1(handoffID: source.handoffID, workspaceID: workspaceID,
                releaseID: source.releaseID, item: item(source.item), fromHolder: actor(source.fromHolder),
                toHolder: actor(source.toHolder), resultLinks: source.resultLinks, reason: source.reason,
                handedOffAt: source.handedOffAt, revision: source.revision, mutationID: mutationID(original))
            try target.validate(release: release.target)
            try record(original, payload: .recordHandoff(target), dependencies: [release.original])
        }
    }
}
