import Foundation

enum AssetLabelLifecycleFailureV1: Error, Equatable, Sendable {
    case currentAuthorityUnavailable
    case projectionNotStaged
    case publicationMismatch
}

/// The live authority closure must re-read every asset revision, locator binding,
/// template release, and renderer release represented by the plan. A cached plan
/// is never sufficient authority to generate or accept labels.
@MainActor final class AssetLabelAuthoritativePlanAdapterV1:
    AssetLabelAuthoritativePlanValidatingV1 {
    typealias Validate = @MainActor (AssetLabelGenerationPlanV1) async throws -> Void
    private let validateLive: Validate

    init(validateLive: @escaping Validate) { self.validateLive = validateLive }

    func validateCurrent(_ plan: AssetLabelGenerationPlanV1) async throws {
        try plan.validate()
        guard plan.template.rendererID == DeterministicPDFRendererV1.assetLabelRendererID,
              plan.template.rendererVersion == DeterministicPDFRendererV1.assetLabelRendererVersion,
              plan.template.rendererSHA256 == DeterministicPDFRendererV1.assetLabelRendererSHA256,
              plan.template.rendererRelease.nativeTextLayoutReleaseID == DeterministicPDFRendererV1.assetLabelNativeTextLayoutReleaseID,
              plan.template.rendererRelease == (try AssetLabelRendererReleaseReferenceV1.current),
              !plan.template.interpolationEnabled,
              !plan.template.overlaidLogoEnabled else {
            throw AssetLabelContractFailureV1.unsupportedTemplate
        }
        try await validateLive(plan)
    }
}

/// C45 extends the one existing deterministic PDF/report renderer. CSV and
/// structured text are companion projections from that same renderer release.
@MainActor final class AssetLabelExistingRendererAdapterV1:
    AssetLabelProjectionRenderingV1 {
    func project(_ plan: AssetLabelGenerationPlanV1) async throws -> LabelProjectionResultV1 {
        try DeterministicPDFRendererV1.renderAssetLabels(plan)
    }
}

/// Bounded scratch/publication ownership used by the existing resumable job.
/// Implementations stage all three artifacts under the attempt directory,
/// atomically publish-or-adopt the exact manifest, and remove scratch after a
/// terminal receipt, cancellation, delete, restore reconciliation, or Erase.
struct AssetLabelArtifactOperationsV1: Sendable {
    let stage: @Sendable (LocalJobIDV1, AssetLabelGenerationPlanV1, LabelProjectionResultV1) async throws -> Void
    let load: @Sendable (LocalJobIDV1, String) async throws -> (AssetLabelGenerationPlanV1, LabelProjectionResultV1)?
    let publishOrAdopt: @Sendable (ResumableLocalJobV1, String, String) throws -> LocalJobPublicationOutcomeV1
    let adoptOnly: @Sendable (ResumableLocalJobV1, String, String) throws -> LocalJobPublicationOutcomeV1
    /// Exact readback from the existing published-content authority. It must
    /// return nil rather than reconstructing from deleted attempt scratch.
    let publishedReadback: @Sendable (LocalJobIDV1, String, String) async throws -> AssetLabelPublishedContentReadbackV1?
    let removePublishedOutput: @Sendable (AssetLabelRenderPublicationBindingV1) async throws -> Void
    let removePublishedWorkspace: @Sendable (WorkspaceID) async throws -> Void
    let eraseAllPublished: @Sendable () async throws -> Void
    let discardUncommitted: @Sendable (ResumableLocalJobV1) async throws -> Void
    let discard: @Sendable (LocalJobIDV1) async throws -> Void

    /// Durable attempt scratch uses canonical plan/manifest documents and the
    /// three exact artifact files. Publication is still delegated to the
    /// existing content-store adoption authority supplied by the composition
    /// root, so this staging helper cannot become a second byte store.
    static func durableStaging(
        jobStagingRootURL: URL,
        publishOrAdopt: @escaping @Sendable (ResumableLocalJobV1, String, String) throws -> LocalJobPublicationOutcomeV1,
        adoptOnly: @escaping @Sendable (ResumableLocalJobV1, String, String) throws -> LocalJobPublicationOutcomeV1,
        publishedReadback: @escaping @Sendable (LocalJobIDV1, String, String) async throws -> AssetLabelPublishedContentReadbackV1?,
        removePublishedOutput: @escaping @Sendable (AssetLabelRenderPublicationBindingV1) async throws -> Void,
        removePublishedWorkspace: @escaping @Sendable (WorkspaceID) async throws -> Void,
        eraseAllPublished: @escaping @Sendable () async throws -> Void,
        discardUncommitted: @escaping @Sendable (ResumableLocalJobV1) async throws -> Void
    ) throws -> Self {
        let scratch = try AssetLabelArtifactScratchStoreV1(
            rootURL: jobStagingRootURL.appendingPathComponent(
                "asset-label-render",
                isDirectory: true
            )
        )
        return Self(
            stage: { id, plan, result in try scratch.stage(id: id, plan: plan, result: result) },
            load: { id, digest in try scratch.load(id: id, planSHA256: digest) },
            publishOrAdopt: publishOrAdopt,
            adoptOnly: adoptOnly,
            publishedReadback: publishedReadback,
            removePublishedOutput: removePublishedOutput,
            removePublishedWorkspace: removePublishedWorkspace,
            eraseAllPublished: eraseAllPublished,
            discardUncommitted: discardUncommitted,
            discard: { id in try scratch.discard(id: id) }
        )
    }

    /// Production construction over the sole C05 EvidenceBundleStore. The
    /// attempt scratch remains backup-excluded; publication adopts the exact
    /// three derivative content identities and an atomic store marker.
    static func production(
        jobStagingRootURL: URL,
        contentStore: EvidenceBundleStore
    ) throws -> Self {
        let scratch = try AssetLabelArtifactScratchStoreV1(
            rootURL: jobStagingRootURL.appendingPathComponent("asset-label-render", isDirectory: true)
        )
        return Self(
            stage: { id, plan, result in try scratch.stage(id: id, plan: plan, result: result) },
            load: { id, digest in try scratch.load(id: id, planSHA256: digest) },
            publishOrAdopt: { job, planSHA256, outputSHA256 in
                guard let staged = try scratch.load(id: job.id, planSHA256: planSHA256),
                      staged.1.manifest.manifestSHA256 == outputSHA256 else {
                    throw AssetLabelLifecycleFailureV1.projectionNotStaged
                }
                _ = try contentStore.publishOrAdoptAssetLabelArtifacts(
                    job: job, plan: staged.0, projection: staged.1
                )
                return .completed(try LocalJobPublicationReceiptV1(
                    jobID: job.id, attemptCount: job.attemptCount, kind: .render,
                    outputSHA256: outputSHA256, disposition: .published, readBackAt: Date()
                ))
            },
            adoptOnly: { job, planSHA256, outputSHA256 in
                guard try contentStore.adoptAssetLabelArtifacts(
                    jobID: job.id, planSHA256: planSHA256, outputSHA256: outputSHA256
                ) != nil else { return .absent }
                return .completed(try LocalJobPublicationReceiptV1(
                    jobID: job.id, attemptCount: job.attemptCount, kind: .render,
                    outputSHA256: outputSHA256, disposition: .adopted, readBackAt: Date()
                ))
            },
            publishedReadback: { id, planSHA256, outputSHA256 in
                guard let value = try contentStore.readAssetLabelArtifacts(jobID: id) else { return nil }
                guard value.plan.planSHA256 == planSHA256,
                      value.projection.manifest.manifestSHA256 == outputSHA256 else {
                    throw AssetLabelLifecycleFailureV1.publicationMismatch
                }
                return value
            },
            removePublishedOutput: { binding in try contentStore.removeAssetLabelPublishedOutput(binding) },
            removePublishedWorkspace: { workspaceID in try contentStore.removeAssetLabelPublishedWorkspace(workspaceID) },
            eraseAllPublished: { try contentStore.eraseAllAssetLabelPublishedArtifacts() },
            discardUncommitted: { job in
                guard let staged = try scratch.load(id: job.id, planSHA256: job.immutableInputSHA256) else {
                    throw AssetLabelLifecycleFailureV1.projectionNotStaged
                }
                try contentStore.discardUncommittedAssetLabelArtifacts(
                    job: job, plan: staged.0, projection: staged.1
                )
            },
            discard: { id in try scratch.discard(id: id) }
        )
    }
}

/// Attempt-owned, backup-excluded scratch. The resumable job ledger is the
/// index: relaunch reconstructs the plan/result solely from jobID + plan digest.
private final class AssetLabelArtifactScratchStoreV1: @unchecked Sendable {
    private let rootURL: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()

    init(rootURL: URL) throws {
        guard rootURL.isFileURL else { throw LocalJobValidationFailureV1.invalidContract }
        self.rootURL = rootURL.standardizedFileURL
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        try ProtectedFilePolicyV1.applyAndVerify(.scratch, at: self.rootURL)
    }

    func stage(
        id: LocalJobIDV1,
        plan: AssetLabelGenerationPlanV1,
        result: LabelProjectionResultV1
    ) throws {
        try plan.validate(); try result.validate(plan: plan)
        lock.lock(); defer { lock.unlock() }
        let directory = directoryURL(id)
        let temporary = rootURL.appendingPathComponent(".stage-\(id.rawValue.uuidString.lowercased())", isDirectory: true)
        if fileManager.fileExists(atPath: temporary.path) { try fileManager.removeItem(at: temporary) }
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: false)
        try ProtectedFilePolicyV1.applyAndVerify(.scratch, at: temporary)
        do {
            let planURL = temporary.appendingPathComponent("plan.json")
            let manifestURL = temporary.appendingPathComponent("manifest.json")
            let textEnvironmentURL = temporary.appendingPathComponent("native-text-environment.json")
            try AssetLabelCanonicalCodecV1.encode(plan).write(to: planURL, options: .atomic)
            try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: planURL)
            try AssetLabelCanonicalCodecV1.encode(result.manifest).write(to: manifestURL, options: .atomic)
            try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: manifestURL)
            try AssetLabelCanonicalCodecV1.encode(result.nativeTextEnvironment).write(
                to: textEnvironmentURL,
                options: .atomic
            )
            try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: textEnvironmentURL)
            for artifact in result.artifacts {
                let artifactURL = temporary.appendingPathComponent(artifact.entry.safeFilename)
                try artifact.bytes.write(to: artifactURL, options: .atomic)
                try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: artifactURL)
            }
            if fileManager.fileExists(atPath: directory.path) {
                let existing = try loadUnlocked(id: id, planSHA256: plan.planSHA256)
                guard existing?.0 == plan, existing?.1 == result else {
                    throw AssetLabelLifecycleFailureV1.publicationMismatch
                }
                try fileManager.removeItem(at: temporary)
                return
            }
            try fileManager.moveItem(at: temporary, to: directory)
            try ProtectedFilePolicyV1.verify(.scratch, at: directory)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    func load(
        id: LocalJobIDV1,
        planSHA256: String
    ) throws -> (AssetLabelGenerationPlanV1, LabelProjectionResultV1)? {
        lock.lock(); defer { lock.unlock() }
        return try loadUnlocked(id: id, planSHA256: planSHA256)
    }

    func discard(id: LocalJobIDV1) throws {
        lock.lock(); defer { lock.unlock() }
        let directory = directoryURL(id)
        if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
    }

    private func loadUnlocked(
        id: LocalJobIDV1,
        planSHA256: String
    ) throws -> (AssetLabelGenerationPlanV1, LabelProjectionResultV1)? {
        let directory = directoryURL(id)
        guard fileManager.fileExists(atPath: directory.path) else { return nil }
        try ProtectedFilePolicyV1.verify(.scratch, at: directory)
        let plan = try AssetLabelCanonicalCodecV1.decode(
            AssetLabelGenerationPlanV1.self,
            from: try boundedStagingData(
                at: directory.appendingPathComponent("plan.json"),
                maximumBytes: Int64(AssetLabelCanonicalCodecV1.maximumCanonicalByteCount)
            )
        )
        let manifest = try AssetLabelCanonicalCodecV1.decode(
            LabelArtifactManifestV1.self,
            from: try boundedStagingData(
                at: directory.appendingPathComponent("manifest.json"),
                maximumBytes: Int64(AssetLabelCanonicalCodecV1.maximumCanonicalByteCount)
            )
        )
        let nativeTextEnvironment = try AssetLabelCanonicalCodecV1.decode(
            AssetLabelNativeTextEnvironmentV1.self,
            from: try boundedStagingData(
                at: directory.appendingPathComponent("native-text-environment.json"),
                maximumBytes: Int64(AssetLabelCanonicalCodecV1.maximumCanonicalByteCount)
            )
        )
        guard plan.planSHA256 == planSHA256, manifest.planSHA256 == planSHA256 else {
            throw AssetLabelLifecycleFailureV1.publicationMismatch
        }
        let artifacts = try manifest.entries.map { entry in
            let bytes = try boundedStagingData(
                at: directory.appendingPathComponent(entry.safeFilename),
                maximumBytes: AssetLabelLimitsV1.maximumBytes(for: entry.kind)
            )
            let artifact = try LabelProjectedArtifactV1(
                kind: entry.kind,
                safeFilename: entry.safeFilename,
                mediaType: entry.mediaType,
                bytes: bytes,
                itemCount: entry.itemCount
            )
            guard artifact.entry == entry else { throw AssetLabelContractFailureV1.invalidDigest }
            return artifact
        }
        return (
            plan,
            try LabelProjectionResultV1(
                plan: plan,
                artifacts: artifacts,
                nativeTextEnvironment: nativeTextEnvironment
            )
        )
    }

    private func directoryURL(_ id: LocalJobIDV1) -> URL {
        rootURL.appendingPathComponent(id.rawValue.uuidString.lowercased(), isDirectory: true)
    }

    private func boundedStagingData(
        at url: URL,
        maximumBytes: Int64
    ) throws -> Data {
        try ProtectedFilePolicyV1.verify(.stagingFile, at: url)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              let count = values.fileSize,
              count > 0,
              Int64(count) <= maximumBytes else {
            throw AssetLabelContractFailureV1.limitExceeded
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count == count else { throw AssetLabelLifecycleFailureV1.publicationMismatch }
        return data
    }
}

@MainActor final class AssetLabelLifecycleAdapterV1 {
    let coordinator: AssetLabelCoordinatorV1
    let renderer: AssetLabelExistingRendererAdapterV1
    private let authority: any AssetLabelAuthoritativePlanValidatingV1
    private let jobs: ResumableLocalJobRunnerV1
    private let artifacts: AssetLabelArtifactOperationsV1

    init(
        authority: any AssetLabelAuthoritativePlanValidatingV1,
        writer: any AssetLabelCanonicalWorkspaceWritingV1,
        query: any AcceptedLabelGenerationSnapshotQueryingV1,
        jobs: ResumableLocalJobRunnerV1,
        artifacts: AssetLabelArtifactOperationsV1
    ) async {
        let renderer = AssetLabelExistingRendererAdapterV1()
        self.renderer = renderer
        self.authority = authority
        self.jobs = jobs
        self.artifacts = artifacts
        coordinator = AssetLabelCoordinatorV1(
            authority: authority,
            renderer: renderer,
            writer: writer,
            query: query
        )
        await jobs.registerAssetLabelRenderOperation { [weak self] context in
            guard let self else { throw AssetLabelLifecycleFailureV1.currentAuthorityUnavailable }
            return try await self.performRender(context)
        }
        await jobs.registerAssetLabelRenderPublisher { context in
            guard context.job.kind == .render,
                  context.pending.outputSHA256 == context.job.checkpoint.rollingOutputSHA256 else {
                throw AssetLabelLifecycleFailureV1.publicationMismatch
            }
            switch context.mode {
            case .publishOrAdopt:
                return try artifacts.publishOrAdopt(
                    context.job,
                    context.job.immutableInputSHA256,
                    context.pending.outputSHA256
                )
            case .adoptOnly:
                return try artifacts.adoptOnly(
                    context.job,
                    context.job.immutableInputSHA256,
                    context.pending.outputSHA256
                )
            }
        }
        await jobs.registerTerminalCleanup(.render) { job in
            try await artifacts.discardUncommitted(job)
            try await artifacts.discard(job.id)
        }
    }

    @discardableResult
    func enqueueValidatedPlan(
        _ plan: AssetLabelGenerationPlanV1,
        generationEpoch: GenerationEpochV1,
        createdAt: Date
    ) async throws -> ResumableLocalJobV1 {
        let projection = try await coordinator.projectValidatedPlan(plan)
        let job = try ResumableLocalJobV1.assetLabelRender(
            plan: plan,
            generationEpoch: generationEpoch,
            createdAt: createdAt
        )
        try await artifacts.stage(job.id, plan, projection)
        return try await jobs.enqueue(job)
    }

    func recoverAfterInterruption() async throws {
        try await discardRecoveredTerminalScratch()
        try await jobs.resumePending()
    }

    /// The single C45 acceptance path. A canonical GENERATED snapshot can be
    /// created only after the durable job has a receipt-bound publication or
    /// exact adoption and the existing content authority reopens matching
    /// bytes. Replaying after an effect-before-receipt interruption repeats
    /// this readback and the canonical writer's mutation-idempotent accept.
    func acceptPublishedJob(
        jobID: LocalJobIDV1,
        outputReceiptID: UUID,
        snapshotID: UUID,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        recordedBy: ActorSnapshotV1,
        recordedAt: Date
    ) async throws -> AssetLabelAcceptanceReceiptV1 {
        guard let job = try await jobs.job(id: jobID),
              job.kind == .render,
              job.state == .succeeded,
              let outputSHA256 = job.outputSHA256,
              let publicationReceipt = job.publicationReceipt,
              publicationReceipt.jobID == jobID,
              publicationReceipt.kind == .render,
              publicationReceipt.outputSHA256 == outputSHA256,
              let published = try await artifacts.publishedReadback(
                  jobID,
                  job.immutableInputSHA256,
                  outputSHA256
              ) else { throw AssetLabelLifecycleFailureV1.publicationMismatch }
        let plan = published.plan
        let projection = published.projection
        try await authority.validateCurrent(plan)
        try projection.validate(plan: plan)
        guard plan.planSHA256 == job.immutableInputSHA256,
              projection.manifest.manifestSHA256 == outputSHA256,
              plan.workspaceID == expectedRevision.workspaceID,
              recordedBy.workspaceID == plan.workspaceID else {
            throw AssetLabelLifecycleFailureV1.publicationMismatch
        }
        let publicationBinding = try AssetLabelRenderPublicationBindingV1(
            workspaceID: plan.workspaceID,
            planSHA256: plan.planSHA256,
            manifestSHA256: projection.manifest.manifestSHA256,
            outputSHA256: outputSHA256,
            publishedArtifacts: published.publishedArtifacts,
            publicationReceipt: publicationReceipt
        )
        let outputReceipt = try LabelOutputReceiptV1(
            receiptID: outputReceiptID,
            workspaceID: plan.workspaceID,
            planID: plan.planID,
            planSHA256: plan.planSHA256,
            manifestSHA256: projection.manifest.manifestSHA256,
            nativeTextEnvironment: projection.nativeTextEnvironment,
            publicationBinding: publicationBinding,
            disposition: .generated,
            generatedAt: publicationReceipt.readBackAt
        )
        let request = try await coordinator.makeAcceptanceRequest(
            snapshotID: snapshotID,
            plan: plan,
            projection: projection,
            outputReceipt: outputReceipt,
            activationDecision: .enabledBoundedLocalOnly,
            expectedRevision: expectedRevision,
            mutationID: mutationID,
            recordedBy: recordedBy,
            recordedAt: recordedAt
        )
        return try await coordinator.accept(request)
    }

    /// Cancellation and expiry use the runner's durable cancellation edge.
    /// Its descriptor-pinned terminal cleanup targets the exact
    /// `asset-label-render/<jobID>` directory used by durableStaging.
    func cancelOrExpire(jobID: LocalJobIDV1) async throws {
        let job = try await jobs.requestCancellation(id: jobID)
        if job.state.isTerminal { try await artifacts.discard(jobID) }
    }

    func deleteWorkspaceArtifacts(workspaceID: WorkspaceID) async throws {
        try await jobs.removeJobs(workspaceID: workspaceID.rawValue)
        try await artifacts.removePublishedWorkspace(workspaceID)
    }

    /// Ordinary asset deletion removes the complete multi-asset output for
    /// every accepted plan containing that asset. It does not delete or alter
    /// any other accepted output, asset, or locator.
    func deletePublishedOutputs(
        containingAssetID assetID: UUID,
        acceptedSnapshots: [AcceptedLabelGenerationSnapshotV1]
    ) async throws {
        var selected: [AssetLabelRenderPublicationBindingV1] = []
        var seen = Set<LocalJobIDV1>()
        for snapshot in acceptedSnapshots {
            try snapshot.validate()
            guard snapshot.disposition == .activeSourceWorkspace,
                  snapshot.plan.items.contains(where: { $0.assetID == assetID }) else {
                continue
            }
            let binding = snapshot.outputReceipt.publicationBinding
            try binding.validate()
            guard binding.workspaceID == snapshot.workspaceID,
                  binding.planSHA256 == snapshot.plan.planSHA256,
                  binding.manifestSHA256 == snapshot.manifest.manifestSHA256 else {
                throw AssetLabelLifecycleFailureV1.publicationMismatch
            }
            if seen.insert(binding.jobID).inserted { selected.append(binding) }
        }
        for binding in selected.sorted(by: {
            $0.jobID.rawValue.uuidString < $1.jobID.rawValue.uuidString
        }) {
            try await deletePublishedOutput(
                publicationBinding: binding,
                activeWorkspaceID: binding.workspaceID
            )
        }
    }

    /// Receipt-replay seam for a recoverable canonical deletion cleanup.
    func deletePublishedOutput(
        publicationBinding: AssetLabelRenderPublicationBindingV1,
        activeWorkspaceID: WorkspaceID
    ) async throws {
        try publicationBinding.validate()
        guard publicationBinding.workspaceID == activeWorkspaceID else {
            throw AssetLabelLifecycleFailureV1.publicationMismatch
        }
        try await artifacts.removePublishedOutput(publicationBinding)
    }

    func reconcileAfterRestore() async throws {
        try await discardRecoveredTerminalScratch()
        try await jobs.resumePending()
    }

    /// Exact regeneration is available only when the current native shaping
    /// engine, OS build, and every font program selected for this plan match
    /// the accepted environment receipt. Unavailable font identity fails
    /// closed to blocked reprint rather than claiming byte stability.
    func reprintEligibility(
        for snapshot: AcceptedLabelGenerationSnapshotV1,
        currentBindings: [AssetLabelCurrentBindingV1]
    ) throws -> LabelReprintEligibilityV1 {
        try snapshot.validate()
        let currentEnvironment = try? DeterministicPDFRendererV1
            .assetLabelNativeTextEnvironment(for: snapshot.plan)
        let context = try AssetLabelReprintContextV1(
            templateRelease: try snapshot.plan.template.reference,
            rendererRelease: snapshot.plan.template.rendererRelease,
            nativeTextEnvironment: currentEnvironment,
            currentBindings: currentBindings
        )
        return try coordinator.reprintEligibility(for: snapshot, context: context)
    }

    func eraseAllArtifacts() async throws {
        try await jobs.eraseAll()
        try await artifacts.eraseAllPublished()
    }

    private func discardRecoveredTerminalScratch() async throws {
        for job in try await jobs.jobs(workspaceID: nil)
            where job.kind == .render && job.state.isTerminal {
            try await artifacts.discardUncommitted(job)
            try await artifacts.discard(job.id)
        }
    }

    func discardTerminalScratch(jobID: LocalJobIDV1) async throws {
        guard let job = try await jobs.job(id: jobID), job.state.isTerminal else {
            throw LocalJobValidationFailureV1.invalidTransition
        }
        try await artifacts.discard(jobID)
        try await jobs.removeTerminal(id: jobID)
    }

    private func performRender(
        _ context: ResumableLocalJobExecutionContextV1
    ) async throws -> ResumableLocalJobResultV1 {
        let job = context.job
        guard job.kind == .render,
              let staged = try await artifacts.load(job.id, job.immutableInputSHA256) else {
            throw AssetLabelLifecycleFailureV1.projectionNotStaged
        }
        let (plan, result) = staged
        guard plan.planSHA256 == job.immutableInputSHA256 else {
            throw AssetLabelLifecycleFailureV1.publicationMismatch
        }
        try await authority.validateCurrent(plan)
        try result.validate(plan: plan)
        try await context.cancellationBoundary()
        for checkpoint in AssetLabelRenderCheckpointV1.allCases
            .filter({ $0.completedUnitCount > job.checkpoint.completedUnitCount }) {
            try await context.checkpoint(checkpoint.localJobCheckpoint(jobID: job.id,
                                                                        rollingSHA256: result.manifest.manifestSHA256))
            try await context.cancellationBoundary()
        }
        try await context.publicationBoundary()
        return ResumableLocalJobResultV1(
            outputSHA256: result.manifest.manifestSHA256,
            completedUnitCount: AssetLabelRenderCheckpointV1.totalUnitCount
        )
    }

    static let backupRestoresAcceptedManifestOnly = true
    static let restoreRebuildsOrAdoptsDerivedArtifacts = true
    static let deleteRemovesOwnedPublishedArtifacts = true
    static let eraseRemovesJobsAndScratch = true
    static let searchIndexesManifestMetadataOnly = true
    static let replayNeverClaimsPrintOrDelivery = true
    static let migrationPreservesAcceptedManifestOnly = true
}
