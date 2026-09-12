import CryptoKit
import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V23ActivityOrderingTests: XCTestCase {
    func testBundledActivityReleasesKeepCanonicalOrdinalOrderWhenIDsAreNonlexical() throws {
        let workspaceID = WorkspaceID(rawValue: id(1))
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let registry = try InspectionPackageRegistryV2(packages: [package])

        let installation = try registry.bundledActivityWorkflowRelease(
            kind: .installation,
            packageID: ShippingIlluminatedSignAdapterV1.packageID,
            workspaceID: workspaceID
        )
        guard case let .installation(installationRelease) = installation.release else {
            return XCTFail("Expected the bundled installation release")
        }
        XCTAssertEqual(
            installationRelease.tasks.map(\.taskID),
            ["identify-subject", "record-placement", "record-as-built"]
        )
        XCTAssertNoThrow(try installationRelease.validate())

        let punch = try registry.bundledActivityWorkflowRelease(
            kind: .punchReview,
            packageID: ShippingIlluminatedSignAdapterV1.packageID,
            workspaceID: workspaceID
        )
        guard case let .punch(punchRelease) = punch.release else {
            return XCTFail("Expected the bundled punch-review release")
        }
        XCTAssertEqual(
            punchRelease.scope.map(\.scopeItemID),
            ["review-recorded-scope", "record-findings"]
        )
        XCTAssertNoThrow(try punchRelease.validate())
    }

    func testActivityReleaseOrderingAcceptsUniqueNonlexicalIDsAndRejectsDuplicateIdentityOrOrdinal() throws {
        let workspaceID = WorkspaceID(rawValue: id(10))
        let installationPolicy = try InstallationReadinessPolicyV1(requiredFacets: [.subject])
        let firstTask = try InstallationTaskDefinitionV1(
            taskID: "z-first", ordinal: 0, title: "First by ordinal", evidencePurposes: [.subjectIdentity]
        )
        let secondTask = try InstallationTaskDefinitionV1(
            taskID: "a-second", ordinal: 1, title: "Second by ordinal", evidencePurposes: [.placementContext]
        )
        let installation = try InstallationWorkflowDefinitionReleaseV1(
            releaseID: id(11), workspaceID: workspaceID, tasks: [secondTask, firstTask],
            readinessPolicy: installationPolicy, revision: 1, mutationID: try mutation(12)
        )
        XCTAssertEqual(installation.tasks.map(\.taskID), ["z-first", "a-second"])

        XCTAssertThrowsError(try InstallationWorkflowDefinitionReleaseV1(
            releaseID: id(13), workspaceID: workspaceID,
            tasks: [
                firstTask,
                try InstallationTaskDefinitionV1(
                    taskID: firstTask.taskID, ordinal: 1, title: "Duplicate ID",
                    evidencePurposes: [.placementContext]
                ),
            ],
            readinessPolicy: installationPolicy, revision: 1, mutationID: try mutation(14)
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .invalidValue)
        }
        XCTAssertThrowsError(try InstallationWorkflowDefinitionReleaseV1(
            releaseID: id(15), workspaceID: workspaceID,
            tasks: [
                firstTask,
                try InstallationTaskDefinitionV1(
                    taskID: "a-same-ordinal", ordinal: 0, title: "Duplicate ordinal",
                    evidencePurposes: [.placementContext]
                ),
            ],
            readinessPolicy: installationPolicy, revision: 1, mutationID: try mutation(16)
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .invalidValue)
        }

        let punchPolicy = try PunchReviewReadinessPolicyV1(requiredFacets: [.subject])
        let firstScope = try PunchReviewScopeItemV1(
            scopeItemID: "z-first", ordinal: 0, title: "First by ordinal"
        )
        let secondScope = try PunchReviewScopeItemV1(
            scopeItemID: "a-second", ordinal: 1, title: "Second by ordinal"
        )
        let punch = try PunchReviewWorkflowDefinitionReleaseV1(
            releaseID: id(20), workspaceID: workspaceID, scope: [secondScope, firstScope],
            readinessPolicy: punchPolicy, revision: 1, mutationID: try mutation(21)
        )
        XCTAssertEqual(punch.scope.map(\.scopeItemID), ["z-first", "a-second"])

        XCTAssertThrowsError(try PunchReviewWorkflowDefinitionReleaseV1(
            releaseID: id(22), workspaceID: workspaceID,
            scope: [
                firstScope,
                try PunchReviewScopeItemV1(
                    scopeItemID: firstScope.scopeItemID, ordinal: 1, title: "Duplicate ID"
                ),
            ],
            readinessPolicy: punchPolicy, revision: 1, mutationID: try mutation(23)
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .invalidValue)
        }
        XCTAssertThrowsError(try PunchReviewWorkflowDefinitionReleaseV1(
            releaseID: id(24), workspaceID: workspaceID,
            scope: [
                firstScope,
                try PunchReviewScopeItemV1(
                    scopeItemID: "a-same-ordinal", ordinal: 0, title: "Duplicate ordinal"
                ),
            ],
            readinessPolicy: punchPolicy, revision: 1, mutationID: try mutation(25)
        )) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .invalidValue)
        }
    }

    func testDecodedActivityReleaseRejectsReorderedCanonicalCollections() throws {
        let workspaceID = WorkspaceID(rawValue: id(30))
        let installation = try InstallationWorkflowDefinitionReleaseV1(
            releaseID: id(31), workspaceID: workspaceID,
            tasks: [
                try InstallationTaskDefinitionV1(
                    taskID: "z-first", ordinal: 0, title: "First by ordinal",
                    evidencePurposes: [.subjectIdentity]
                ),
                try InstallationTaskDefinitionV1(
                    taskID: "a-second", ordinal: 1, title: "Second by ordinal",
                    evidencePurposes: [.placementContext]
                ),
            ],
            readinessPolicy: try InstallationReadinessPolicyV1(requiredFacets: [.subject]),
            revision: 1, mutationID: try mutation(32)
        )
        let reorderedInstallation = try decodeReordered(
            installation, collectionKey: "tasks", as: InstallationWorkflowDefinitionReleaseV1.self
        )
        XCTAssertThrowsError(try reorderedInstallation.validate()) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .invalidValue)
        }

        let punch = try PunchReviewWorkflowDefinitionReleaseV1(
            releaseID: id(40), workspaceID: workspaceID,
            scope: [
                try PunchReviewScopeItemV1(
                    scopeItemID: "z-first", ordinal: 0, title: "First by ordinal"
                ),
                try PunchReviewScopeItemV1(
                    scopeItemID: "a-second", ordinal: 1, title: "Second by ordinal"
                ),
            ],
            readinessPolicy: try PunchReviewReadinessPolicyV1(requiredFacets: [.subject]),
            revision: 1, mutationID: try mutation(41)
        )
        let reorderedPunch = try decodeReordered(
            punch, collectionKey: "scope", as: PunchReviewWorkflowDefinitionReleaseV1.self
        )
        XCTAssertThrowsError(try reorderedPunch.validate()) { error in
            XCTAssertEqual(error as? ActivityContractFailureV2, .invalidValue)
        }
    }

    private func decodeReordered<Value: Codable>(
        _ value: Value,
        collectionKey: String,
        as type: Value.Type
    ) throws -> Value {
        let data = try WorkspaceMutationCanonicalV1.data(value)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let collection = try XCTUnwrap(object[collectionKey] as? [[String: Any]])
        object[collectionKey] = Array(collection.reversed())
        var basis = object
        basis.removeValue(forKey: "releaseSHA256")
        let basisData = try JSONSerialization.data(
            withJSONObject: basis,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        object["releaseSHA256"] = SHA256.hash(data: basisData)
            .map { String(format: "%02x", $0) }
            .joined()
        let reordered = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: reordered)
    }

    private func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "a2300000-0000-4000-8000-%012x", slot))!
    }

    private func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }
}
