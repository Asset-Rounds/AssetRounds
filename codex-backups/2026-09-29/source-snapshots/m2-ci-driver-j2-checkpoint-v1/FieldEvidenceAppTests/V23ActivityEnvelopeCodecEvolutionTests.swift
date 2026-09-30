import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Literal pre-evolution bytes are retained from an audited native original.
/// Never regenerate expected bytes with the codec under test.
@MainActor
final class V23ActivityEnvelopeCodecEvolutionTests: XCTestCase {
    private struct Corpus: Decodable {
        let schemaVersion: Int
        let originalRunID: UInt64
        let sourceHead: String
        let rootAuditSHA256: String
        let records: [Record]
    }

    private struct Record: Decodable {
        let path: String
        let sha256: String
        let base64: String
    }

    // Filled only from the sealed original, after successful native extraction.
    private let expectedRootAuditSHA256 = "6A1CC8B21279CE6A0E386D1D2B0EAF529385D69F2C254BD5D9FF2D0A34374E9D"
    private let codecCases: [String] = [
        "INSTALLATION/INTERNAL/c47-output-scope-v1",
        "INSTALLATION/CUSTOMER_SAFE/c47-output-scope-v1",
        "INSTALLATION/CUSTOMER_SAFE/c47-output-scope-v2",
        "PUNCH_REVIEW/INTERNAL/c47-output-scope-v1",
        "PUNCH_REVIEW/CUSTOMER_SAFE/c47-output-scope-v1",
        "PUNCH_REVIEW/CUSTOMER_SAFE/c47-output-scope-v2"
    ]
    private let codecFiles = [
        "activity-envelope-v2.json", "activity-archive-v36.json",
        "completed-snapshot-v2.json", "fixture-manifest.json"
    ]
    private let mutationFiles = [
        "activity-mutation-v2.json", "workspace-command-v1.json",
        "workspace-request-v1.json", "fixture-manifest.json"
    ]

    private func decoder() -> JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .millisecondsSince1970
        return value
    }

    private func loadCorpus() throws -> [String: Data] {
        let bundle = Bundle(for: Self.self)
        let name = "V23ActivityLegacyCodecCorpusV1"
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/V23/Activities")
                ?? bundle.url(forResource: name, withExtension: "json")
        )
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.originalRunID, 35723712558)
        XCTAssertEqual(corpus.sourceHead, "beaa8f487f0a3cf3267e7465a6195a7d844e8d6c")
        XCTAssertEqual(corpus.rootAuditSHA256, expectedRootAuditSHA256)
        var expected: Set<String> = []
        for caseID in codecCases {
            for filename in codecFiles {
                expected.insert("codec/\(caseID)/\(filename)")
            }
        }
        for caseID in ["unfinished", "completed"] {
            for filename in mutationFiles {
                expected.insert("mutations/\(caseID)/\(filename)")
            }
        }
        XCTAssertEqual(corpus.records.count, 32)
        XCTAssertEqual(Set(corpus.records.map(\.path)), expected)
        var result: [String: Data] = [:]
        for record in corpus.records {
            XCTAssertNil(result[record.path], "Duplicate frozen record")
            let data = try XCTUnwrap(Data(base64Encoded: record.base64))
            XCTAssertEqual(data.base64EncodedString(), record.base64)
            XCTAssertEqual(KernelCanonicalHashV1.sha256(data).uppercased(), record.sha256)
            result[record.path] = data
        }
        return result
    }

    func testLegacyEnvelopeArchiveSnapshotBytesRemainExact() throws {
        let corpus = try loadCorpus()
        for caseID in codecCases {
            let prefix = "codec/" + caseID + "/"
            let envelopeBytes = try XCTUnwrap(corpus[prefix + "activity-envelope-v2.json"])
            let archiveBytes = try XCTUnwrap(corpus[prefix + "activity-archive-v36.json"])
            let snapshotBytes = try XCTUnwrap(corpus[prefix + "completed-snapshot-v2.json"])
            let manifest = try decoder().decode([String: String].self,
                from: XCTUnwrap(corpus[prefix + "fixture-manifest.json"]))
            let envelope = try decoder().decode(ActivitySessionEnvelopeV2.self, from: envelopeBytes)
            try envelope.validateForRead()
            XCTAssertEqual(envelope.schemaVersion, 2)
            XCTAssertEqual(envelope.envelopeSHA256, manifest["envelopeSemanticSHA256"])
            XCTAssertEqual(try envelope.canonicalData(), envelopeBytes)
            let row = try ActivitySessionEnvelopeRow(envelope)
            XCTAssertEqual(try row.value(), envelope)
            XCTAssertEqual(row.canonicalData, envelopeBytes)
            let archive = try decoder().decode(V36BackupActivityContractRecordV2.self, from: archiveBytes)
            XCTAssertEqual(try archive.envelopeValue(), envelope)
            XCTAssertEqual(archive.canonicalData, envelopeBytes)
            XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(archive), archiveBytes)
            let snapshot = try CompletedActivitySnapshotCanonicalCodecV2.decode(snapshotBytes)
            XCTAssertEqual(try CompletedActivitySnapshotCanonicalCodecV2.encode(snapshot), snapshotBytes)
            XCTAssertEqual(snapshot.snapshotSHA256, envelope.completedSnapshotReference?.snapshotSHA256)
        }
    }

    func testLegacyMutationCommandRequestBytesRemainExact() throws {
        let corpus = try loadCorpus()
        for caseID in ["unfinished", "completed"] {
            let prefix = "mutations/" + caseID + "/"
            let mutationBytes = try XCTUnwrap(corpus[prefix + "activity-mutation-v2.json"])
            let commandBytes = try XCTUnwrap(corpus[prefix + "workspace-command-v1.json"])
            let requestBytes = try XCTUnwrap(corpus[prefix + "workspace-request-v1.json"])
            let manifest = try decoder().decode([String: String].self,
                from: XCTUnwrap(corpus[prefix + "fixture-manifest.json"]))
            let mutation = try decoder().decode(ActivityContractMutationV2.self, from: mutationBytes)
            try mutation.validate()
            XCTAssertEqual(mutation.schemaVersion, 2)
            XCTAssertEqual(mutation.mutationSHA256, manifest["mutationSHA256"])
            XCTAssertEqual(mutation.successorEnvelope.envelopeSHA256, manifest["successorEnvelopeSHA256"])
            XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(mutation), mutationBytes)
            let command = try decoder().decode(WorkspaceCommandV1.self, from: commandBytes)
            guard case .applyActivityContract(let embeddedMutation) = command else {
                XCTFail("Frozen command must retain its original activity operation")
                return
            }
            XCTAssertEqual(embeddedMutation, mutation)
            XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(command), commandBytes)
            let request = try decoder().decode(WorkspaceMutationRequestV1.self, from: requestBytes)
            XCTAssertEqual(request.mutationID, mutation.mutationID)
            XCTAssertEqual(request.expectedRevision, mutation.expectedRevision)
            XCTAssertEqual(request.command, command)
            XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(request), requestBytes)
            if caseID == "unfinished" {
                XCTAssertNil(mutation.completedSnapshotReference)
                XCTAssertNil(mutation.successorEnvelope.completedSnapshotReference)
            } else {
                XCTAssertNotNil(mutation.completedSnapshotReference)
                XCTAssertEqual(mutation.completedSnapshotReference, mutation.successorEnvelope.completedSnapshotReference)
            }
        }
    }

    func testLegacyEnvelopeRowsRejectCorruptMirrorsAndBytes() throws {
        let corpus = try loadCorpus()
        for caseID in codecCases {
            let bytes = try XCTUnwrap(corpus["codec/" + caseID + "/activity-envelope-v2.json"])
            let envelope = try decoder().decode(ActivitySessionEnvelopeV2.self, from: bytes)
            let wrongMirror = try ActivitySessionEnvelopeRow(envelope)
            wrongMirror.revision += 1
            XCTAssertThrowsError(try wrongMirror.value())
            let wrongDigest = try ActivitySessionEnvelopeRow(envelope)
            wrongDigest.envelopeSHA256 = String(repeating: "0", count: 64)
            XCTAssertThrowsError(try wrongDigest.value())
            let noncanonicalBytes = try ActivitySessionEnvelopeRow(envelope)
            noncanonicalBytes.canonicalData.append(0x20)
            XCTAssertThrowsError(try noncanonicalBytes.value())
            var changed = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            changed["title"] = "Tampered legacy activity title"
            let changedBytes = try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys])
            XCTAssertThrowsError(try decoder().decode(ActivitySessionEnvelopeV2.self,
                from: changedBytes).validateForRead())
        }
    }

    private func legacyCompletion() throws -> ActivityContractMutationV2 {
        let corpus = try loadCorpus()
        let bytes = try XCTUnwrap(corpus["mutations/completed/activity-mutation-v2.json"])
        return try decoder().decode(ActivityContractMutationV2.self, from: bytes)
    }

    private func fileReference(_ slot: Int = 1) throws -> ActivityCompletedFileReferenceV1 {
        // Deliberate metadata-only fixture: no existence or file-readback claim.
        try ActivityCompletedFileReferenceV1(
            outputID: XCTUnwrap(UUID(uuidString: String(format: "73000000-0000-4000-8000-%012d", slot))),
            fileSHA256: String(repeating: slot == 1 ? "a" : "b", count: 64)
        )
    }

    private func copied(
        _ source: ActivitySessionEnvelopeV2, version: Int,
        file: ActivityCompletedFileReferenceV1?, state: ActivityStateV2? = nil,
        revision: UInt64? = nil, predecessor: String? = nil
    ) throws -> ActivitySessionEnvelopeV2 {
        try ActivitySessionEnvelopeV2(
            activityID: source.activityID, workspaceID: source.workspaceID, kind: source.kind,
            state: state ?? source.state, reviewState: source.reviewState,
            subjectID: source.subjectID, title: source.title, readiness: source.readiness,
            readinessPolicy: source.readinessPolicy, variations: source.variations,
            amendment: source.amendment, currentBasisReference: source.currentBasisReference,
            installationCloseout: source.installationCloseout, punchReviewCloseout: source.punchReviewCloseout,
            completedSnapshotReference: source.completedSnapshotReference,
            startedAt: source.startedAt, finalizedAt: source.finalizedAt,
            revision: revision ?? source.revision, mutationID: source.mutationID,
            predecessorEnvelopeSHA256: predecessor ?? source.predecessorEnvelopeSHA256,
            schemaVersion: version, completedFileReference: file
        )
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func bytes(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    func testSchema3RoundTripBindsSeparateTypedAndFileDigests() throws {
        let legacy = try legacyCompletion().successorEnvelope
        let reference = try fileReference()
        let value = try copied(legacy, version: 3, file: reference)
        let encoded = try value.canonicalData()
        XCTAssertEqual(try decoder().decode(ActivitySessionEnvelopeV2.self, from: encoded), value)
        XCTAssertEqual(try decoder().decode(ActivitySessionEnvelopeV2.self, from: encoded).canonicalData(), encoded)
        XCTAssertEqual(ActivitySessionEnvelopeV2.schemaVersion, 2)
        XCTAssertEqual(value.completedSnapshotReference, legacy.completedSnapshotReference)
        XCTAssertNotEqual(reference.fileSHA256, value.completedSnapshotReference?.snapshotSHA256)
        XCTAssertNotEqual(value.envelopeSHA256, legacy.envelopeSHA256)
        XCTAssertEqual(try ActivitySessionEnvelopeRow(value).value(), value)
        var independentlyHashed = try json(encoded)
        independentlyHashed.removeValue(forKey: "envelopeSHA256")
        XCTAssertEqual(KernelCanonicalHashV1.sha256(try bytes(independentlyHashed)), value.envelopeSHA256)
        for field in ["completedSnapshotReference", "completedFileReference"] {
            var changed = try json(encoded)
            var nested = try XCTUnwrap(changed[field] as? [String: Any])
            nested[field == "completedFileReference" ? "fileSHA256" : "snapshotSHA256"] = String(repeating: "c", count: 64)
            changed[field] = nested
            XCTAssertThrowsError(try decoder().decode(ActivitySessionEnvelopeV2.self, from: bytes(changed)))
        }
        let differentFile = try copied(legacy, version: 3, file: fileReference(2))
        XCTAssertEqual(differentFile.completedSnapshotReference, value.completedSnapshotReference)
        XCTAssertNotEqual(differentFile.envelopeSHA256, value.envelopeSHA256)
    }

    func testClosedFileReferenceRejectsUnknownFieldsVersionsAndNoncanonicalIdentity() throws {
        let reference = try fileReference()
        let original = try json(WorkspaceMutationCanonicalV1.data(reference))
        XCTAssertEqual(Set(original.keys), Set(["schemaVersion", "outputID", "fileFormat", "fileVersion", "relativePath", "fileSHA256"]))
        let hostile: [(String, Any)] = [
            ("schemaVersion", 2), ("fileVersion", 2), ("fileFormat", "COMPLETED_ACTIVITY_SNAPSHOT_V2"),
            ("outputID", "00000000-0000-0000-0000-000000000000"),
            ("relativePath", "snapshots/../outside.json"),
            ("relativePath", reference.relativePath.uppercased()),
            ("fileSHA256", String(repeating: "A", count: 64)),
            ("fileSHA256", String(repeating: "a", count: 63)),
            ("ownerWorkspaceID", UUID().uuidString)
        ]
        for (field, replacement) in hostile {
            var object = original; object[field] = replacement
            XCTAssertThrowsError(try decoder().decode(ActivityCompletedFileReferenceV1.self, from: bytes(object)), field)
        }
        for field in original.keys {
            var object = original; object.removeValue(forKey: field)
            XCTAssertThrowsError(try decoder().decode(ActivityCompletedFileReferenceV1.self, from: bytes(object)), field)
        }
        XCTAssertThrowsError(try ActivityCompletedFileReferenceV1(
            outputID: ActivityContractValidationV2.zeroUUID, fileSHA256: reference.fileSHA256))
    }

    func testEnvelopeRejectsUnknownSchemasReservedLegacyFieldAndIncompleteSchema3() throws {
        let mutation = try legacyCompletion()
        let legacy = mutation.successorEnvelope
        let reference = try fileReference()
        let value = try copied(legacy, version: 3, file: reference)
        let oldObject = try json(legacy.canonicalData())
        let reservedValues: [Any] = [NSNull(), try json(WorkspaceMutationCanonicalV1.data(reference))]
        for reserved in reservedValues {
            var object = oldObject; object["completedFileReference"] = reserved
            XCTAssertThrowsError(try decoder().decode(ActivitySessionEnvelopeV2.self, from: bytes(object)))
        }
        for version in [0, 1, 4, 99] {
            var object = oldObject; object["schemaVersion"] = version
            XCTAssertThrowsError(try decoder().decode(ActivitySessionEnvelopeV2.self, from: bytes(object)))
        }
        for field in ["completedFileReference", "completedSnapshotReference", "finalizedAt"] {
            var object = try json(value.canonicalData()); object.removeValue(forKey: field)
            XCTAssertThrowsError(try decoder().decode(ActivitySessionEnvelopeV2.self, from: bytes(object)))
        }
        var extra = try json(value.canonicalData()); extra["unrecognizedOwner"] = "owner"
        XCTAssertThrowsError(try decoder().decode(ActivitySessionEnvelopeV2.self, from: bytes(extra)))
        XCTAssertThrowsError(try copied(legacy, version: 2, file: reference))
        XCTAssertThrowsError(try copied(legacy, version: 3, file: nil))
        let unfinished = try XCTUnwrap(mutation.predecessorEnvelope)
        XCTAssertThrowsError(try copied(unfinished, version: 3, file: reference))
        XCTAssertThrowsError(try copied(unfinished, version: 3, file: nil))
    }

    func testOnlyUnfinishedSchema2CanFinalizeIntoSchema3() throws {
        let mutation = try legacyCompletion()
        let unfinished = try XCTUnwrap(mutation.predecessorEnvelope)
        let oldFinalized = mutation.successorEnvelope
        let value = try copied(oldFinalized, version: 3, file: fileReference())
        try value.validateSuccessor(of: unfinished)
        XCTAssertEqual(value.revision, unfinished.revision + 1)
        XCTAssertEqual(value.predecessorEnvelopeSHA256, unfinished.envelopeSHA256)
        let retrofit = try copied(oldFinalized, version: 3, file: fileReference(),
            revision: oldFinalized.revision + 1, predecessor: oldFinalized.envelopeSHA256)
        XCTAssertThrowsError(try retrofit.validateSuccessor(of: oldFinalized))
        let supersededRetrofit = try copied(oldFinalized, version: 3, file: fileReference(),
            state: .superseded, revision: oldFinalized.revision + 1, predecessor: oldFinalized.envelopeSHA256)
        XCTAssertThrowsError(try supersededRetrofit.validateSuccessor(of: oldFinalized))
        let wrongParent = try copied(oldFinalized, version: 3, file: fileReference(),
            predecessor: String(repeating: "e", count: 64))
        XCTAssertThrowsError(try wrongParent.validateSuccessor(of: unfinished))
    }

    func testSchema3SupersessionRetainsWholeReferenceAndRejectsDowngrade() throws {
        let value = try copied(legacyCompletion().successorEnvelope, version: 3, file: fileReference())
        let superseded = try copied(value, version: 3, file: value.completedFileReference,
            state: .superseded, revision: value.revision + 1, predecessor: value.envelopeSHA256)
        try superseded.validateSuccessor(of: value)
        XCTAssertEqual(superseded.completedFileReference, value.completedFileReference)
        XCTAssertEqual(superseded.completedSnapshotReference, value.completedSnapshotReference)
        let changed = try copied(value, version: 3, file: fileReference(2),
            state: .superseded, revision: value.revision + 1, predecessor: value.envelopeSHA256)
        XCTAssertThrowsError(try changed.validateSuccessor(of: value))
        let downgraded = try copied(value, version: 2, file: nil,
            state: .superseded, revision: value.revision + 1, predecessor: value.envelopeSHA256)
        XCTAssertThrowsError(try downgraded.validateSuccessor(of: value))
        // Equality applies to every field, including a digest-only replacement.
        let changedDigest = try ActivityCompletedFileReferenceV1(
            outputID: XCTUnwrap(value.completedFileReference).outputID,
            fileSHA256: String(repeating: "d", count: 64))
        let rewritten = try copied(value, version: 3, file: changedDigest,
            state: .superseded, revision: value.revision + 1, predecessor: value.envelopeSHA256)
        XCTAssertThrowsError(try rewritten.validateSuccessor(of: value))
    }

    func testLegacyMutationAndGenericCommandRejectSchema3EvenWithRecomputedMutationHash() throws {
        let legacy = try legacyCompletion()
        let completed = try copied(legacy.successorEnvelope, version: 3, file: fileReference())
        XCTAssertThrowsError(try ActivityContractMutationV2(
            workspaceID: legacy.workspaceID, expectedRevision: legacy.expectedRevision,
            mutationID: legacy.mutationID, predecessorEnvelope: legacy.predecessorEnvelope,
            successorEnvelope: completed, transition: legacy.transition,
            completedSnapshotReference: legacy.completedSnapshotReference,
            installationBasisSnapshot: legacy.installationBasisSnapshot,
            installationTaskResults: legacy.installationTaskResults,
            installationAsBuiltSnapshot: legacy.installationAsBuiltSnapshot))
        var object = try json(WorkspaceMutationCanonicalV1.data(legacy))
        object["successorEnvelope"] = try json(completed.canonicalData())
        object.removeValue(forKey: "mutationSHA256")
        object["mutationSHA256"] = KernelCanonicalHashV1.sha256(try bytes(object))
        let hostile = try decoder().decode(ActivityContractMutationV2.self, from: bytes(object))
        XCTAssertThrowsError(try hostile.validate())
        XCTAssertThrowsError(try hostile.validateForCanonicalMutation())
        let request = WorkspaceMutationRequestV1(mutationID: hostile.mutationID,
            expectedRevision: hostile.expectedRevision, command: .applyActivityContract(hostile))
        XCTAssertThrowsError(try WorkspaceWriterV1.affectedIdentities(for: request.command))
        let successor = try copied(completed, version: 2, file: nil, state: .superseded,
            revision: completed.revision + 1, predecessor: completed.envelopeSHA256)
        var predecessorHostile = try json(WorkspaceMutationCanonicalV1.data(legacy))
        predecessorHostile["predecessorEnvelope"] = try json(completed.canonicalData())
        predecessorHostile["successorEnvelope"] = try json(successor.canonicalData())
        predecessorHostile.removeValue(forKey: "mutationSHA256")
        predecessorHostile["mutationSHA256"] = KernelCanonicalHashV1.sha256(try bytes(predecessorHostile))
        XCTAssertThrowsError(try decoder().decode(ActivityContractMutationV2.self,
            from: bytes(predecessorHostile)).validateForCanonicalMutation())
    }

    private func fork(_ source: ActivitySessionEnvelopeV2, slot: Int) throws -> ActivitySessionEnvelopeV2 {
        let workspace = WorkspaceID(rawValue: UUID())
        let activityID = UUID()
        let subjectID = UUID()
        let mutation = try MutationIDV1(rawValue: UUID())
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let registry = try InspectionPackageRegistryV2(packages: [package])
        let selection = try registry.bundledActivityWorkflowRelease(kind: .installation,
            packageID: ShippingIlluminatedSignAdapterV1.packageID, workspaceID: workspace)
        guard case let .installation(release) = selection.release else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        // The envelope accepts already mapped domain metadata; graph-wide restore
        // qualification remains separate. These targets are built by domain APIs.
        let basis = try InstallationBasisSnapshotV1(
            basisID: UUID(), workspaceID: workspace, activityID: activityID, subjectID: subjectID,
            workflowReleaseReference: ActivityWorkflowReleaseReferenceV2(installation: release, package: package),
            source: .noPlan(NoPlanFallbackV1(limitation: "Envelope codec Fork mapping fixture.")),
            capturedAt: XCTUnwrap(source.finalizedAt), revision: 1, mutationID: mutation)
        let sourceCloseout = try XCTUnwrap(source.installationCloseout)
        let closeout = try sourceCloseout.rebound(to: workspace, activityID: activityID,
            asBuiltSnapshotSHA256: String(repeating: slot == 1 ? "e" : "f", count: 64),
            mappedActivitySHA256: { _ in basis.basisSHA256 })
        return try source.rebound(to: workspace, activityID: activityID, subjectID: subjectID,
            revision: 1, mutationID: mutation, mappedPredecessorEnvelopeSHA256: nil,
            mappedVariations: [], mappedAmendment: nil,
            mappedCurrentBasisReference: .installation(InstallationBasisReferenceV1(basis)),
            mappedInstallationCloseout: closeout, mappedPunchReviewCloseout: nil)
    }

    func testLegacyAndSchema3ForkRepeatForkPreserveSourceAndFileIdentity() throws {
        let legacy = try legacyCompletion().successorEnvelope
        for source in [legacy, try copied(legacy, version: 3, file: fileReference())] {
            let first = try fork(source, slot: 1)
            let second = try fork(first, slot: 2)
            for target in [first, second] {
                XCTAssertEqual(target.schemaVersion, source.schemaVersion)
                XCTAssertEqual(target.completedFileReference, source.completedFileReference)
                XCTAssertNotEqual(target.workspaceID, source.workspaceID)
                XCTAssertNotEqual(target.activityID, source.activityID)
                XCTAssertNotEqual(target.envelopeSHA256, source.envelopeSHA256)
                let originalReference = try XCTUnwrap(source.completedSnapshotReference)
                let mappedReference = try XCTUnwrap(target.completedSnapshotReference)
                XCTAssertEqual(mappedReference.sourceWorkspaceID, originalReference.sourceWorkspaceID)
                XCTAssertEqual(mappedReference.sourceActivityID, originalReference.sourceActivityID)
                XCTAssertEqual(mappedReference.sourceSubjectID, originalReference.sourceSubjectID)
                XCTAssertEqual(mappedReference.sourceActivityRevision, originalReference.sourceActivityRevision)
                XCTAssertEqual(mappedReference.sourceCloseoutSHA256, originalReference.sourceCloseoutSHA256)
                XCTAssertEqual(mappedReference.snapshotSHA256, originalReference.snapshotSHA256)
                XCTAssertEqual(mappedReference.snapshotID, originalReference.snapshotID)
                XCTAssertEqual(mappedReference.snapshotRevision, originalReference.snapshotRevision)
                XCTAssertEqual(mappedReference.workspaceID, target.workspaceID)
                XCTAssertEqual(mappedReference.activityID, target.activityID)
                XCTAssertEqual(mappedReference.targetCloseoutSHA256, target.installationCloseout?.closeoutSHA256)
                XCTAssertNotEqual(mappedReference.targetCloseoutSHA256, originalReference.targetCloseoutSHA256)
                let encoded = try target.canonicalData()
                XCTAssertEqual(try decoder().decode(ActivitySessionEnvelopeV2.self, from: encoded), target)
            }
            XCTAssertNotEqual(first.installationCloseout?.closeoutSHA256, second.installationCloseout?.closeoutSHA256)
            XCTAssertNotEqual(first.envelopeSHA256, second.envelopeSHA256)
        }
    }

    func testLegacyUnknownKindRemainsReadableButNotWritable() throws {
        let mutation = try legacyCompletion()
        let seed = try ActivitySessionEnvelopeV2(
            activityID: UUID(), workspaceID: mutation.workspaceID, kind: .installation,
            state: .draft, reviewState: .notRequested, subjectID: UUID(), title: "Future kind fixture",
            readiness: [], revision: 1, mutationID: mutation.mutationID)
        var object = try json(seed.canonicalData())
        object["kind"] = "FUTURE_ACTIVITY_KIND"
        object.removeValue(forKey: "envelopeSHA256")
        object["envelopeSHA256"] = KernelCanonicalHashV1.sha256(try bytes(object))
        let encoded = try bytes(object)
        let value = try decoder().decode(ActivitySessionEnvelopeV2.self, from: encoded)
        try value.validateForRead()
        XCTAssertEqual(try value.canonicalData(), encoded)
        XCTAssertThrowsError(try value.validateForMutation())
        XCTAssertThrowsError(try ActivitySessionEnvelopeRow(value))
    }
}
