import CryptoKit
import Foundation
import XCTest

final class V9_92ExactCandidateRegressionFreezeTests: XCTestCase {
    private let corpusPath = "FieldEvidenceAppTests/Fixtures/V21/Brand/V23P04C29ExactCandidateRegressionFreezeCorpusV1.json"

    func testV23P04C29G01ExactCandidateFreezeBindsBrandHIGAccessibilityLocalizationJourneyAndReleaseState() throws {
        let corpus = try object(corpusPath)
        XCTAssertEqual(corpus["schema"] as? String, "V23P04C29ExactCandidateRegressionFreezeCorpusV1")
        XCTAssertEqual(corpus["schemaVersion"] as? Int, 1)
        XCTAssertEqual(corpus["cardID"] as? String, "V23-P04-C29")
        XCTAssertEqual(corpus["syntheticOnly"] as? Bool, true)
        XCTAssertEqual(corpus["containsCustomerData"] as? Bool, false)
        XCTAssertTrue(c29Valid(corpus))

        let authority = try dictionary(corpus, "authority")
        XCTAssertEqual(authority["coordinationHead"] as? String, "3be7e1ac1cb8e8c046f4a02d8c6c450a14078c05")
        XCTAssertEqual(authority["coordinationTree"] as? String, "60748a754f7fb5e2ce12af18df1fe8414aa20ffb")
        XCTAssertEqual(authority["hydrationSequence"] as? Int, 512)
        XCTAssertEqual(authority["appBaseHead"] as? String, "8b97b33a0c83d639349d9c28806092fdeb79b95f")
        XCTAssertEqual(authority["appBaseTree"] as? String, "0c804ceb7b50a5b804b1380762408aedac644d2d")

        try assertPrerequisiteJoins(corpus)
        try assertProductLedgerJoin(corpus)
        let candidate = try dictionary(corpus, "candidateFreeze")
        XCTAssertEqual(candidate["acceptanceMode"] as? String, "FAIL_FAST_EXACT_CANDIDATE")
        XCTAssertEqual(candidate["maximumShardCount"] as? Int, 5)
        XCTAssertEqual(candidate["sealed"] as? Bool, false)
        XCTAssertTrue(candidate["candidateHead"] is NSNull)
        XCTAssertTrue(candidate["candidateTree"] is NSNull)
        XCTAssertEqual(candidate["completeMatrixStatus"] as? String, "NOT_RUN")
        XCTAssertEqual(try strings(candidate, "contracts"), [
            "ReleaseStateCandidateManifestV1",
            "V21ReleaseBrandBaselineManifestV1",
            "ApplicationBrandAcceptanceReceiptV1",
            "AppStoreAccessibilityLabelPayloadV1",
            "AppIconReleaseVerificationReceiptV1",
        ])

        let rows = try dictionaries(corpus, "evidenceRows")
        XCTAssertEqual(try rows.map { try string($0, "evidenceID") }, [
            "V23-P04-C29-G01", "V23-P04-C29-A01", "V23-P04-C29-H01",
            "V23-P04-C29-I01", "V23-P04-C29-R01",
        ])
        XCTAssertTrue(rows.allSatisfy { $0["acceptanceCredit"] as? Bool == false })
        XCTAssertTrue(rows.allSatisfy { ($0["blockers"] as? [String])?.isEmpty == false })
        try assertBlockedEvidence(corpus)
    }

    func testV23P04C29A01MinimumIOS18AndLatestStableResolveSeparatelyWithSemanticParity() throws {
        let corpus = try object(corpusPath)
        let profiles = try dictionaries(corpus, "runtimeProfiles")
        XCTAssertEqual(try profiles.map { try string($0, "profileID") }, [
            "MINIMUM_IOS_18", "LATEST_ACCEPTED_STABLE_SHIPPING_RUNTIME",
        ])
        XCTAssertEqual(try profiles.map { try string($0, "baselineScope") }, [
            "MINIMUM_IOS_18_RUNTIME_SPECIFIC", "LATEST_STABLE_RUNTIME_SPECIFIC",
        ])
        XCTAssertTrue(profiles.allSatisfy { $0["status"] as? String == "NOT_RUN" })
        XCTAssertTrue(profiles.allSatisfy { $0["resolvedRuntime"] is NSNull })
        XCTAssertTrue(profiles.allSatisfy { $0["acceptanceCredit"] as? Bool == false })
        XCTAssertEqual(try strings(corpus, "semanticParityDimensions"), [
            "ACCESSIBILITY", "ACTION", "CONTENT", "DATA_TRUTH", "DURABILITY", "ROUTE", "TASK",
        ])
        XCTAssertNotEqual(profiles[0]["baselineScope"] as? String, profiles[1]["baselineScope"] as? String)
        let diagnostics = try dictionary(corpus, "diagnosticPolicy")
        XCTAssertEqual(diagnostics["acceptanceEligible"] as? Bool, false)
        XCTAssertEqual(diagnostics["promotionAllowed"] as? Bool, false)
    }

    func testV23P04C29H01UnknownStaleCorruptCoverageContrastAccessibilityLocalizationJourneyAndReleaseDriftFailClosed() throws {
        let pristine = try object(corpusPath)
        XCTAssertTrue(c29Valid(pristine))
        XCTAssertEqual(try dictionaries(pristine, "hostileCases").map { try string($0, "caseID") }, [
            "H01_UNKNOWN_ENUM_OR_RECORD", "H02_STALE_CANDIDATE_HEAD_OR_TREE",
            "H03_CORRUPT_MANIFEST_OR_RECEIPT", "H04_UNAUTHORIZED_ARTIFACT_PATH",
            "H05_SOURCE_OR_ARTIFACT_HASH_MISMATCH", "H06_MISSING_STATE_OR_CONSUMER_COVERAGE",
            "H07_EXPIRED_CONTRAST_EXCEPTION", "H08_ACCESSIBILITY_AUDIT_FAILURE",
            "H09_LOCALIZATION_PSEUDO_OR_RTL_DRIFT", "H10_JOURNEY_SEMANTIC_GAP",
            "H11_RELEASE_STATE_OR_PACKAGE_DRIFT", "H12_DIAGNOSTIC_PROMOTED_TO_ACCEPTANCE",
        ])

        let mutations: [(String, (inout [String: Any]) throws -> Void)] = [
            ("unknown", { root in try self.mutateObject("candidateFreeze", key: "acceptanceMode", value: "UNKNOWN", root: &root) }),
            ("stale", { root in try self.mutateObject("authority", key: "appBaseHead", value: String(repeating: "0", count: 40), root: &root) }),
            ("corrupt", { root in root["candidateFreeze"] = "corrupt" }),
            ("path", { root in
                var value = try self.dictionary(root, "candidateFreeze")
                var paths = try self.strings(value, "allowedArtifactPaths")
                paths.append("unowned/path.json")
                value["allowedArtifactPaths"] = paths
                root["candidateFreeze"] = value
            }),
            ("hash", { root in
                var prerequisites = try self.dictionary(root, "prerequisites")
                var c28 = try self.dictionary(prerequisites, "V23-P04-C28")
                c28["ledgerSHA256"] = String(repeating: "a", count: 64)
                prerequisites["V23-P04-C28"] = c28
                root["prerequisites"] = prerequisites
            }),
            ("coverage", { root in try self.mutateObject("blockedEvidence", key: "coverage", value: "NOT_RUN", root: &root) }),
            ("contrast", { root in try self.mutateObject("negativeClaims", key: "expiredContrastExceptionCount", value: 1, root: &root) }),
            ("accessibility", { root in try self.mutateObject("blockedEvidence", key: "accessibility", value: "ACCEPTED", root: &root) }),
            ("localization", { root in try self.mutateObject("blockedEvidence", key: "localization", value: "ACCEPTED", root: &root) }),
            ("journey", { root in try self.mutateObject("blockedEvidence", key: "journeys", value: "ACCEPTED", root: &root) }),
            ("release", { root in try self.mutateObject("blockedEvidence", key: "releaseState", value: "ACCEPTED", root: &root) }),
            ("diagnostic", { root in try self.mutateObject("diagnosticPolicy", key: "acceptanceEligible", value: true, root: &root) }),
        ]
        for (label, mutate) in mutations {
            var hostile = pristine
            try mutate(&hostile)
            XCTAssertFalse(c29Valid(hostile), label)
        }
    }

    func testV23P04C29I01ManifestLastInterruptionPreservesCandidateAndNoPartialReceipt() throws {
        let corpus = try object(corpusPath)
        let recovery = try dictionary(corpus, "manifestLastRecovery")
        XCTAssertEqual(recovery["protocol"] as? String, "MANIFEST_LAST_ATOMIC_REPLACE")
        XCTAssertEqual(recovery["deterministicRetry"] as? Bool, true)
        let boundaries = try dictionaries(recovery, "boundaries")
        XCTAssertEqual(try boundaries.map { try string($0, "boundary") }, [
            "BEFORE_ARTIFACTS", "AFTER_ARTIFACTS_BEFORE_MANIFEST", "AFTER_MANIFEST",
        ])
        XCTAssertEqual(try boundaries.map { try integer($0, "acceptedSetCount") }, [0, 0, 1])
        XCTAssertEqual(try boundaries.map { try integer($0, "partialReceiptCount") }, [0, 0, 0])
        XCTAssertEqual(try boundaries.map { try integer($0, "retryAcceptedSetCount") }, [1, 1, 1])
        try assertPrerequisiteJoins(corpus)
    }

    func testV23P04C29R01DeterministicRetryPreservesFrozenCandidateWithoutPromotion() throws {
        let corpus = try object(corpusPath)
        let recovery = try dictionary(corpus, "manifestLastRecovery")
        XCTAssertEqual(recovery["deterministicRetry"] as? Bool, true)
        let negative = try dictionary(corpus, "negativeClaims")
        XCTAssertEqual(Set(negative.keys), [
            "accessibilityPhysicalPromotion", "appStorePromotion", "expiredContrastExceptionCount",
            "nativeIPadClaim", "publicClaimDrift", "releaseSigning",
            "telemetryOrCustomerDataCollection", "testFlightUpload",
        ])
        XCTAssertEqual(negative["expiredContrastExceptionCount"] as? Int, 0)
        for key in negative.keys where key != "expiredContrastExceptionCount" {
            XCTAssertEqual(negative[key] as? Bool, false, key)
        }
        let flags = try dictionary(corpus, "statusFlags")
        XCTAssertTrue(flags.values.allSatisfy { $0 as? Bool == false })
        let diagnostics = try dictionary(corpus, "diagnosticPolicy")
        XCTAssertEqual(diagnostics["promotionAllowed"] as? Bool, false)
        XCTAssertTrue(c29Valid(corpus))
    }

    private func c29Valid(_ root: [String: Any]) -> Bool {
        do { return try c29ValidUnchecked(root) } catch { return false }
    }

    private func c29ValidUnchecked(_ root: [String: Any]) throws -> Bool {
        guard Set(root.keys) == [
            "authority", "blockedEvidence", "candidateFreeze", "cardID", "containsCustomerData",
            "diagnosticPolicy", "evidenceRows", "hostileCases", "manifestLastRecovery",
            "negativeClaims", "prerequisites", "productLedger", "runtimeProfiles", "schema", "schemaVersion",
            "selectors", "semanticParityDimensions", "statusFlags", "syntheticOnly",
        ], root["cardID"] as? String == "V23-P04-C29",
           root["schema"] as? String == "V23P04C29ExactCandidateRegressionFreezeCorpusV1" else { return false }

        let authority = try dictionary(root, "authority")
        guard authority["coordinationHead"] as? String == "3be7e1ac1cb8e8c046f4a02d8c6c450a14078c05",
              authority["coordinationTree"] as? String == "60748a754f7fb5e2ce12af18df1fe8414aa20ffb",
              authority["hydrationSequence"] as? Int == 512,
              authority["appBaseHead"] as? String == "8b97b33a0c83d639349d9c28806092fdeb79b95f",
              authority["appBaseTree"] as? String == "0c804ceb7b50a5b804b1380762408aedac644d2d" else { return false }

        let candidate = try dictionary(root, "candidateFreeze")
        guard candidate["acceptanceMode"] as? String == "FAIL_FAST_EXACT_CANDIDATE",
              candidate["maximumShardCount"] as? Int == 5,
              candidate["sealed"] as? Bool == false,
              candidate["candidateHead"] is NSNull,
              candidate["candidateTree"] is NSNull,
              candidate["completeMatrixStatus"] as? String == "NOT_RUN",
              try strings(candidate, "allowedArtifactPaths") == exactArtifactPaths else { return false }

        let blocked = try dictionary(root, "blockedEvidence")
        guard Set(blocked.keys) == [
            "acceptedS10_6", "accessibility", "contrast", "coverage", "journeys",
            "localization", "nativeCandidate", "releaseState",
        ], blocked["acceptedS10_6"] as? String == "BLOCKED",
           blocked["accessibility"] as? String == "NOT_RUN",
           blocked["contrast"] as? String == "NOT_RUN",
           blocked["coverage"] as? String == "BLOCKED",
           blocked["journeys"] as? String == "NOT_RUN",
           blocked["localization"] as? String == "NOT_RUN",
           blocked["nativeCandidate"] as? String == "NOT_RUN",
           blocked["releaseState"] as? String == "NOT_RUN" else { return false }

        let diagnostics = try dictionary(root, "diagnosticPolicy")
        guard diagnostics["acceptanceEligible"] as? Bool == false,
              diagnostics["promotionAllowed"] as? Bool == false,
              diagnostics["status"] as? String == "NOT_RUN" else { return false }

        let negative = try dictionary(root, "negativeClaims")
        guard negative["expiredContrastExceptionCount"] as? Int == 0,
              negative.filter({ $0.key != "expiredContrastExceptionCount" })
                .allSatisfy({ $0.value as? Bool == false }) else { return false }

        let c28 = try dictionary(dictionary(root, "prerequisites"), "V23-P04-C28")
        guard c28["ledgerSHA256"] as? String == "3edc52a47c91c4b79238380bdad92f6a2a1e0ebd0d1084a2e1ad7ae0e6238e14",
              c28["corpusSHA256"] as? String == "e1a6230e1f4b0b0e758a6a48fe764e1e2fce5a1dc17d9752c0f1e7e774c01dee" else { return false }
        let productLedger = try dictionary(root, "productLedger")
        guard productLedger["path"] as? String == "docs/product/brand/V23P04C29ExactCandidateRegressionFreezeV1.json",
              productLedger["schema"] as? String == "V23P04C29ExactCandidateRegressionFreezeV1" else { return false }

        let rows = try dictionaries(root, "evidenceRows")
        guard rows.count == 5,
              rows.allSatisfy({ $0["acceptanceCredit"] as? Bool == false }),
              try dictionaries(root, "hostileCases").count == 12,
              try dictionaries(root, "runtimeProfiles").count == 2 else { return false }
        return true
    }

    private func assertPrerequisiteJoins(_ corpus: [String: Any]) throws {
        let prerequisites = try dictionary(corpus, "prerequisites")
        XCTAssertEqual(Set(prerequisites.keys), ["V23-P00-C13", "V23-P04-C27", "V23-P04-C28"])
        let coverage = try dictionary(prerequisites, "V23-P00-C13")
        XCTAssertEqual(coverage["checkpointDigest"] as? String, "8aa76625bee8c70277a41e2212f814604dac32f4600ab1954db4af4c90713b47")
        XCTAssertEqual(coverage["verificationReceiptDigest"] as? String, "cba3785a50588c1bceddaaaabac2736b2256c3da017bd31eaef8f124342f4482")
        XCTAssertEqual(coverage["xccovStatus"] as? String, "NOT_RUN")
        XCTAssertEqual(coverage["acceptedS10_6Comparison"] as? String, "UNRESOLVED_ACCEPTANCE_BLOCKER")

        let c27 = try dictionary(prerequisites, "V23-P04-C27")
        XCTAssertEqual(try sha256(data(try string(c27, "inventoryPath"))), c27["inventorySHA256"] as? String)
        let c28 = try dictionary(prerequisites, "V23-P04-C28")
        XCTAssertEqual(try sha256(data(try string(c28, "ledgerPath"))), c28["ledgerSHA256"] as? String)
        XCTAssertEqual(try sha256(data(try string(c28, "corpusPath"))), c28["corpusSHA256"] as? String)
        XCTAssertEqual(c28["acceptedHead"] as? String, "8b97b33a0c83d639349d9c28806092fdeb79b95f")
        XCTAssertEqual(c28["acceptedTree"] as? String, "0c804ceb7b50a5b804b1380762408aedac644d2d")
    }

    private func assertBlockedEvidence(_ corpus: [String: Any]) throws {
        let blocked = try dictionary(corpus, "blockedEvidence")
        XCTAssertEqual(blocked["acceptedS10_6"] as? String, "BLOCKED")
        XCTAssertEqual(blocked["coverage"] as? String, "BLOCKED")
        for key in ["accessibility", "contrast", "journeys", "localization", "nativeCandidate", "releaseState"] {
            XCTAssertEqual(blocked[key] as? String, "NOT_RUN", key)
        }
    }

    private func assertProductLedgerJoin(_ corpus: [String: Any]) throws {
        let binding = try dictionary(corpus, "productLedger")
        let ledger = try object(try string(binding, "path"))
        XCTAssertEqual(ledger["schema"] as? String, binding["schema"] as? String)
        XCTAssertEqual(ledger["cardID"] as? String, "V23-P04-C29")
        XCTAssertEqual(ledger["classification"] as? String, "PREPARE_NOW")
        XCTAssertEqual(ledger["planningStatus"] as? String, "NOT_STARTED")
        XCTAssertEqual(ledger["selectors"] as? [String], corpus["selectors"] as? [String])
        let corpusAuthority = try dictionary(corpus, "authority")
        let ledgerAuthority = try dictionary(ledger, "authority")
        XCTAssertEqual(ledgerAuthority["coordinationHead"] as? String, corpusAuthority["coordinationHead"] as? String)
        XCTAssertEqual(ledgerAuthority["coordinationTree"] as? String, corpusAuthority["coordinationTree"] as? String)
        XCTAssertEqual(ledgerAuthority["sequence"] as? Int, corpusAuthority["hydrationSequence"] as? Int)
        XCTAssertEqual(ledgerAuthority["appBaseHead"] as? String, corpusAuthority["appBaseHead"] as? String)
        XCTAssertEqual(ledgerAuthority["appBaseTree"] as? String, corpusAuthority["appBaseTree"] as? String)
        XCTAssertEqual(ledgerAuthority["contextDigest"] as? String, corpusAuthority["contextDigest"] as? String)
        XCTAssertEqual(ledgerAuthority["pathFenceDigest"] as? String, corpusAuthority["fenceDigest"] as? String)
        XCTAssertEqual(ledgerAuthority["allocationDigest"] as? String, corpusAuthority["allocationDigest"] as? String)
        XCTAssertEqual(ledgerAuthority["prerequisiteDigest"] as? String, corpusAuthority["prerequisiteDigest"] as? String)
        XCTAssertEqual(ledgerAuthority["transitionDigest"] as? String, corpusAuthority["hydrationTransitionDigest"] as? String)
        let candidate = try dictionary(ledger, "candidate")
        XCTAssertEqual(candidate["head"] as? String, corpusAuthority["appBaseHead"] as? String)
        XCTAssertEqual(candidate["tree"] as? String, corpusAuthority["appBaseTree"] as? String)
        XCTAssertEqual(candidate["sealDisposition"] as? String, "UNSEALED_PROVISIONAL")
        let flags = try dictionary(ledger, "statusFlags")
        XCTAssertTrue(flags.values.allSatisfy { $0 as? Bool == false })

        let prerequisites = try dictionary(corpus, "prerequisites")
        let c27 = try dictionary(prerequisites, "V23-P04-C27")
        let c28 = try dictionary(prerequisites, "V23-P04-C28")
        let bindings = try dictionaries(ledger, "sourceBindings")
        let bindingSHAByPath = Dictionary(uniqueKeysWithValues: try bindings.map {
            (try string($0, "path"), try string($0, "sha256"))
        })
        XCTAssertEqual(
            bindingSHAByPath[try string(c27, "inventoryPath")],
            c27["inventorySHA256"] as? String
        )
        XCTAssertEqual(
            bindingSHAByPath[try string(c28, "ledgerPath")],
            c28["ledgerSHA256"] as? String
        )
        XCTAssertEqual(
            bindingSHAByPath["docs/design/v23/tooling/V23-P00-C13-tooling-manifest.json"],
            "1772fc652c01813addc9cbb1318a80415f2d9684b0f0f654d5b63581c22d1c35"
        )
        let coverage = try dictionary(ledger, "p00C13Coverage")
        XCTAssertEqual(coverage["required"] as? Bool, true)
        XCTAssertEqual(coverage["status"] as? String, "NOT_RUN")
        XCTAssertTrue(coverage["coverageEvidenceSHA256"] is NSNull)
        XCTAssertEqual(
            coverage["commonTaskJourneyReleaseSHA256"] as? String,
            bindingSHAByPath["docs/design/v23/tooling/CommonTaskJourneyReleaseV2.json"]
        )
        XCTAssertEqual(
            coverage["featureEndToEndJourneyReleaseSHA256"] as? String,
            bindingSHAByPath["docs/design/v23/tooling/FeatureEndToEndJourneyReleaseV1.json"]
        )
    }

    private var exactArtifactPaths: [String] {
        [
            "docs/product/brand/V23P04C29ExactCandidateRegressionFreezeV1.json",
            "docs/design/v23/tooling/V23P04C29ExactCandidateRegressionFreezeContractV1.json",
            "docs/design/v23/tooling/V23P04C29ExactCandidateRegressionFreezeEvidenceReceiptV1.json",
            "docs/design/v23/tooling/V23P04C29BrandImpactManifestV1.json",
            "docs/design/v23/tooling/V23-P04-C29-tooling-manifest.json",
        ]
    }

    private func mutateObject(
        _ objectKey: String, key: String, value: Any, root: inout [String: Any]
    ) throws {
        var object = try dictionary(root, objectKey)
        object[key] = value
        root[objectKey] = object
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func data(_ path: String) throws -> Data {
        try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
    }

    private func object(_ path: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(path)) as? [String: Any])
    }

    private func dictionary(_ root: [String: Any], _ key: String) throws -> [String: Any] {
        try XCTUnwrap(root[key] as? [String: Any], "missing object \(key)")
    }

    private func dictionaries(_ root: [String: Any], _ key: String) throws -> [[String: Any]] {
        try XCTUnwrap(root[key] as? [[String: Any]], "missing object array \(key)")
    }

    private func strings(_ root: [String: Any], _ key: String) throws -> [String] {
        try XCTUnwrap(root[key] as? [String], "missing string array \(key)")
    }

    private func string(_ root: [String: Any], _ key: String) throws -> String {
        try XCTUnwrap(root[key] as? String, "missing string \(key)")
    }

    private func integer(_ root: [String: Any], _ key: String) throws -> Int {
        try XCTUnwrap(root[key] as? Int, "missing integer \(key)")
    }

    private func sha256(_ value: Data) -> String {
        SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }
}
