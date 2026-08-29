import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private final class C30EvidenceContextAnchorV9_35ClientCapabilityPackageLifecycle: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

/// C21's tests use the portable capability and package-lifecycle contracts as
/// the source of truth.  The fixture contains no client identity, endpoint,
/// account, provider, or network state.
enum C21ClientCapabilityTestSupport {
    struct Fixture {
        let workspace: WorkspaceID
        let release: InspectionPackageReleaseV1
        let ranges: [PortableCapabilityRangeV1]
        let profile: ClientCapabilityProfileV1
        let policy: PackageLifecyclePolicyV1
        let disposition: PackageLifecycleDispositionV1
        let decisions: [PackageLifecycleOperationV1: ClientCapabilityAdmissionDecisionV1]
    }

    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c2100000-0000-4000-8000-%012x", slot))!
    }

    static func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    static func digest(_ byte: Character = "a") -> String {
        String(repeating: byte, count: 64)
    }

    static func ranges(
        minimumMajor: UInt32 = 1,
        maximumMajor: UInt32 = 3
    ) throws -> [PortableCapabilityRangeV1] {
        let minimum = try PortableSemanticVersionV1(major: minimumMajor)
        let maximum = try PortableSemanticVersionV1(
            major: maximumMajor,
            minor: 2,
            patch: 1
        )
        return try PortableCapabilityDomainV1.allCases.map { domain in
            try PortableCapabilityRangeV1(
                domain: domain,
                semanticID: "c21.\(domain.rawValue.lowercased())",
                minimum: minimum,
                maximum: maximum
            )
        }
    }

    static func rules() throws -> [PackageLifecycleOperationRuleV1] {
        try PackageLifecycleOperationV1.allCases.map { operation in
            let historicRead = [
                PackageLifecycleOperationV1.view,
                .export,
                .restore,
                .replay
            ].contains(operation)
            return try PackageLifecycleOperationRuleV1(
                operation: operation,
                active: .readWrite,
                deprecated: .migrationRequired,
                withdrawn: historicRead ? .readOnly : .reject,
                quarantined: .quarantine,
                superseded: .reject
            )
        }
    }

    static func makeFixture(
        state: PackageLifecycleStateV1 = .active,
        profileMaximumMajor: UInt32 = 3,
        requiredMinimumMajor: UInt32 = 1
    ) throws -> Fixture {
        let workspace = WorkspaceID(rawValue: id(1))
        let release = try publishedRelease()
        let profileRanges = try ranges(maximumMajor: profileMaximumMajor)
        let requiredRanges = try ranges(minimumMajor: requiredMinimumMajor)
        let profile = try ClientCapabilityProfileV1(
            profileID: id(10),
            workspaceID: workspace,
            semanticRanges: profileRanges,
            emittedAt: fixedDate,
            mutationID: try mutation(11)
        )
        let policy = try PackageLifecyclePolicyV1(
            policyID: id(20),
            workspaceID: workspace,
            release: release,
            requiredCapabilities: requiredRanges,
            operationRules: try rules(),
            effectiveAt: fixedDate.addingTimeInterval(1),
            mutationID: try mutation(21)
        )
        let disposition = try PackageLifecycleDispositionV1(
            dispositionID: id(30),
            workspaceID: workspace,
            release: release,
            state: state,
            reason: "C21 \(state.rawValue.lowercased()) disposition",
            recordedAt: fixedDate.addingTimeInterval(2),
            mutationID: try mutation(31)
        )
        let decisions = try Dictionary(uniqueKeysWithValues:
            PackageLifecycleOperationV1.allCases.enumerated().map { offset, operation in
                let outcome = ClientCapabilityAdmissionEvaluatorV1.evaluate(
                    profile: profile,
                    policy: policy,
                    disposition: disposition,
                    release: release,
                    operation: operation
                )
                let value = try ClientCapabilityAdmissionDecisionV1(
                    decisionID: id(100 + offset),
                    workspaceID: workspace,
                    profile: profile,
                    policy: policy,
                    disposition: disposition,
                    release: release,
                    operation: operation,
                    admission: outcome.0,
                    reasons: outcome.1,
                    decidedAt: fixedDate.addingTimeInterval(10 + Double(offset)),
                    mutationID: try mutation(200 + offset)
                )
                return (operation, value)
            }
        )
        return Fixture(
            workspace: workspace,
            release: release,
            ranges: profileRanges,
            profile: profile,
            policy: policy,
            disposition: disposition,
            decisions: decisions
        )
    }

    static func publishedRelease(
        workflowID: String = "c21.workflow.capability.v1"
    ) throws -> InspectionPackageReleaseV1 {
        let draft = try InspectionPackageReleaseV1.makeDraft(
            package: ShippingIlluminatedSignAdapterV1.inspectionPackage(),
            workflow: try workflow(id: workflowID)
        )
        return try InspectionPackageReleasePublisherV1.publish(
            InspectionPackageReleasePublisherV1.test(draft)
        ).release
    }

    private static func workflow(id: String) throws -> WorkflowDefinitionV1 {
        try WorkflowDefinitionV1(
            workflowID: id,
            entryNodeID: "c21.start",
            declaredFieldIDs: [],
            nodes: [
                try WorkflowNodeV1(
                    nodeID: "c21.start",
                    kind: .section,
                    localizationKey: "c21.start",
                    outgoingNodeIDs: ["c21.end"]
                ),
                try WorkflowNodeV1(
                    nodeID: "c21.end",
                    kind: .terminal,
                    localizationKey: "c21.end",
                    outgoingNodeIDs: []
                )
            ]
        )
    }

    static func assertHeader(_ corpus: C21Corpus, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(corpus.schema, "V21P03C21ClientCapabilityPackageLifecycleCorpusV1", file: file, line: line)
        XCTAssertEqual(corpus.schemaVersion, 1, file: file, line: line)
        XCTAssertEqual(corpus.cardID, "V23-P03-C21", file: file, line: line)
        XCTAssertEqual(corpus.records, 19, file: file, line: line)
        XCTAssertEqual(corpus.recordsSchemaVersion, 19, file: file, line: line)
        XCTAssertEqual(corpus.persistentSchemaVersion, 20, file: file, line: line)
        XCTAssertEqual(corpus.persistentModelCount, 81, file: file, line: line)
        XCTAssertEqual(corpus.evidenceIDs, [
            "V23-P03-C21-G01", "V23-P03-C21-A01", "V23-P03-C21-H01",
            "V23-P03-C21-I01", "V23-P03-C21-R01"
        ], file: file, line: line)
        XCTAssertEqual(corpus.admissions, ClientAdmissionV1.allCases.map(\.rawValue), file: file, line: line)
        XCTAssertEqual(corpus.operations, PackageLifecycleOperationV1.allCases.map(\.rawValue), file: file, line: line)
        XCTAssertEqual(corpus.states, PackageLifecycleStateV1.allCases.map(\.rawValue), file: file, line: line)
        XCTAssertTrue(corpus.platformNeutral, file: file, line: line)
        XCTAssertTrue(corpus.localeAndOrderingIndependent, file: file, line: line)
        XCTAssertTrue(corpus.immutablePackageBytes, file: file, line: line)
        XCTAssertTrue(corpus.historicWithdrawalReadable, file: file, line: line)
        XCTAssertTrue(corpus.noRemoteIdentity, file: file, line: line)
        XCTAssertTrue(corpus.noSecondWriter, file: file, line: line)
        XCTAssertTrue(corpus.noSecondStore, file: file, line: line)
    }
}

struct C21Corpus: Decodable {
    let schema: String
    let schemaVersion: Int
    let corpusID: String
    let cardID: String
    let records: Int
    let recordsSchemaVersion: Int
    let persistentSchemaVersion: Int
    let persistentModelCount: Int
    let evidenceIDs: [String]
    let admissions: [String]
    let operations: [String]
    let states: [String]
    let capabilityDomains: [String]
    let evidenceSelectors: [C21EvidenceSelector]
    let coverage: [String]
    let interruptionBoundaries: [String]
    let recoveryDispositions: [String]
    let lifecycleConsumers: [String]
    let privacyExclusions: [String]
    let forbiddenProductionSymbols: [String]
    let platformNeutral: Bool
    let localeAndOrderingIndependent: Bool
    let immutablePackageBytes: Bool
    let historicWithdrawalReadable: Bool
    let noRemoteIdentity: Bool
    let noSecondWriter: Bool
    let noSecondStore: Bool
}

struct C21EvidenceSelector: Decodable {
    let id: String
    let selector: String
    let focus: String
}

@MainActor
final class V9_35ClientCapabilityPackageLifecycleTests: XCTestCase {
    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    func testV23P03C21G01CapabilityAdmissionAndImmutableReleaseLifecycle() throws {
        let corpus = try loadCorpus()
        C21ClientCapabilityTestSupport.assertHeader(corpus)
        XCTAssertEqual(corpus.capabilityDomains, PortableCapabilityDomainV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.evidenceSelectors.map(\.id), corpus.evidenceIDs)

        let first = try C21ClientCapabilityTestSupport.makeFixture()
        let second = try C21ClientCapabilityTestSupport.makeFixture()
        XCTAssertEqual(PersistentSchemaV20.versionIdentifier, Schema.Version(20, 0, 0))
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        try V20ClientCapabilityImportBoundaryV1.validate(
            persistent: 20,
            records: 19
        )
        XCTAssertThrowsError(
            try V20ClientCapabilityImportBoundaryV1.validate(
                persistent: 19,
                records: 18
            )
        )
        try first.profile.validate()
        try first.policy.validate(release: first.release)
        try first.disposition.validate(release: first.release)
        XCTAssertEqual(first.profile, second.profile)
        XCTAssertEqual(first.policy, second.policy)
        XCTAssertEqual(first.disposition, second.disposition)
        XCTAssertTrue(first.profile.supports(first.policy.requiredCapabilities))
        XCTAssertEqual(
            first.ranges.map(\.stableKey),
            first.ranges.map(\.stableKey).sorted()
        )
        XCTAssertEqual(Set(first.ranges.map(\.domain)), Set(PortableCapabilityDomainV1.allCases))

        let profileData = try ClientCapabilityCanonicalCodecV1.encode(first.profile)
        let policyData = try ClientCapabilityCanonicalCodecV1.encode(first.policy)
        let dispositionData = try ClientCapabilityCanonicalCodecV1.encode(first.disposition)
        XCTAssertEqual(
            try ClientCapabilityCanonicalCodecV1.decode(ClientCapabilityProfileV1.self, from: profileData),
            first.profile
        )
        XCTAssertEqual(
            try ClientCapabilityCanonicalCodecV1.decode(PackageLifecyclePolicyV1.self, from: policyData),
            first.policy
        )
        XCTAssertEqual(
            try ClientCapabilityCanonicalCodecV1.decode(PackageLifecycleDispositionV1.self, from: dispositionData),
            first.disposition
        )
        XCTAssertEqual(first.release.canonicalPackageBytes, second.release.canonicalPackageBytes)
        XCTAssertEqual(first.release.canonicalWorkflowBytes, second.release.canonicalWorkflowBytes)
    }

    func testV23P03C21A01ClosedAdmissionAndOperationMatrixIsDeterministic() throws {
        let corpus = try loadCorpus()
        C21ClientCapabilityTestSupport.assertHeader(corpus)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PackageLifecycleStateV1.allCases.count, 5)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)

        var observedAdmissions = Set<ClientAdmissionV1>()
        for state in PackageLifecycleStateV1.allCases {
            let fixture = try C21ClientCapabilityTestSupport.makeFixture(state: state)
            for operation in PackageLifecycleOperationV1.allCases {
                let result = ClientCapabilityAdmissionEvaluatorV1.evaluate(
                    profile: fixture.profile,
                    policy: fixture.policy,
                    disposition: fixture.disposition,
                    release: fixture.release,
                    operation: operation
                )
                XCTAssertEqual(result.0, try fixture.policy.rule(for: operation).admission(for: state))
                XCTAssertFalse(result.1.isEmpty)
                observedAdmissions.insert(result.0)
            }
        }
        XCTAssertEqual(observedAdmissions, Set(ClientAdmissionV1.allCases))

        let fixture = try C21ClientCapabilityTestSupport.makeFixture()
        XCTAssertEqual(Set(fixture.decisions.keys), Set(PackageLifecycleOperationV1.allCases))
        for operation in PackageLifecycleOperationV1.allCases {
            let decision = try XCTUnwrap(fixture.decisions[operation])
            try decision.validate(
                profile: fixture.profile,
                policy: fixture.policy,
                disposition: fixture.disposition,
                release: fixture.release
            )
            try ClientCapabilityLifecycleClosureV1(
                profile: fixture.profile,
                policy: fixture.policy,
                disposition: fixture.disposition,
                decision: decision,
                release: fixture.release
            ).validate()
        }
    }

    func testV23P03C21H01UnknownCapabilityAndForbiddenRemoteStateFailClosed() throws {
        let fixture = try C21ClientCapabilityTestSupport.makeFixture()
        let profileData = try ClientCapabilityCanonicalCodecV1.encode(fixture.profile)

        var unknownObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: profileData) as? [String: Any]
        )
        unknownObject["unknownCapability"] = "future"
        let unknownData = try JSONSerialization.data(
            withJSONObject: unknownObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        XCTAssertThrowsError(
            try ClientCapabilityCanonicalCodecV1.decode(
                ClientCapabilityProfileV1.self,
                from: unknownData
            )
        )

        var forgedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: profileData) as? [String: Any]
        )
        forgedObject["profileSHA256"] = C21ClientCapabilityTestSupport.digest("f")
        let forgedData = try JSONSerialization.data(
            withJSONObject: forgedObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let forgedProfile = try ClientCapabilityCanonicalCodecV1.decode(
            ClientCapabilityProfileV1.self,
            from: forgedData
        )
        XCTAssertThrowsError(try forgedProfile.validate())

        XCTAssertThrowsError(
            try PortableSemanticVersionV1(major: 0)
        )
        let duplicate = fixture.ranges + [try XCTUnwrap(fixture.ranges.first)]
        XCTAssertThrowsError(
            try ClientCapabilityProfileV1(
                profileID: C21ClientCapabilityTestSupport.id(12),
                workspaceID: fixture.workspace,
                semanticRanges: duplicate,
                emittedAt: C21ClientCapabilityTestSupport.fixedDate,
                mutationID: C21ClientCapabilityTestSupport.mutation(12)
            )
        )

        let foreignWorkspace = WorkspaceID(rawValue: C21ClientCapabilityTestSupport.id(999))
        let foreignPolicy = try fixture.policy.rebound(
            to: foreignWorkspace,
            release: fixture.release
        )
        let staleResult = ClientCapabilityAdmissionEvaluatorV1.evaluate(
            profile: fixture.profile,
            policy: foreignPolicy,
            disposition: fixture.disposition,
            release: fixture.release,
            operation: .start
        )
        XCTAssertEqual(staleResult.0, .reject)
        XCTAssertEqual(staleResult.1, [.stalePolicy])

        let unsupported = try C21ClientCapabilityTestSupport.makeFixture(
            profileMaximumMajor: 1,
            requiredMinimumMajor: 2
        )
        let unsupportedResult = ClientCapabilityAdmissionEvaluatorV1.evaluate(
            profile: unsupported.profile,
            policy: unsupported.policy,
            disposition: unsupported.disposition,
            release: unsupported.release,
            operation: .start
        )
        XCTAssertEqual(unsupportedResult.0, .reject)
        XCTAssertEqual(unsupportedResult.1, [.unsupportedRequiredRange])

        var missingRulesObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: ClientCapabilityCanonicalCodecV1.encode(fixture.policy)
            ) as? [String: Any]
        )
        let rules = try XCTUnwrap(missingRulesObject["operationRules"] as? [Any])
        missingRulesObject["operationRules"] = Array(rules.dropLast())
        let missingRulesData = try JSONSerialization.data(
            withJSONObject: missingRulesObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let missingRules = try ClientCapabilityCanonicalCodecV1.decode(
            PackageLifecyclePolicyV1.self,
            from: missingRulesData
        )
        XCTAssertThrowsError(try missingRules.validate(release: fixture.release))

        let otherRelease = try C21ClientCapabilityTestSupport.publishedRelease(
            workflowID: "c21.workflow.other.v1"
        )
        XCTAssertNotEqual(otherRelease, fixture.release)
        XCTAssertThrowsError(try fixture.policy.validate(release: otherRelease))
        XCTAssertThrowsError(
            try ClientCapabilityCanonicalCodecV1.decode(
                ClientCapabilityProfileV1.self,
                from: Data([0x20]) + profileData
            )
        )
    }

    func testV23P03C21I01CapabilityAdmissionAndPackageMutationIsAtomicAndRecoverable() throws {
        let fixture = try C21ClientCapabilityTestSupport.makeFixture()
        for mutation in [
            ClientCapabilityMutationV1.profile(fixture.profile),
            .policy(value: fixture.policy, release: fixture.release),
            .disposition(value: fixture.disposition, release: fixture.release),
            .admission(
                value: try XCTUnwrap(fixture.decisions[.start]),
                profile: fixture.profile,
                policy: fixture.policy,
                disposition: fixture.disposition,
                release: fixture.release
            )
        ] {
            try mutation.validate()
            XCTAssertEqual(try mutation.canonicalSHA256(), try mutation.canonicalSHA256())
        }

        let decision = try XCTUnwrap(fixture.decisions[.start])
        let profileRow = try ClientCapabilityProfileRow(fixture.profile)
        let policyRow = try PackageLifecyclePolicyRow(
            fixture.policy,
            release: fixture.release
        )
        let dispositionRow = try PackageLifecycleDispositionRow(
            fixture.disposition,
            release: fixture.release
        )
        let decisionRow = try ClientCapabilityAdmissionDecisionRow(
            decision,
            profile: fixture.profile,
            policy: fixture.policy,
            disposition: fixture.disposition,
            release: fixture.release
        )
        XCTAssertEqual(try profileRow.value(), fixture.profile)
        XCTAssertEqual(try policyRow.value(release: fixture.release), fixture.policy)
        XCTAssertEqual(try dispositionRow.value(release: fixture.release), fixture.disposition)
        XCTAssertEqual(
            try decisionRow.value(
                profile: fixture.profile,
                policy: fixture.policy,
                disposition: fixture.disposition,
                release: fixture.release
            ),
            decision
        )
        assertLinkedValidationRequired { try PackageLifecyclePolicyRow(fixture.policy) }
        assertLinkedValidationRequired { try PackageLifecycleDispositionRow(fixture.disposition) }
        assertLinkedValidationRequired { try ClientCapabilityAdmissionDecisionRow(decision) }
        assertLinkedValidationRequired { try policyRow.value() }
        assertLinkedValidationRequired { try dispositionRow.value() }
        assertLinkedValidationRequired { try decisionRow.value() }

        let invalidPolicy = try ClientCapabilityCanonicalCodecV1.decode(
            PackageLifecyclePolicyV1.self,
            from: forgedCanonicalData(
                fixture.policy,
                replacing: "policySHA256",
                with: C21ClientCapabilityTestSupport.digest("b")
            )
        )
        XCTAssertThrowsError(
            try PackageLifecyclePolicyRow(invalidPolicy, release: fixture.release)
        )
        let invalidDisposition = try ClientCapabilityCanonicalCodecV1.decode(
            PackageLifecycleDispositionV1.self,
            from: forgedCanonicalData(
                fixture.disposition,
                replacing: "dispositionSHA256",
                with: C21ClientCapabilityTestSupport.digest("b")
            )
        )
        XCTAssertThrowsError(
            try PackageLifecycleDispositionRow(invalidDisposition, release: fixture.release)
        )
        let invalidDecision = try ClientCapabilityCanonicalCodecV1.decode(
            ClientCapabilityAdmissionDecisionV1.self,
            from: forgedCanonicalData(
                decision,
                replacing: "decisionSHA256",
                with: C21ClientCapabilityTestSupport.digest("b")
            )
        )
        XCTAssertThrowsError(
            try ClientCapabilityAdmissionDecisionRow(
                invalidDecision,
                profile: fixture.profile,
                policy: fixture.policy,
                disposition: fixture.disposition,
                release: fixture.release
            )
        )

        let successorProfile = try ClientCapabilityProfileV1(
            profileID: C21ClientCapabilityTestSupport.id(40),
            workspaceID: fixture.workspace,
            semanticRanges: fixture.ranges,
            emittedAt: C21ClientCapabilityTestSupport.fixedDate.addingTimeInterval(20),
            supersedesProfileID: fixture.profile.profileID,
            revision: fixture.profile.revision + 1,
            mutationID: C21ClientCapabilityTestSupport.mutation(41)
        )
        try successorProfile.validateSuccessor(of: fixture.profile)
        let reusedProfileMutation = try ClientCapabilityProfileV1(
            profileID: C21ClientCapabilityTestSupport.id(42),
            workspaceID: fixture.workspace,
            semanticRanges: fixture.ranges,
            emittedAt: C21ClientCapabilityTestSupport.fixedDate.addingTimeInterval(21),
            supersedesProfileID: fixture.profile.profileID,
            revision: fixture.profile.revision + 1,
            mutationID: fixture.profile.mutationID
        )
        XCTAssertThrowsError(
            try reusedProfileMutation.validateSuccessor(of: fixture.profile)
        )

        let successorPolicy = try PackageLifecyclePolicyV1(
            policyID: C21ClientCapabilityTestSupport.id(50),
            workspaceID: fixture.workspace,
            release: fixture.release,
            requiredCapabilities: fixture.policy.requiredCapabilities,
            operationRules: fixture.policy.operationRules,
            effectiveAt: C21ClientCapabilityTestSupport.fixedDate.addingTimeInterval(22),
            supersedesPolicyID: fixture.policy.policyID,
            revision: fixture.policy.revision + 1,
            mutationID: try C21ClientCapabilityTestSupport.mutation(51)
        )
        try successorPolicy.validateSuccessor(of: fixture.policy, release: fixture.release)
        let reusedPolicyMutation = try PackageLifecyclePolicyV1(
            policyID: C21ClientCapabilityTestSupport.id(52),
            workspaceID: fixture.workspace,
            release: fixture.release,
            requiredCapabilities: fixture.policy.requiredCapabilities,
            operationRules: fixture.policy.operationRules,
            effectiveAt: C21ClientCapabilityTestSupport.fixedDate.addingTimeInterval(23),
            supersedesPolicyID: fixture.policy.policyID,
            revision: fixture.policy.revision + 1,
            mutationID: fixture.policy.mutationID
        )
        XCTAssertThrowsError(
            try reusedPolicyMutation.validateSuccessor(
                of: fixture.policy,
                release: fixture.release
            )
        )

        let successorDisposition = try PackageLifecycleDispositionV1(
            dispositionID: C21ClientCapabilityTestSupport.id(60),
            workspaceID: fixture.workspace,
            release: fixture.release,
            state: .active,
            reason: "C21 successor disposition",
            recordedAt: C21ClientCapabilityTestSupport.fixedDate.addingTimeInterval(24),
            supersedesDispositionID: fixture.disposition.dispositionID,
            revision: fixture.disposition.revision + 1,
            mutationID: try C21ClientCapabilityTestSupport.mutation(61)
        )
        try successorDisposition.validateSuccessor(
            of: fixture.disposition,
            release: fixture.release
        )
        let reusedDispositionMutation = try PackageLifecycleDispositionV1(
            dispositionID: C21ClientCapabilityTestSupport.id(62),
            workspaceID: fixture.workspace,
            release: fixture.release,
            state: .active,
            reason: "C21 reused disposition mutation",
            recordedAt: C21ClientCapabilityTestSupport.fixedDate.addingTimeInterval(25),
            supersedesDispositionID: fixture.disposition.dispositionID,
            revision: fixture.disposition.revision + 1,
            mutationID: fixture.disposition.mutationID
        )
        XCTAssertThrowsError(
            try reusedDispositionMutation.validateSuccessor(
                of: fixture.disposition,
                release: fixture.release
            )
        )
        let writer = C21RecordingCapabilityWriter()
        let coordinator = ClientCapabilityCoordinatorV1(writer: writer)
        let firstReceipt = try coordinator.recordProfile(fixture.profile)
        let retryReceipt = try coordinator.recordProfile(fixture.profile)
        XCTAssertEqual(firstReceipt, retryReceipt)
        XCTAssertEqual(writer.applyCount, 1)
        XCTAssertEqual(
            ClientCapabilityLifecycleAdapterV1(
                writer: writer
            ).disposition(existingReceiptMatchesMutation: true),
            .retainCanonicalHistory
        )
        XCTAssertEqual(
            ClientCapabilityLifecycleAdapterV1(
                writer: writer
            ).disposition(existingReceiptMatchesMutation: false),
            .quarantineDivergentRetry
        )
        XCTAssertTrue(
            WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(
                .applyClientCapability
            )
        )
    }

    func testV23P03C21R01V20BackupRestoreDeleteEraseReplayAndWithdrawalPreserveHistory() throws {
        let corpus = try loadCorpus()
        C21ClientCapabilityTestSupport.assertHeader(corpus)
        let fixture = try C21ClientCapabilityTestSupport.makeFixture(state: .withdrawn)

        for operation in PackageLifecycleOperationV1.allCases {
            let result = ClientCapabilityAdmissionEvaluatorV1.evaluate(
                profile: fixture.profile,
                policy: fixture.policy,
                disposition: fixture.disposition,
                release: fixture.release,
                operation: operation
            )
            if [.view, .export, .restore, .replay].contains(operation) {
                XCTAssertEqual(result.0, .readOnly)
                XCTAssertEqual(result.1, [.readOnlyCompatibility])
            } else {
                XCTAssertEqual(result.0, .reject)
                XCTAssertEqual(result.1, [.packageWithdrawn])
            }
        }

        try fixture.release.validate()
        let packageBytes = fixture.release.canonicalPackageBytes
        let workflowBytes = fixture.release.canonicalWorkflowBytes
        XCTAssertEqual(packageBytes, fixture.release.canonicalPackageBytes)
        XCTAssertEqual(workflowBytes, fixture.release.canonicalWorkflowBytes)

        let reboundedProfile = try fixture.profile.rebound(
            to: WorkspaceID(rawValue: C21ClientCapabilityTestSupport.id(1000))
        )
        XCTAssertNotEqual(reboundedProfile.workspaceID, fixture.workspace)
        XCTAssertEqual(reboundedProfile.profileID, fixture.profile.profileID)
        XCTAssertEqual(reboundedProfile.semanticRanges, fixture.profile.semanticRanges)

        let binding = try PackageReleaseBindingV1(
            bindingID: "c21-historic-release",
            kind: .export,
            publication: try InspectionPackageReleasePublisherV1.publish(
                InspectionPackageReleasePublisherV1.test(
                    try InspectionPackageReleaseV1.makeDraft(
                        package: ShippingIlluminatedSignAdapterV1.inspectionPackage(),
                        workflow: try C21ClientCapabilityTestSupport.workflowForBinding()
                    )
                )
            )
        )
        try binding.validate()
        XCTAssertEqual(binding.packageReleaseID, fixture.release.packageReleaseID)
        XCTAssertEqual(binding.canonicalPackageBytes, packageBytes)
        XCTAssertEqual(binding.canonicalWorkflowBytes, workflowBytes)

        // A binding is admitted only from the complete, linked capability
        // closure.  A forged decision digest and a decision linked to a
        // different profile both retain the same release/operation/admission
        // fields, but must not cross the binding boundary.
        let activeFixture = try C21ClientCapabilityTestSupport.makeFixture()
        let activeDecision = try XCTUnwrap(activeFixture.decisions[.start])
        let validClosure = ClientCapabilityLifecycleClosureV1(
            profile: activeFixture.profile,
            policy: activeFixture.policy,
            disposition: activeFixture.disposition,
            decision: activeDecision,
            release: activeFixture.release
        )
        XCTAssertNoThrow(
            try binding.validateClientAdmission(
                validClosure,
                operation: .start,
                forWrite: true
            )
        )
        let forgedDecision = try ClientCapabilityCanonicalCodecV1.decode(
            ClientCapabilityAdmissionDecisionV1.self,
            from: forgedCanonicalData(
                activeDecision,
                replacing: "decisionSHA256",
                with: C21ClientCapabilityTestSupport.digest("c")
            )
        )
        let forgedClosure = ClientCapabilityLifecycleClosureV1(
            profile: activeFixture.profile,
            policy: activeFixture.policy,
            disposition: activeFixture.disposition,
            decision: forgedDecision,
            release: activeFixture.release
        )
        XCTAssertThrowsError(
            try binding.validateClientAdmission(
                forgedClosure,
                operation: .start,
                forWrite: true
            )
        )
        let alternateProfile = try ClientCapabilityProfileV1(
            profileID: C21ClientCapabilityTestSupport.id(901),
            workspaceID: activeFixture.workspace,
            semanticRanges: activeFixture.ranges,
            emittedAt: C21ClientCapabilityTestSupport.fixedDate.addingTimeInterval(30),
            mutationID: try C21ClientCapabilityTestSupport.mutation(902)
        )
        let unclosedClosure = ClientCapabilityLifecycleClosureV1(
            profile: alternateProfile,
            policy: activeFixture.policy,
            disposition: activeFixture.disposition,
            decision: activeDecision,
            release: activeFixture.release
        )
        XCTAssertThrowsError(
            try binding.validateClientAdmission(
                unclosedClosure,
                operation: .start,
                forWrite: true
            )
        )
    }

    func testClientCapabilityAdmissionGatesDraftUpgrade() throws {
        let migrationOnly = try C21ClientCapabilityTestSupport.makeFixture(
            state: .deprecated
        )
        let deniedDecision = try XCTUnwrap(migrationOnly.decisions[.upgradeDraft])
        let deniedClosure = ClientCapabilityLifecycleClosureV1(
            profile: migrationOnly.profile,
            policy: migrationOnly.policy,
            disposition: migrationOnly.disposition,
            decision: deniedDecision,
            release: migrationOnly.release
        )
        XCTAssertThrowsError(
            try PackageEvolutionLifecycleAdapterV1.validateClientCapabilityClosure(
                deniedClosure
            )
        )
        XCTAssertEqual(
            PackageEvolutionDraftPersistenceBoundaryV1.capabilityDecisionOperation,
            .upgradeDraft
        )
        XCTAssertFalse(PackageEvolutionDraftPersistenceBoundaryV1.capabilityInputsPersistent)

        // Keep this call shape compiled in the test target: the coordinator's
        // only draft-upgrade entry point carries the complete admission
        // closure; there is no legacy ungated coordinator overload.
        let type: Any.Type = PackageEvolutionCoordinatorV1.self
        XCTAssertNotNil(type)
    }

    private func loadCorpus() throws -> C21Corpus {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V21P03C21ClientCapabilityPackageLifecycleCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/PackageLifecycle"
            ) ?? bundle.url(
                forResource: "V21P03C21ClientCapabilityPackageLifecycleCorpusV1",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(C21Corpus.self, from: Data(contentsOf: url))
    }

    private func assertLinkedValidationRequired(
        _ operation: () throws -> Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard case .linkedValidationRequired = error as? ClientCapabilityPersistenceFailureV1 else {
                XCTFail("expected linked validation failure", file: file, line: line)
                return
            }
        }
    }

    private func forgedCanonicalData<T: Encodable>(
        _ value: T,
        replacing field: String,
        with replacement: Any
    ) throws -> Data {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: ClientCapabilityCanonicalCodecV1.encode(value)
            ) as? [String: Any]
        )
        object[field] = replacement
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }
}

@MainActor
private func c21ApplyGatedDraftUpgrade(
    coordinator: PackageEvolutionCoordinatorV1,
    plan: DraftUpgradePlanV1,
    source: FieldDraftCheckpointV1,
    diff: PackageSemanticDiffV1,
    mutationID: MutationIDV1,
    updatedAt: Date,
    admittedBy closure: ClientCapabilityLifecycleClosureV1
) throws -> MutationReceiptV1 {
    try coordinator.applyDraftUpgrade(
        plan: plan,
        source: source,
        diff: diff,
        mutationID: mutationID,
        updatedAt: updatedAt,
        admittedBy: closure
    )
}

@MainActor
private final class C21RecordingCapabilityWriter: ClientCapabilityWritingV1 {
    private var receipts: [MutationIDV1: ClientCapabilityWriteReceiptV1] = [:]
    private(set) var applyCount = 0

    func acceptedWriteReceipt(for mutation: ClientCapabilityMutationV1) throws -> ClientCapabilityWriteReceiptV1? {
        receipts[mutation.mutationID]
    }

    func applyClientCapability(_ mutation: ClientCapabilityMutationV1) throws -> ClientCapabilityWriteReceiptV1 {
        try mutation.validate()
        applyCount += 1
        let postImage: String
        switch mutation {
        case let .profile(value): postImage = value.profileSHA256
        case let .policy(value, _): postImage = value.policySHA256
        case let .disposition(value, _): postImage = value.dispositionSHA256
        case let .admission(value, _, _, _, _): postImage = value.decisionSHA256
        }
        let receipt = try ClientCapabilityWriteReceiptV1(
            mutationID: mutation.mutationID,
            postImageSHA256: postImage,
            canonicalMutationReceiptSHA256: C21ClientCapabilityTestSupport.digest()
        )
        receipts[mutation.mutationID] = receipt
        return receipt
    }
}

private extension C21ClientCapabilityTestSupport {
    static func workflowForBinding() throws -> WorkflowDefinitionV1 {
        try WorkflowDefinitionV1(
            workflowID: "c21.workflow.capability.v1",
            entryNodeID: "c21.start",
            declaredFieldIDs: [],
            nodes: [
                try WorkflowNodeV1(
                    nodeID: "c21.start",
                    kind: .section,
                    localizationKey: "c21.start",
                    outgoingNodeIDs: ["c21.end"]
                ),
                try WorkflowNodeV1(
                    nodeID: "c21.end",
                    kind: .terminal,
                    localizationKey: "c21.end",
                    outgoingNodeIDs: []
                )
            ]
        )
    }
}

extension V9_35ClientCapabilityPackageLifecycleTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorV935ClientCapabilityPackageLifecycleTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}
