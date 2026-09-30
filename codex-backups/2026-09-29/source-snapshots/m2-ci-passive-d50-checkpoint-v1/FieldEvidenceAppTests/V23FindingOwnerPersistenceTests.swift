import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

/// These fixtures exercise row storage only. Constructed endpoint references
/// confer no receipt, writer, restore or production-enrollment authority.
@MainActor
final class V23FindingOwnerPersistenceTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)
    private func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "CF490000-0000-4000-8000-%012d", slot))!
    }
    private var workspace: WorkspaceID { WorkspaceID(rawValue: id(1)) }

    private func endpoint(_ slot: Int) throws -> FindingRelationshipEndpointReferenceV1 {
        let revision = try FindingOwnerRevisionReferenceV1(workspaceID: workspace,
            kind: .finding, ownerID: id(slot), ownerRevision: 1, recordSHA256: digest)
        let acceptance = try FindingAcceptedMutationReferenceV1(workspaceID: workspace,
            generationID: id(2), mutationID: MutationIDV1(rawValue: id(slot + 100)),
            envelopeSHA256: digest, receiptSHA256: String(repeating: "b", count: 64))
        let selected = try FindingSelectedOwnerReferenceV1(original: revision, selected: revision,
            originalAcceptance: acceptance, selectedAcceptance: acceptance)
        return try FindingRelationshipEndpointReferenceV1(workID: "finding.\(slot)",
            workRevision: 0, owner: .finding(selected))
    }

    private func record(_ kind: FindingOwnerKindV1, prior: FindingOwnerRecordV1? = nil,
                        summary: String = "Observed leak") throws -> FindingOwnerRecordV1 {
        let revision = (prior?.ownerRevision ?? 0) + 1
        let mutation = try MutationIDV1(rawValue: id(20 + Int(revision)))
        let actor = try LocalActorReferenceV1(actorReferenceID: id(10), workspaceID: workspace,
                                             displayName: "Recorder")
        let snapshot = try ActorSnapshotV1(snapshotID: id(11), workspaceID: workspace,
            actor: actor, responsibility: .recordedBy, displayNameAtTime: "Recorder",
            capturedAt: Date(timeIntervalSince1970: 0))
        let origin = try prior?.origin ?? FindingOwnerOriginIdentityV1(workspaceID: workspace,
            kind: kind, ownerID: id(30), creationMutationID: mutation)
        var facts: FindingOwnedFactsV1?
        var relation: FindingOwnedRelationshipV1?
        switch kind {
        case .finding:
            let finding = try FindingV1(findingID: "finding.one", revision: 0,
                severity: FindingSeverityBindingV1(severityID: "medium",
                    severityScaleReleaseID: "scale.one", severityScaleSHA256: digest),
                categoryID: "leak",
                subject: FindingSubjectV1(subjectKindID: "asset", subjectID: "subject.one", subjectRevision: 0),
                source: FindingSourceV1(kind: .humanObservation, sourceID: "observation.one", sourceRevision: 0),
                summary: summary)
            let lifecycle = try FindingLifecycleV1(findingID: finding.findingID, transitions: [])
            var dispositions = prior?.finding?.evidence.operationalDispositionEvents ?? []
            if prior != nil {
                let previous = dispositions.last
                let dispositionRevision = dispositions.count + 1
                dispositions.append(try OperationalDispositionEventV1(
                    eventID: "disposition.\(dispositionRevision)", subjectID: "subject.one",
                    findingID: finding.findingID, findingRevision: finding.revision,
                    evidenceRevisionIDs: [], expectedDispositionRevision: dispositionRevision - 1,
                    resultingDispositionRevision: dispositionRevision, mutationID: "disposition-mutation.\(dispositionRevision)",
                    state: .restrictedUseRecorded, actorID: "actor.one", authority: "Operator",
                    reason: "Recorded restriction", effectiveAt: "2026-09-22T12:00:00Z",
                    supersedesEventID: previous?.eventID))
            }
            facts = try FindingOwnedFactsV1(evidence: FindingLifecycleCanonicalEvidenceV1(
                finding: finding, lifecycle: lifecycle, operationalDispositionEvents: dispositions))
        case .relationship:
            let source = try endpoint(31)
            let candidate = try endpoint(32)
            let suggestion = try RelatedWorkSuggestionV1(sourceWorkID: source.workID,
                sourceWorkRevision: source.workRevision, candidateWorkID: candidate.workID,
                candidateWorkRevision: candidate.workRevision, subjectID: "subject.one",
                categoryID: "leak", policySHA256: digest, reason: "Possible related work")
            let relationship = try WorkRelationshipV1(relationshipID: "relationship.one",
                sourceWorkID: source.workID, sourceWorkRevision: source.workRevision,
                targetWorkID: candidate.workID, targetWorkRevision: candidate.workRevision,
                kind: .duplicateOf, direction: .directed, reason: "Confirmed duplicate",
                actorID: "actor.one", mutationID: "relationship-mutation.one",
                createdAt: "2026-09-22T12:00:00Z")
            let decision = try WorkRelationshipDecisionV1(decisionID: "decision.one", suggestion: suggestion,
                expectedDecisionRevision: 0, resultingDecisionRevision: 1, decision: .confirm,
                relationshipID: relationship.relationshipID, actorID: "actor.one", reason: "Confirmed duplicate",
                mutationID: "decision-mutation.one", effectiveAt: "2026-09-22T12:00:00Z")
            var decisions = prior?.relationship?.decisions ?? [decision]
            if prior != nil {
                let decisionRevision = decisions.count + 1
                decisions.append(try WorkRelationshipDecisionV1(decisionID: "decision.\(decisionRevision)",
                    suggestion: suggestion, expectedDecisionRevision: decisionRevision - 1,
                    resultingDecisionRevision: decisionRevision, decision: .removeRelation,
                    relationshipID: relationship.relationshipID, actorID: "actor.one",
                    reason: "Connection removed", mutationID: "decision-mutation.\(decisionRevision)",
                    effectiveAt: "2026-09-22T12:00:00Z"))
            }
            relation = try FindingOwnedRelationshipV1(suggestion: suggestion, source: source,
                candidate: candidate, relationship: relationship, decisions: decisions)
        }
        return try FindingOwnerRecordV1(workspaceID: workspace, kind: kind, ownerID: id(30),
            ownerRevision: revision, predecessor: prior?.reference, mutationID: mutation,
            recordedBy: snapshot, recordedAt: Date(timeIntervalSince1970: Double(revision)),
            origin: origin, finding: facts, relationship: relation)
    }

    private func withStore<T>(_ url: URL, _ body: (ModelContext) throws -> T) throws -> T {
        try autoreleasepool {
            let schema = Schema([FindingOwnerRevisionRowV1.self])
            let configuration = ModelConfiguration("FindingOwnerRows", schema: schema, url: url,
                                                   allowsSave: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [configuration])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            return try body(context)
        }
    }

    func testBothKindsBindCanonicalBytesAndDistinctRowIdentity() throws {
        var keys = Set<String>()
        for kind in FindingOwnerKindV1.allCases {
            let value = try record(kind)
            let row = try FindingOwnerRevisionRowV1(value)
            XCTAssertEqual(try row.value(), value)
            XCTAssertEqual(row.canonicalData, try FindingOwnerCanonicalCodecV1.encode(value))
            XCTAssertEqual(row.recordSHA256, try value.reference.recordSHA256)
            let expected = "cf490000-0000-4000-8000-000000000001|\(kind.rawValue)|cf490000-0000-4000-8000-000000000030|00000000000000000001"
            XCTAssertEqual(row.rowID, expected)
            XCTAssertTrue(keys.insert(row.rowID).inserted)
        }
        XCTAssertEqual(keys.count, 2)
    }

    func testEveryDuplicatedColumnRejectsMismatchForBothKinds() throws {
        let mutations: [(FindingOwnerRevisionRowV1) -> Void] = [
            { $0.rowID += "-wrong" },
            { $0.workspaceID = self.id(90) },
            { $0.ownerKind = "unknown" },
            { $0.ownerID = self.id(91) },
            { $0.ownerRevision = 9 },
            { $0.predecessorSHA256 = self.digest },
            { $0.mutationID = self.id(92) },
            { $0.recordSHA256 = String(repeating: "c", count: 64) }
        ]
        for kind in FindingOwnerKindV1.allCases {
            let value = try record(kind)
            for (index, mutate) in mutations.enumerated() {
                let row = try FindingOwnerRevisionRowV1(value)
                mutate(row)
                XCTAssertThrowsError(try row.value(), "\(kind.rawValue) column \(index)") { error in
                    guard case FindingOwnerPersistenceFailureV1.corruptRow = error else {
                        return XCTFail("Expected row disagreement, received \(error)")
                    }
                }
            }
        }
    }

    func testPredecessorDigestCannotBeDroppedOrReplaced() throws {
        for kind in FindingOwnerKindV1.allCases {
            let first = try record(kind)
            let second = try record(kind, prior: first)
            try second.validateAppendOnlySuccessor(of: first)
            let row = try FindingOwnerRevisionRowV1(second)
            XCTAssertEqual(row.predecessorSHA256, first.recordSHA256)
            XCTAssertEqual(try row.value(), second)
            row.predecessorSHA256 = nil
            XCTAssertThrowsError(try row.value())
            row.predecessorSHA256 = String(repeating: "d", count: 64)
            XCTAssertThrowsError(try row.value())
        }
    }

    func testMalformedAndValidDivergentCanonicalPayloadsAreRejected() throws {
        let original = try record(.finding)
        let divergent = try record(.finding, summary: "Different immutable fact")
        let otherKind = try record(.relationship)
        let originalBytes = try FindingOwnerCanonicalCodecV1.encode(original)
        let alteredPayloads: [Data] = [
            Data(), Data("{}".utf8), originalBytes + Data(" ".utf8),
            try FindingOwnerCanonicalCodecV1.encode(divergent),
            try FindingOwnerCanonicalCodecV1.encode(otherKind)
        ]
        for bytes in alteredPayloads {
            let row = try FindingOwnerRevisionRowV1(original)
            row.canonicalData = bytes
            XCTAssertThrowsError(try row.value())
        }
    }

    func testFileBackedSwiftDataReopenRetainsBothKindsAndRevisions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("finding.store")
        let finding = try record(.finding)
        let relationship = try record(.relationship)
        let nextFinding = try record(.finding, prior: finding)
        let nextRelationship = try record(.relationship, prior: relationship)
        try nextFinding.validateAppendOnlySuccessor(of: finding)
        try nextRelationship.validateAppendOnlySuccessor(of: relationship)
        let expected = [finding, nextFinding, relationship, nextRelationship]
        var expectedBytes: [String: Data] = [:]
        for value in expected {
            let key = FindingOwnerRevisionRowV1.rowID(workspaceID: value.workspaceID, kind: value.kind,
                                                     ownerID: value.ownerID, revision: value.ownerRevision)
            expectedBytes[key] = try FindingOwnerCanonicalCodecV1.encode(value)
        }
        try withStore(url) { context in
            for value in expected { context.insert(try FindingOwnerRevisionRowV1(value)) }
            try context.save()
        }
        try withStore(url) { context in
            let rows = try context.fetch(FetchDescriptor<FindingOwnerRevisionRowV1>())
            XCTAssertEqual(rows.count, 4)
            XCTAssertEqual(Set(rows.map(\.rowID)), Set(expectedBytes.keys))
            for row in rows {
                XCTAssertEqual(row.canonicalData, expectedBytes[row.rowID])
                XCTAssertTrue(expected.contains(try row.value()))
            }
            let tampered = try XCTUnwrap(rows.first { $0.ownerKind == "finding" && $0.ownerRevision == 1 })
            tampered.recordSHA256 = String(repeating: "e", count: 64)
            try context.save()
        }
        try withStore(url) { context in
            let rows = try context.fetch(FetchDescriptor<FindingOwnerRevisionRowV1>())
            let tampered = try XCTUnwrap(rows.first { $0.ownerKind == "finding" && $0.ownerRevision == 1 })
            XCTAssertThrowsError(try tampered.value())
            for row in rows where row.rowID != tampered.rowID { _ = try row.value() }
        }
    }
}
