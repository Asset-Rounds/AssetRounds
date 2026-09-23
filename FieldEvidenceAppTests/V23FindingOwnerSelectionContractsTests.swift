import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Constructed values exercise intrinsic shapes and typed bindings only. They do
/// not authenticate a receipt, prove relationship completeness or enable writes.
@MainActor
final class V23FindingOwnerSelectionContractsTests: XCTestCase {
    private let a = String(repeating: "a", count: 64)
    private let b = String(repeating: "b", count: 64)
    private let c = String(repeating: "c", count: 64)
    private let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    private func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "CF470000-0000-4000-8000-%012d", slot))!
    }

    private var workspace: WorkspaceID { WorkspaceID(rawValue: id(1)) }
    private func mutation(_ slot: Int) throws -> MutationIDV1 { try MutationIDV1(rawValue: id(slot)) }

    private func acceptance(_ slot: Int = 11, workspace: WorkspaceID? = nil,
                            receipt: String? = nil) throws -> FindingAcceptedMutationReferenceV1 {
        try FindingAcceptedMutationReferenceV1(workspaceID: workspace ?? self.workspace,
            generationID: id(2), mutationID: mutation(slot), envelopeSHA256: a, receiptSHA256: receipt ?? b)
    }

    private func owner(_ slot: Int = 20, kind: FindingOwnerKindV1 = .finding,
                       revision: UInt64 = 7, workspace: WorkspaceID? = nil,
                       digest: String? = nil) throws -> FindingOwnerRevisionReferenceV1 {
        try FindingOwnerRevisionReferenceV1(workspaceID: workspace ?? self.workspace, kind: kind,
            ownerID: id(slot), ownerRevision: revision, recordSHA256: digest ?? c)
    }

    private func selectedOwner(_ slot: Int = 20, kind: FindingOwnerKindV1 = .finding,
                               revision: UInt64 = 7, digest: String? = nil) throws -> FindingSelectedOwnerReferenceV1 {
        let reference = try owner(slot, kind: kind, revision: revision, digest: digest)
        let accepted = try acceptance()
        return try FindingSelectedOwnerReferenceV1(original: reference, selected: reference,
            originalAcceptance: accepted, selectedAcceptance: accepted)
    }

    private func source() throws -> FindingActivitySourceReferenceV1 {
        let context = try FindingSourceContextV1(workspaceID: workspace, activityID: id(3),
            activityKind: .punchReview, activityRevision: 3, activitySHA256: a, taskOrScopeID: "scope-A")
        let accepted = try acceptance(12)
        return try FindingActivitySourceReferenceV1(original: context, selected: context,
            originalAcceptance: accepted, selectedAcceptance: accepted)
    }

    private func frontier(workspace: WorkspaceID? = nil, revision: UInt64 = 9,
                          entities: [WorkspaceEntityRevisionV1] = []) throws -> MutationPortableExpectedRevisionV1 {
        let expected = try WorkspaceExpectedRevisionV1(workspaceID: workspace ?? self.workspace,
            generationID: id(2), writerInstanceID: id(4), workspaceRevision: revision, entityRevisions: entities)
        return try MutationPortableExpectedRevisionV1(expected)
    }

    private func finding(_ identity: String = "finding.pump-7", revision: Int = 0) throws -> FindingV1 {
        let severity = try FindingSeverityBindingV1(severityID: "medium", severityScaleReleaseID: "scale.one",
                                                   severityScaleSHA256: a)
        let subject = try FindingSubjectV1(subjectKindID: "asset", subjectID: "pump-7", subjectRevision: 0)
        let source = try FindingSourceV1(kind: .humanObservation, sourceID: "walkdown-7", sourceRevision: 0)
        return try FindingV1(findingID: identity, revision: revision, severity: severity,
            categoryID: "leak", subject: subject, source: source, summary: "Constructed finding value")
    }

    private func recheck(findingID: String = "finding.pump-7", findingRevision: Int = 0,
                         workID: String = "work.pump-7", workRevision: Int = 0,
                         expectedRevision: Int = 0, resultingRevision: Int = 1) throws -> VerifiedRecheckV1 {
        try VerifiedRecheckV1(recheckID: "recheck.pump-7", findingID: findingID, findingRevision: findingRevision,
            correctiveWorkID: workID, correctiveWorkRevision: workRevision, evidenceRevisionIDs: ["evidence-7"],
            expectedRecheckRevision: expectedRevision, resultingRecheckRevision: resultingRevision,
            mutationID: "recheck-mutation-7", outcome: .passed, verifierActorID: "actor-7",
            verifierAuthority: "Constructed verifier", reason: "Constructed recheck",
            effectiveAt: "2026-09-22T12:00:00Z")
    }

    private func event(finding: FindingV1, sourceOverride: ChangeRequestItemReferenceV1? = nil,
                       actionSlot: Int = 30) throws -> CorrectiveActionEventV1 {
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let actor = try LocalActorReferenceV1(actorReferenceID: id(40), workspaceID: workspace, displayName: "Recorder")
        let recorder = try ActorSnapshotV1(snapshotID: id(41), workspaceID: workspace, actor: actor,
            responsibility: .recordedBy, displayNameAtTime: "Recorder", capturedAt: instant)
        let dueRule = try CorrectiveActionDueRuleV1(kind: .noDueDate)
        let priorityRule = try CorrectiveActionPriorityRuleV1(priority: .normal, dueRule: dueRule)
        let policy = try CorrectiveActionPolicyV1(releaseID: id(42), policyID: id(43), workspaceID: workspace,
            priorityRules: [priorityRule], assignmentRule: .optional, closureEvidenceRequirements: [],
            verifierRule: .notRequired, reopenTriggers: [], effectiveAt: instant, mutationID: mutation(44))
        let due = try CorrectiveActionDueCalculationV1(openedAt: instant, timeZoneIdentifier: nil,
            dueAt: nil, graceEndsAt: nil, resolvedUTCOffsetSeconds: nil)
        let source = try sourceOverride ?? finding.inspectionReviewItemReference()
        return try CorrectiveActionEventV1(eventID: id(31), actionID: id(actionSlot), workspaceID: workspace,
            source: source, policy: CorrectiveActionPolicyReferenceV1(policy), priority: .normal, state: .open,
            recorder: recorder, due: due, reason: "Constructed C14 event", occurredAt: instant, recordedAt: instant,
            mutationID: mutation(13))
    }

    private func support(event: CorrectiveActionEventV1, workID: String = "work.pump-7",
                         workRevision: Int = 0) throws -> FindingC14SupportReferenceV1 {
        let reference = try FindingCorrectiveEventReferenceV1(workspaceID: workspace, actionID: event.actionID,
            eventID: event.eventID, eventRevision: event.revision, eventSHA256: event.eventSHA256,
            acceptance: acceptance(13))
        return try FindingC14SupportReferenceV1(correctiveWorkID: workID, correctiveWorkRevision: workRevision,
                                                original: reference, selected: reference)
    }

    private func link(finding: FindingV1? = nil, owner: FindingSelectedOwnerReferenceV1? = nil,
                      support: FindingC14SupportReferenceV1? = nil,
                      recheck: VerifiedRecheckV1? = nil) throws -> ActivityFindingOwnerLinkV1 {
        let fact = try finding ?? self.finding()
        let selected = try owner ?? selectedOwner()
        var recheckReference: FindingVerifiedRecheckReferenceV1?
        if let recheck {
            recheckReference = try FindingVerifiedRecheckReferenceV1(owner: selected.selected,
                recheckID: recheck.recheckID, resultingRecheckRevision: recheck.resultingRecheckRevision,
                recheckSHA256: WorkspaceMutationCanonicalV1.sha256(recheck))
        }
        return try ActivityFindingOwnerLinkV1(findingID: fact.findingID, findingRevision: fact.revision,
            findingSHA256: WorkspaceMutationCanonicalV1.sha256(fact), owner: selected, source: source(),
            correctiveAction: support, verifiedRecheck: recheckReference)
    }

    private func selection(links: [ActivityFindingOwnerLinkV1] = [],
                           relationships: [FindingSelectedOwnerReferenceV1] = []) throws -> ActivityFindingSelectionV1 {
        try ActivityFindingSelectionV1(workspaceID: workspace, activityID: id(3), frontier: frontier(),
                                       links: links, relationshipOwners: relationships)
    }

    private func canonicalJSON(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func object<T: FindingOwnerSelectionValueV1>(_ value: T) throws -> [String: Any] {
        let bytes = try FindingOwnerSelectionCanonicalCodecV1.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private func roundTrip<T: FindingOwnerSelectionValueV1 & Equatable>(_ value: T) throws {
        let bytes = try FindingOwnerSelectionCanonicalCodecV1.encode(value)
        let decoded = try FindingOwnerSelectionCanonicalCodecV1.decode(T.self, from: bytes)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(try FindingOwnerSelectionCanonicalCodecV1.encode(decoded), bytes)
    }

    private func assertRejected<T: FindingOwnerSelectionValueV1>(_ type: T.Type, _ object: [String: Any],
                                                               file: StaticString = #filePath, line: UInt = #line) throws {
        let bytes = try canonicalJSON(object)
        XCTAssertThrowsError(try FindingOwnerSelectionCanonicalCodecV1.decode(type, from: bytes), file: file, line: line)
    }

    private func assertClosed<T: FindingOwnerSelectionValueV1>(_ value: T, keys: Set<String>,
                                                             optional: Set<String> = []) throws {
        let original = try object(value)
        XCTAssertEqual(Set(original.keys), keys)
        var unknown = original
        unknown["futureField"] = true
        try assertRejected(T.self, unknown)
        XCTAssertThrowsError(try JSONDecoder().decode(T.self, from: canonicalJSON(unknown)))
        for key in keys.subtracting(optional) {
            var missing = original
            missing.removeValue(forKey: key)
            try assertRejected(T.self, missing)
            var null = original
            null[key] = NSNull()
            try assertRejected(T.self, null)
        }
    }

    func testNineValuesRoundTripAndExposeExactClosedFields() throws {
        let fact = try finding()
        let event = try event(finding: fact)
        let support = try support(event: event)
        let link = try link(finding: fact, support: support, recheck: recheck())
        let recheck = try XCTUnwrap(link.verifiedRecheck)
        let selection = try selection(links: [link])
        try roundTrip(link.owner.selected)
        try roundTrip(link.owner.selectedAcceptance)
        try roundTrip(link.owner)
        try roundTrip(link.source)
        try roundTrip(support.selected)
        try roundTrip(support)
        try roundTrip(recheck)
        try roundTrip(link)
        try roundTrip(selection)
        try assertClosed(link.owner.selected, keys: ["workspaceID", "kind", "ownerID", "ownerRevision", "recordSHA256"])
        try assertClosed(link.owner.selectedAcceptance,
                         keys: ["workspaceID", "generationID", "mutationID", "envelopeSHA256", "receiptSHA256"])
        try assertClosed(link.owner, keys: ["original", "selected", "originalAcceptance", "selectedAcceptance"])
        try assertClosed(link.source, keys: ["original", "selected", "originalAcceptance", "selectedAcceptance"])
        try assertClosed(support.selected,
                         keys: ["workspaceID", "actionID", "eventID", "eventRevision", "eventSHA256", "acceptance"])
        try assertClosed(support, keys: ["correctiveWorkID", "correctiveWorkRevision", "original", "selected"])
        try assertClosed(recheck, keys: ["owner", "recheckID", "resultingRecheckRevision", "recheckSHA256"])
        try assertClosed(link, keys: ["findingID", "findingRevision", "findingSHA256", "owner", "source",
                                    "correctiveAction", "verifiedRecheck"], optional: ["correctiveAction", "verifiedRecheck"])
        try assertClosed(selection, keys: ["contract", "workspaceID", "activityID", "frontier", "links",
                                         "relationshipOwners", "selectionSHA256"])
        XCTAssertEqual(FindingOwnerKindV1.allCases.map(\.rawValue), ["finding", "relationship"])
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(FindingOwnerKindV1.finding), Data("\"finding\"".utf8))
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(FindingOwnerKindV1.relationship), Data("\"relationship\"".utf8))
    }

    func testLegalNonUUIDStringsStayExactAndIncumbentIDGrammarIsNotBroadened() throws {
        let fact = try finding()
        let support = try support(event: event(finding: fact))
        let link = try link(finding: fact, support: support, recheck: recheck())
        let decoded = try FindingOwnerSelectionCanonicalCodecV1.decode(ActivityFindingOwnerLinkV1.self,
            from: FindingOwnerSelectionCanonicalCodecV1.encode(link))
        XCTAssertEqual(Array(decoded.findingID.utf8), Array("finding.pump-7".utf8))
        XCTAssertEqual(decoded.correctiveAction?.correctiveWorkID, "work.pump-7")
        XCTAssertEqual(decoded.verifiedRecheck?.recheckID, "recheck.pump-7")
        XCTAssertNil(UUID(uuidString: decoded.findingID))
        XCTAssertEqual(decoded.findingRevision, 0)
        XCTAssertEqual(decoded.owner.selected.ownerRevision, 7)
        let legalBoundary = String(repeating: "a", count: 128)
        try roundTrip(self.link(finding: finding(legalBoundary)))
        for illegal in ["Finding.pump-7", " finding.pump-7", "finding/pump-7", "café", "cafe\u{301}",
                        String(repeating: "a", count: 129), ""] {
            var bad = try object(link)
            bad["findingID"] = illegal
            try assertRejected(ActivityFindingOwnerLinkV1.self, bad)
            var badWork = try object(support)
            badWork["correctiveWorkID"] = illegal
            try assertRejected(FindingC14SupportReferenceV1.self, badWork)
            var badRecheck = try object(XCTUnwrap(link.verifiedRecheck))
            badRecheck["recheckID"] = illegal
            try assertRejected(FindingVerifiedRecheckReferenceV1.self, badRecheck)
        }
    }

    func testOptionalFieldsMustBeAbsentRatherThanExplicitNull() throws {
        let plain = try link()
        let original = try object(plain)
        XCTAssertNil(original["correctiveAction"])
        XCTAssertNil(original["verifiedRecheck"])
        for key in ["correctiveAction", "verifiedRecheck"] {
            var bad = original
            bad[key] = NSNull()
            try assertRejected(ActivityFindingOwnerLinkV1.self, bad)
            XCTAssertThrowsError(try JSONDecoder().decode(ActivityFindingOwnerLinkV1.self, from: canonicalJSON(bad)))
        }
        var source = try object(plain.source)
        var context = try XCTUnwrap(source["selected"] as? [String: Any])
        context["taskOrScopeID"] = NSNull()
        source["selected"] = context
        try assertRejected(FindingActivitySourceReferenceV1.self, source)
    }

    func testWrongVersionKindWorkspaceAndNilIdentitiesAreRejected() throws {
        var selection = try object(self.selection())
        for contract in ["C47_FINDING_OWNER_SELECTION_V2", "", "C47_FINDING_OWNER_CLOSEOUT_V1"] {
            selection["contract"] = contract
            try assertRejected(ActivityFindingSelectionV1.self, selection)
        }
        let originalOwner = try object(owner())
        for kind in ["FINDING", "workflowRecord", "operationalRecheck", "future"] {
            var bad = originalOwner
            bad["kind"] = kind
            try assertRejected(FindingOwnerRevisionReferenceV1.self, bad)
        }
        var nilOwner = originalOwner
        nilOwner["ownerID"] = zero.uuidString
        try assertRejected(FindingOwnerRevisionReferenceV1.self, nilOwner)
        nilOwner = originalOwner
        nilOwner["workspaceID"] = ["rawValue": zero.uuidString]
        try assertRejected(FindingOwnerRevisionReferenceV1.self, nilOwner)
        for key in ["generationID", "mutationID"] {
            var nilAcceptance = try object(acceptance())
            nilAcceptance[key] = zero.uuidString
            try assertRejected(FindingAcceptedMutationReferenceV1.self, nilAcceptance)
        }
        var wrongWorkspace = try object(selectedOwner())
        var selectedAcceptance = try XCTUnwrap(wrongWorkspace["selectedAcceptance"] as? [String: Any])
        selectedAcceptance["workspaceID"] = ["rawValue": id(99).uuidString]
        wrongWorkspace["selectedAcceptance"] = selectedAcceptance
        try assertRejected(FindingSelectedOwnerReferenceV1.self, wrongWorkspace)
        XCTAssertThrowsError(try ActivityFindingSelectionV1(workspaceID: workspace, activityID: id(3),
            frontier: frontier(workspace: WorkspaceID(rawValue: id(99))), links: [], relationshipOwners: []))
        XCTAssertThrowsError(try link(owner: selectedOwner(kind: .relationship)))
        XCTAssertThrowsError(try self.selection(relationships: [selectedOwner()]))
    }

    func testEmptySelectionMatchesIndependentLiteralBytesAndHash() throws {
        let value = try selection()
        let literal = #"{"activityID":"CF470000-0000-4000-8000-000000000003","contract":"C47_FINDING_OWNER_SELECTION_V1","frontier":{"entityRevisions":[],"generationID":"CF470000-0000-4000-8000-000000000002","workspaceID":{"rawValue":"CF470000-0000-4000-8000-000000000001"},"workspaceRevision":9},"links":[],"relationshipOwners":[],"selectionSHA256":"aafa0a6d9dcbdbd101f0eb3acb3a46d33a33d4c80e1a45f9fab75510e354e680","workspaceID":{"rawValue":"CF470000-0000-4000-8000-000000000001"}}"#
        XCTAssertEqual(value.selectionSHA256, "aafa0a6d9dcbdbd101f0eb3acb3a46d33a33d4c80e1a45f9fab75510e354e680")
        XCTAssertEqual(try FindingOwnerSelectionCanonicalCodecV1.encode(value), Data(literal.utf8))
        XCTAssertEqual(try FindingOwnerSelectionCanonicalCodecV1.decode(ActivityFindingSelectionV1.self,
            from: Data(literal.utf8)), value)
        XCTAssertThrowsError(try selection(relationships: [selectedOwner(50, kind: .relationship)]))
    }

    func testNestedLegacyValueGroupsAreClosedOnlyAtTheNewBoundary() throws {
        let identity = try WorkspaceEntityIdentityV1(kind: .activitySessionEnvelope, id: id(3))
        let entity = WorkspaceEntityRevisionV1(identity: identity, revision: 3)
        let value = try ActivityFindingSelectionV1(workspaceID: workspace, activityID: id(3),
            frontier: frontier(entities: [entity]), links: [link()], relationshipOwners: [])
        let original = try object(value)
        for variant in try unknownObjectVariants(original) {
            let changed = try XCTUnwrap(variant as? [String: Any])
            try assertRejected(ActivityFindingSelectionV1.self, changed)
            XCTAssertThrowsError(try JSONDecoder().decode(ActivityFindingSelectionV1.self, from: canonicalJSON(changed)))
        }
        // The original contexts/frontier retain their existing canonical shape.
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(value.links[0].source.original),
                       try WorkspaceMutationCanonicalV1.data(source().original))
        var raw = try object(value)
        var front = try XCTUnwrap(raw["frontier"] as? [String: Any])
        front["entityRevisions"] = [
            ["identity": ["kind": "activitySessionEnvelope", "id": id(3).uuidString], "revision": 3],
            ["identity": ["kind": "activitySessionEnvelope", "id": id(3).uuidString], "revision": 3]
        ]
        raw["frontier"] = front
        try assertRejected(ActivityFindingSelectionV1.self, raw)
    }

    /// Mutates each object independently, including workspace wrappers, source
    /// contexts, portable-frontier entries and identity objects.
    private func unknownObjectVariants(_ value: Any) throws -> [Any] {
        var result: [Any] = []
        if let object = value as? [String: Any] {
            var extra = object
            extra["futureField"] = 1
            result.append(extra)
            for key in object.keys.sorted() {
                let child = try XCTUnwrap(object[key])
                for nested in try unknownObjectVariants(child) {
                    var changed = object
                    changed[key] = nested
                    result.append(changed)
                }
            }
        } else if let array = value as? [Any] {
            for index in array.indices {
                for nested in try unknownObjectVariants(array[index]) {
                    var changed = array
                    changed[index] = nested
                    result.append(changed)
                }
            }
        }
        return result
    }

    func testRevisionBoundariesPreserveUInt64AndIntWithoutNarrowingOrOverflow() throws {
        try roundTrip(owner(revision: UInt64.max))
        let maximumFinding = try finding(revision: Int.max)
        let maximumLink = try link(finding: maximumFinding, owner: selectedOwner(revision: UInt64.max))
        try roundTrip(maximumLink)
        let maximumSelection = try ActivityFindingSelectionV1(workspaceID: workspace, activityID: id(3),
            frontier: frontier(revision: UInt64.max), links: [maximumLink], relationshipOwners: [])
        try roundTrip(maximumSelection)
        XCTAssertEqual(maximumSelection.frontier.workspaceRevision, UInt64.max)
        XCTAssertEqual(maximumSelection.links[0].findingRevision, Int.max)
        XCTAssertThrowsError(try owner(revision: 0))
        var negative = try object(maximumLink)
        negative["findingRevision"] = -1
        try assertRejected(ActivityFindingOwnerLinkV1.self, negative)
        let maximumOwnerBytes = try FindingOwnerSelectionCanonicalCodecV1.encode(owner(revision: UInt64.max))
        let text = try XCTUnwrap(String(data: maximumOwnerBytes, encoding: .utf8))
        let overflow = text.replacingOccurrences(of: "18446744073709551615", with: "18446744073709551616")
        XCTAssertNotEqual(text, overflow)
        XCTAssertThrowsError(try FindingOwnerSelectionCanonicalCodecV1.decode(FindingOwnerRevisionReferenceV1.self,
            from: Data(overflow.utf8)))
        let extremeRecheck = try recheck(expectedRevision: Int.max - 1, resultingRevision: Int.max)
        let reference = try FindingVerifiedRecheckReferenceV1(owner: owner(), recheckID: extremeRecheck.recheckID,
            resultingRecheckRevision: Int.max, recheckSHA256: WorkspaceMutationCanonicalV1.sha256(extremeRecheck))
        try reference.validate(recheck: extremeRecheck)
        try roundTrip(reference)
        var negativeRecheck = try object(reference)
        negativeRecheck["resultingRecheckRevision"] = 0
        try assertRejected(FindingVerifiedRecheckReferenceV1.self, negativeRecheck)
        let c14 = try support(event: event(finding: finding()), workRevision: Int.max)
        try roundTrip(c14)
        var negativeWork = try object(c14)
        negativeWork["correctiveWorkRevision"] = -1
        try assertRejected(FindingC14SupportReferenceV1.self, negativeWork)
        var zeroEvent = try object(c14.original)
        zeroEvent["eventRevision"] = 0
        try assertRejected(FindingCorrectiveEventReferenceV1.self, zeroEvent)
    }

    func testDuplicateAndConflictingFindingOwnerAndRelationshipIdentitiesReject() throws {
        let first = try link()
        XCTAssertThrowsError(try selection(links: [first, first]))
        let sameFindingOtherOwner = try link(owner: selectedOwner(21))
        XCTAssertThrowsError(try selection(links: [first, sameFindingOtherOwner]))
        let otherFindingSameOwner = try link(finding: finding("finding.z"))
        XCTAssertThrowsError(try selection(links: [first, otherFindingSameOwner]))
        let ownerDifferentRevision = try selectedOwner(revision: 8)
        let conflicting = try link(finding: finding("finding.z"), owner: ownerDifferentRevision)
        XCTAssertThrowsError(try selection(links: [first, conflicting]))
        let relationship = try selectedOwner(50, kind: .relationship)
        XCTAssertThrowsError(try selection(links: [first], relationships: [relationship, relationship]))
        let changedRelationship = try selectedOwner(50, kind: .relationship, revision: 8)
        XCTAssertThrowsError(try selection(links: [first], relationships: [relationship, changedRelationship]))
        let kindCollision = try selectedOwner(20, kind: .relationship)
        XCTAssertThrowsError(try selection(links: [first], relationships: [kindCollision]))
        let valid = try selection(links: [first], relationships: [relationship])
        XCTAssertEqual(valid.relationshipOwners.count, 1)
        try roundTrip(valid)
    }

    func testCanonicalOrderingIsUTF8AndRelationshipOwnerTupleOrder() throws {
        let names = ["finding-7", "finding.7", "finding_7", "findinga"]
        var links: [ActivityFindingOwnerLinkV1] = []
        for (index, name) in names.enumerated() {
            links.append(try link(finding: finding(name), owner: selectedOwner(100 + index)))
        }
        let relationships = try [selectedOwner(200, kind: .relationship), selectedOwner(201, kind: .relationship)]
        let value = try selection(links: links, relationships: relationships)
        XCTAssertEqual(value.links.map(\.findingID), names)
        try roundTrip(value)
        XCTAssertThrowsError(try selection(links: Array(links.reversed()), relationships: relationships))
        XCTAssertThrowsError(try selection(links: links, relationships: Array(relationships.reversed())))
    }

    func testDigestsRejectMalformedValuesAndSelectionTampering() throws {
        let fact = try finding()
        let support = try support(event: event(finding: fact))
        let link = try link(finding: fact, support: support, recheck: recheck())
        for digest in ["", String(repeating: "A", count: 64), String(repeating: "g", count: 64),
                       String(repeating: "a", count: 63), " " + a] {
            var owner = try object(link.owner.selected)
            owner["recordSHA256"] = digest
            try assertRejected(FindingOwnerRevisionReferenceV1.self, owner)
            for key in ["envelopeSHA256", "receiptSHA256"] {
                var acceptance = try object(link.owner.selectedAcceptance)
                acceptance[key] = digest
                try assertRejected(FindingAcceptedMutationReferenceV1.self, acceptance)
            }
            var badLink = try object(link)
            badLink["findingSHA256"] = digest
            try assertRejected(ActivityFindingOwnerLinkV1.self, badLink)
            var event = try object(support.selected)
            event["eventSHA256"] = digest
            try assertRejected(FindingCorrectiveEventReferenceV1.self, event)
            var recheck = try object(XCTUnwrap(link.verifiedRecheck))
            recheck["recheckSHA256"] = digest
            try assertRejected(FindingVerifiedRecheckReferenceV1.self, recheck)
        }
        let value = try selection(links: [link], relationships: [selectedOwner(50, kind: .relationship)])
        let original = try object(value)
        var badDigest = original
        badDigest["selectionSHA256"] = a
        try assertRejected(ActivityFindingSelectionV1.self, badDigest)
        var changedActivity = original
        changedActivity["activityID"] = id(99).uuidString
        try assertRejected(ActivityFindingSelectionV1.self, changedActivity)
        var removedRelationship = original
        removedRelationship["relationshipOwners"] = []
        try assertRejected(ActivityFindingSelectionV1.self, removedRelationship)
        var changedFrontier = original
        var front = try XCTUnwrap(changedFrontier["frontier"] as? [String: Any])
        front["workspaceRevision"] = 10
        changedFrontier["frontier"] = front
        try assertRejected(ActivityFindingSelectionV1.self, changedFrontier)
        var changedFinding = original
        var links = try XCTUnwrap(changedFinding["links"] as? [[String: Any]])
        links[0]["findingSHA256"] = a
        changedFinding["links"] = links
        try assertRejected(ActivityFindingSelectionV1.self, changedFinding)
    }

    func testExactRecheckOwnerKindRevisionAndDigestAreRequired() throws {
        let fact = try finding()
        let support = try support(event: event(finding: fact))
        let valid = try link(finding: fact, support: support, recheck: recheck())
        let recheckReference = try XCTUnwrap(valid.verifiedRecheck)
        for substitutedOwner in try [owner(21), owner(revision: 8), owner(digest: a),
                                      owner(workspace: WorkspaceID(rawValue: id(99)))] {
            let substituted = try FindingVerifiedRecheckReferenceV1(owner: substitutedOwner,
                recheckID: recheckReference.recheckID, resultingRecheckRevision: 1,
                recheckSHA256: recheckReference.recheckSHA256)
            XCTAssertThrowsError(try ActivityFindingOwnerLinkV1(findingID: valid.findingID,
                findingRevision: valid.findingRevision, findingSHA256: valid.findingSHA256,
                owner: valid.owner, source: valid.source, correctiveAction: support, verifiedRecheck: substituted))
        }
        XCTAssertThrowsError(try FindingVerifiedRecheckReferenceV1(owner: owner(kind: .relationship),
            recheckID: "recheck.pump-7", resultingRecheckRevision: 1, recheckSHA256: a))
        XCTAssertThrowsError(try ActivityFindingOwnerLinkV1(findingID: valid.findingID,
            findingRevision: valid.findingRevision, findingSHA256: valid.findingSHA256,
            owner: valid.owner, source: valid.source, verifiedRecheck: recheckReference))
    }

    func testTypedFindingC14AndRecheckBindingsRejectIndependentlyValidWrongFacts() throws {
        let fact = try finding()
        let event = try event(finding: fact)
        let support = try support(event: event)
        let recheck = try recheck()
        let valid = try link(finding: fact, support: support, recheck: recheck)
        try valid.validateBindings(finding: fact, originalCorrectiveEvent: event,
                                   selectedCorrectiveEvent: event, recheck: recheck)
        XCTAssertThrowsError(try valid.validateBindings(finding: finding("finding.other"),
            originalCorrectiveEvent: event, selectedCorrectiveEvent: event, recheck: recheck))
        XCTAssertThrowsError(try valid.validateBindings(finding: fact, originalCorrectiveEvent: event,
            selectedCorrectiveEvent: event))
        XCTAssertThrowsError(try valid.validateBindings(finding: fact, recheck: recheck))
        let wrongAction = try self.event(finding: fact, actionSlot: 99)
        XCTAssertThrowsError(try valid.validateBindings(finding: fact, originalCorrectiveEvent: event,
            selectedCorrectiveEvent: wrongAction, recheck: recheck))
        let wrongSource = try ChangeRequestItemReferenceV1(kind: .finding, itemID: fact.findingID,
            itemRevision: 1, itemSHA256: WorkspaceMutationCanonicalV1.sha256(fact))
        let wrongEvent = try self.event(finding: fact, sourceOverride: wrongSource)
        let matchingWrongEventReference = try self.support(event: wrongEvent)
        let wrongC14Link = try link(finding: fact, support: matchingWrongEventReference, recheck: recheck)
        XCTAssertThrowsError(try wrongC14Link.validateBindings(finding: fact, originalCorrectiveEvent: wrongEvent,
            selectedCorrectiveEvent: wrongEvent, recheck: recheck))
        let wrongKind = try ChangeRequestItemReferenceV1(kind: .criterion, itemID: fact.findingID,
            itemRevision: 0, itemSHA256: WorkspaceMutationCanonicalV1.sha256(fact))
        let wrongKindEvent = try self.event(finding: fact, sourceOverride: wrongKind)
        let wrongKindLink = try link(finding: fact, support: self.support(event: wrongKindEvent), recheck: recheck)
        XCTAssertThrowsError(try wrongKindLink.validateBindings(finding: fact, originalCorrectiveEvent: wrongKindEvent,
            selectedCorrectiveEvent: wrongKindEvent, recheck: recheck))
        let wrongRechecks = try [self.recheck(findingID: "finding.other"), self.recheck(findingRevision: 1),
                                self.recheck(workID: "work.other"), self.recheck(workRevision: 1)]
        for wrong in wrongRechecks {
            // Bind its real digest first: rejection must come from the cross-fact
            // Finding/work linkage, not from a conveniently stale recheck hash.
            let selfConsistentReference = try link(finding: fact, support: support, recheck: wrong)
            XCTAssertThrowsError(try selfConsistentReference.validateBindings(finding: fact,
                originalCorrectiveEvent: event, selectedCorrectiveEvent: event, recheck: wrong))
        }
        let plain = try link(finding: fact)
        try plain.validateBindings(finding: fact)
        XCTAssertThrowsError(try plain.validateBindings(finding: fact, recheck: recheck))
        XCTAssertThrowsError(try plain.validateBindings(finding: fact, originalCorrectiveEvent: event))
    }

    func testOriginalAndSelectedProvenanceRemainDistinctWithoutAuthenticityClaims() throws {
        let original = try owner()
        let destination = WorkspaceID(rawValue: id(99))
        let mapped = try owner(workspace: destination, digest: a)
        let originalAcceptance = try acceptance()
        let destinationAcceptance = try FindingAcceptedMutationReferenceV1(workspaceID: destination,
            generationID: id(98), mutationID: mutation(97), envelopeSHA256: b, receiptSHA256: c)
        let pair = try FindingSelectedOwnerReferenceV1(original: original, selected: mapped,
            originalAcceptance: originalAcceptance, selectedAcceptance: destinationAcceptance)
        try roundTrip(pair)
        XCTAssertEqual(pair.original.recordSHA256, c)
        XCTAssertEqual(pair.selected.recordSHA256, a)
        XCTAssertEqual(pair.originalAcceptance.generationID, id(2))
        XCTAssertEqual(pair.selectedAcceptance.generationID, id(98))
        // A genuine same-workspace destination acceptance may differ; its actual
        // journal artifacts and mapping still require writer authentication.
        let anotherAcceptance = try FindingAcceptedMutationReferenceV1(workspaceID: workspace,
            generationID: id(96), mutationID: mutation(95), envelopeSHA256: b, receiptSHA256: c)
        let sameWorkspace = try FindingSelectedOwnerReferenceV1(original: original, selected: original,
            originalAcceptance: originalAcceptance, selectedAcceptance: anotherAcceptance)
        try roundTrip(sameWorkspace)
        XCTAssertNotEqual(sameWorkspace.originalAcceptance, sameWorkspace.selectedAcceptance)
        let changedRevision = try owner(revision: 8, workspace: destination)
        XCTAssertThrowsError(try FindingSelectedOwnerReferenceV1(original: original, selected: changedRevision,
            originalAcceptance: originalAcceptance, selectedAcceptance: destinationAcceptance))
        XCTAssertThrowsError(try FindingSelectedOwnerReferenceV1(original: original,
            selected: owner(kind: .relationship, workspace: destination),
            originalAcceptance: originalAcceptance, selectedAcceptance: destinationAcceptance))
        XCTAssertThrowsError(try FindingSelectedOwnerReferenceV1(original: original, selected: mapped,
            originalAcceptance: destinationAcceptance, selectedAcceptance: originalAcceptance))
    }

    func testConflictingAcceptanceAndSourceIdentitiesCannotBeMerged() throws {
        let original = try owner()
        XCTAssertThrowsError(try FindingSelectedOwnerReferenceV1(original: original, selected: original,
            originalAcceptance: acceptance(), selectedAcceptance: acceptance(receipt: c)))
        let changedGenerationOnly = try FindingAcceptedMutationReferenceV1(workspaceID: workspace,
            generationID: id(98), mutationID: mutation(11), envelopeSHA256: a, receiptSHA256: b)
        XCTAssertThrowsError(try FindingSelectedOwnerReferenceV1(original: original, selected: original,
            originalAcceptance: acceptance(), selectedAcceptance: changedGenerationOnly))
        let first = try link()
        let source = try self.source()
        let conflictingContext = try FindingSourceContextV1(workspaceID: workspace,
            activityID: source.selected.activityID, activityKind: source.selected.activityKind,
            activityRevision: source.selected.activityRevision, activitySHA256: c, taskOrScopeID: "scope-B")
        let conflictingSource = try FindingActivitySourceReferenceV1(original: conflictingContext,
            selected: conflictingContext, originalAcceptance: acceptance(12), selectedAcceptance: acceptance(12))
        let second = try ActivityFindingOwnerLinkV1(findingID: "finding.z", findingRevision: 0,
            findingSHA256: a, owner: selectedOwner(21), source: conflictingSource)
        XCTAssertThrowsError(try selection(links: [first, second]))
        var changed = try object(first)
        var owner = try XCTUnwrap(changed["owner"] as? [String: Any])
        var accepted = try XCTUnwrap(owner["selectedAcceptance"] as? [String: Any])
        accepted["mutationID"] = id(12).uuidString
        accepted["receiptSHA256"] = c
        owner["selectedAcceptance"] = accepted
        changed["owner"] = owner
        try assertRejected(ActivityFindingOwnerLinkV1.self, changed)
    }

    func testCanonicalCodecRejectsDuplicateWireKeysNoncanonicalBytesAndOversizeInput() throws {
        let value = try selection()
        let bytes = try FindingOwnerSelectionCanonicalCodecV1.encode(value)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        let duplicate = "{\"contract\":\"C47_FINDING_OWNER_SELECTION_V1\"," + String(text.dropFirst())
        XCTAssertThrowsError(try FindingOwnerSelectionCanonicalCodecV1.decode(ActivityFindingSelectionV1.self,
            from: Data(duplicate.utf8)))
        XCTAssertThrowsError(try FindingOwnerSelectionCanonicalCodecV1.decode(ActivityFindingSelectionV1.self,
            from: Data((" " + text).utf8)))
        XCTAssertThrowsError(try FindingOwnerSelectionCanonicalCodecV1.decode(ActivityFindingSelectionV1.self,
            from: Data(repeating: 0x20, count: FindingContractLimitsV1.maximumCanonicalBytes + 1)))
        XCTAssertThrowsError(try FindingOwnerSelectionCanonicalCodecV1.decode(ActivityFindingSelectionV1.self,
            from: Data()))
        let one = try link()
        XCTAssertThrowsError(try selection(links: Array(repeating: one, count: 1_025)))
        XCTAssertThrowsError(try selection(links: [one],
            relationships: Array(repeating: selectedOwner(50, kind: .relationship), count: 1_025)))
    }

    func testCompleteSelectionByteLimitAppliesBeforePublication() throws {
        var links: [ActivityFindingOwnerLinkV1] = []
        for index in 0..<700 {
            let findingID = String(format: "finding.%04d", index)
            links.append(try link(finding: finding(findingID), owner: selectedOwner(2_000 + index)))
        }
        // This is below the C04 registry cardinality bound but above its 1 MiB
        // canonical byte bound. No separate, smaller workspace-frontier cap.
        XCTAssertThrowsError(try selection(links: links)) { error in
            XCTAssertEqual(error as? FindingContractFailureV1, .limitExceeded)
        }
    }

    func testNilAndCrossWorkspaceSourceC14AndFrontierIdentitiesReject() throws {
        let fact = try finding()
        let corrective = try support(event: event(finding: fact))
        for key in ["actionID", "eventID"] {
            var bad = try object(corrective.selected)
            bad[key] = zero.uuidString
            try assertRejected(FindingCorrectiveEventReferenceV1.self, bad)
        }
        var badEvent = try object(corrective.selected)
        badEvent["workspaceID"] = ["rawValue": id(99).uuidString]
        try assertRejected(FindingCorrectiveEventReferenceV1.self, badEvent)
        for field in ["workspaceID", "activityID", "activityRevision", "activityKind", "activitySHA256"] {
            var badSource = try object(source())
            var context = try XCTUnwrap(badSource["selected"] as? [String: Any])
            switch field {
            case "workspaceID": context[field] = ["rawValue": zero.uuidString]
            case "activityID": context[field] = zero.uuidString
            case "activityRevision": context[field] = 0
            case "activityKind": context[field] = "FUTURE_ACTIVITY"
            default: context[field] = "invalid"
            }
            badSource["selected"] = context
            try assertRejected(FindingActivitySourceReferenceV1.self, badSource)
        }
        var badSelection = try object(selection())
        badSelection["activityID"] = zero.uuidString
        try assertRejected(ActivityFindingSelectionV1.self, badSelection)
        badSelection = try object(selection())
        var badFrontier = try XCTUnwrap(badSelection["frontier"] as? [String: Any])
        badFrontier["generationID"] = zero.uuidString
        badSelection["frontier"] = badFrontier
        try assertRejected(ActivityFindingSelectionV1.self, badSelection)
    }

    func testMappedSourceAndC14PairsKeepExactFieldsAndSeparateAcceptances() throws {
        let originalSource = try source()
        let destination = WorkspaceID(rawValue: id(99))
        let destinationAcceptance = try FindingAcceptedMutationReferenceV1(workspaceID: destination,
            generationID: id(98), mutationID: mutation(12), envelopeSHA256: b, receiptSHA256: c)
        let selectedContext = try originalSource.original.rebound(to: destination,
            activityID: originalSource.original.activityID, mappedActivitySHA256: c)
        let mappedSource = try FindingActivitySourceReferenceV1(original: originalSource.original,
            selected: selectedContext, originalAcceptance: originalSource.originalAcceptance,
            selectedAcceptance: destinationAcceptance)
        try roundTrip(mappedSource)
        XCTAssertEqual(mappedSource.original.activitySHA256, a)
        XCTAssertEqual(mappedSource.selected.activitySHA256, c)
        let differentScope = try FindingSourceContextV1(workspaceID: destination, activityID: selectedContext.activityID,
            activityKind: selectedContext.activityKind, activityRevision: selectedContext.activityRevision,
            activitySHA256: c, taskOrScopeID: "other-scope")
        XCTAssertThrowsError(try FindingActivitySourceReferenceV1(original: originalSource.original,
            selected: differentScope, originalAcceptance: originalSource.originalAcceptance,
            selectedAcceptance: destinationAcceptance))
        let corrective = try support(event: event(finding: finding()))
        let mappedAcceptance = try FindingAcceptedMutationReferenceV1(workspaceID: destination,
            generationID: id(98), mutationID: mutation(13), envelopeSHA256: b, receiptSHA256: c)
        let mappedEvent = try FindingCorrectiveEventReferenceV1(workspaceID: destination,
            actionID: corrective.selected.actionID, eventID: corrective.selected.eventID,
            eventRevision: corrective.selected.eventRevision, eventSHA256: a, acceptance: mappedAcceptance)
        let mappedSupport = try FindingC14SupportReferenceV1(correctiveWorkID: corrective.correctiveWorkID,
            correctiveWorkRevision: 0, original: corrective.original, selected: mappedEvent)
        try roundTrip(mappedSupport)
        XCTAssertEqual(mappedSupport.original.eventSHA256, corrective.original.eventSHA256)
        XCTAssertEqual(mappedSupport.selected.eventSHA256, a)
        let sameWorkspaceAcceptance = try FindingAcceptedMutationReferenceV1(workspaceID: workspace,
            generationID: id(98), mutationID: mutation(95), envelopeSHA256: b, receiptSHA256: c)
        let sameFactOtherAcceptance = try FindingCorrectiveEventReferenceV1(workspaceID: workspace,
            actionID: corrective.selected.actionID, eventID: corrective.selected.eventID,
            eventRevision: corrective.selected.eventRevision, eventSHA256: corrective.selected.eventSHA256,
            acceptance: sameWorkspaceAcceptance)
        try roundTrip(FindingC14SupportReferenceV1(correctiveWorkID: corrective.correctiveWorkID,
            correctiveWorkRevision: 0, original: corrective.original, selected: sameFactOtherAcceptance))
    }
}
