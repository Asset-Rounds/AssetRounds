import CryptoKit
import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V9_91BrandHIGSharedRootCorrectionTests: XCTestCase {
    private let corpusPath = "FieldEvidenceAppTests/Fixtures/V21/Brand/V23P04C28BrandHIGSharedRootCorrectionCorpusV1.json"
    private let c27InventoryPath = "docs/product/brand/V23P04C27BrandHIGStateInventoryV1.json"

    func testV23P04C28G01LowestOwnerCorrectionsCloseC27FindingsAndPreserveHistoricReports() throws {
        let corpus = try object(corpusPath)
        XCTAssertEqual(corpus["schema"] as? String, "V23P04C28BrandHIGSharedRootCorrectionCorpusV1")
        XCTAssertEqual(corpus["schemaVersion"] as? Int, 1)
        XCTAssertEqual(corpus["cardID"] as? String, "V23-P04-C28")
        XCTAssertEqual(corpus["syntheticOnly"] as? Bool, true)
        XCTAssertEqual(corpus["containsCustomerData"] as? Bool, false)
        XCTAssertTrue(try c28Valid(corpus))

        let predecessor = try dictionary(corpus, "predecessor")
        XCTAssertEqual(predecessor["cardID"] as? String, "V23-P04-C27")
        XCTAssertEqual(predecessor["head"] as? String, "803f75bc94a46b7b0ca50b14f1a49401f38550f1")
        XCTAssertEqual(predecessor["tree"] as? String, "6f1cc0077cf74a1adb532124880b1cd5e4a031cc")
        XCTAssertEqual(try sha256(data(c27InventoryPath)), predecessor["inventorySHA256"] as? String)

        let ledgerBinding = try dictionary(corpus, "correctionLedger")
        let ledgerPath = try string(ledgerBinding, "path")
        let ledger = try object(ledgerPath)
        XCTAssertEqual(ledger["schema"] as? String, ledgerBinding["schema"] as? String)
        XCTAssertEqual(ledger["cardID"] as? String, "V23-P04-C28")
        try assertCorrectedAuthorityParity(corpus: corpus, ledger: ledger)
        try assertDeferredClusterParity(corpus: corpus, ledger: ledger)

        let semantics = try arrayOfDictionaries(corpus, "stableFeedbackSemantics")
        let correction = try dictionary(ledger, "sharedBrandCorrectionReceipt")
        let mappings = try arrayOfDictionaries(correction, "afterSemanticMappings")
        XCTAssertEqual(try mappings.map { try string($0, "stableID") }, try semantics.map { try string($0, "id") })
        XCTAssertEqual(try mappings.map { try string($0, "role") }, try semantics.map { try string($0, "role") })
        XCTAssertEqual(try mappings.map { try string($0, "localizationKey") }, try semantics.map { try string($0, "labelKey") })
        let ownerGraph = try dictionary(correction, "ownerGraph")
        XCTAssertEqual(
            ownerGraph["renderer"] as? String,
            "FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift"
        )
        XCTAssertEqual(Set(try strings(corpus, "testSupportLegacyAliases")), Set(try mappings.map {
            try string($0, "legacyID")
        }))
        let registry = try BundledLocalizationCatalogV1.registry()
        let accessibility = try BundledLocalizationCatalogV1.accessibilityRegistry(
            localization: registry
        )
        XCTAssertEqual(accessibility.entries.map(\.semanticID), try semantics.map { try string($0, "id") })
        XCTAssertTrue(accessibility.entries.allSatisfy { $0.deprecatedAliases.isEmpty })
        XCTAssertTrue(try productionLegacyMailReferences().isEmpty)
        try assertPublicCopy(corpus, registry: registry)
        try assertHistoricBytes(corpus)
    }

    func testV23P04C28A01NativeSemanticParityPreservesTasksIdentityAndHistoricBytes() throws {
        let corpus = try object(corpusPath)
        let conformance = try dictionary(corpus, "conformance")
        XCTAssertEqual(conformance["dynamicTypeMaximum"] as? String, "AX5")
        XCTAssertEqual(Set(try strings(conformance, "appearanceProfiles")), [
            "DARK", "INCREASED_CONTRAST", "LIGHT",
        ])
        XCTAssertEqual(conformance["inheritedCommonStateCount"] as? Int, 18)
        XCTAssertEqual(conformance["nonColorStatusRequired"] as? Bool, true)
        XCTAssertEqual(conformance["claimDisposition"] as? String, "UNCHANGED")

        let c27 = try object(c27InventoryPath)
        let contracts = try dictionary(c27, "contracts")
        let state = try dictionary(contracts, "applicationStateInventory")
        XCTAssertEqual(try strings(state, "runtimeProfiles"), [
            "MINIMUM_IOS_18", "LATEST_ACCEPTED_STABLE_SHIPPING_RUNTIME",
        ])
        let identity = try dictionary(contracts, "technicalIdentityFreeze")
        XCTAssertEqual(try strings(identity, "bundleIDs"), [
            "com.palatis3.fieldrecord", "com.palatis3.fieldrecord.tests",
            "com.palatis3.fieldrecord.uitests",
        ])
        XCTAssertEqual(identity["backupUTI"] as? String, "com.palatis3.fieldrecordbackup")
        XCTAssertEqual(identity["backupExtension"] as? String, "fieldrecordbackup")
        XCTAssertEqual(try strings(identity, "storageRoots"), [
            "FieldEvidenceData", "FieldEvidenceOperations", "FieldEvidenceRestore",
        ])
        XCTAssertEqual(try strings(identity, "storeKitProductIDs"), [
            "com.palatis3.fieldrecord.sub.solo.monthly.v1",
        ])
        XCTAssertEqual(identity["entryPointIdentity"] as? String, "FieldEvidenceAppApp")
        XCTAssertEqual(try strings(identity, "targetNames"), [
            "FieldEvidenceApp", "FieldEvidenceAppTests", "FieldEvidenceAppUITests",
        ])
        XCTAssertEqual(try strings(identity, "moduleNames"), [
            "FieldEvidenceApp", "FieldEvidenceAppTests", "FieldEvidenceAppUITests",
        ])
        XCTAssertEqual(identity["renameAllowed"] as? Bool, false)
        XCTAssertEqual(corpus["technicalIdentityDisposition"] as? String, "UNCHANGED_EXACT_C27_BINDING")

        let deferred = try arrayOfDictionaries(corpus, "deferredS10Clusters")
        XCTAssertEqual(deferred.count, 4)
        XCTAssertTrue(deferred.allSatisfy {
            $0["disposition"] as? String == "DEFERRED_PENDING_ACCEPTED_S10_6"
                && $0["adopted"] as? Bool == false
                && $0["acceptanceCredit"] as? Bool == false
        })
        try assertHistoricBytes(corpus)
    }

    func testV23P04C28H01SharedStateRoleAXContrastClaimsAndReportDriftFailClosed() throws {
        let pristine = try object(corpusPath)
        XCTAssertTrue(try c28Valid(pristine))
        let expectedHostiles = [
            "REJECT_APP_ICON_ACTIVATION", "REJECT_CLAIM_CHANGE", "REJECT_DUPLICATE_ROLE",
            "REJECT_DYNAMIC_TYPE_TRUNCATION", "REJECT_HISTORIC_BYTE_DRIFT",
            "REJECT_INCOMPLETE_STATE_CLOSURE", "REJECT_NONCONFORMING_CONTRAST",
            "REJECT_PARTIAL_CONSUMER_GRAPH", "REJECT_PRODUCTION_LEGACY_ALIAS",
            "REJECT_UNAUTHORIZED_BRAND_REVISION",
        ]
        XCTAssertEqual(
            Set(try arrayOfDictionaries(pristine, "hostileCases").map { try string($0, "expected") }),
            Set(expectedHostiles)
        )

        let mutations: [(String, (inout [String: Any]) throws -> Void)] = [
            ("inherited state", { root in try self.mutateConformance("inheritedCommonStateCount", 17, &root) }),
            ("AX5", { root in try self.mutateConformance("dynamicTypeMaximum", "AX4", &root) }),
            ("contrast", { root in try self.mutateConformance("appearanceProfiles", ["DARK", "LIGHT"], &root) }),
            ("claim", { root in try self.mutateConformance("claimDisposition", "CHANGED", &root) }),
            ("consumer", { root in
                var values = try self.arrayOfDictionaries(root, "affectedConsumerGraph")
                values.removeLast()
                root["affectedConsumerGraph"] = values
            }),
            ("duplicate role", { root in
                var values = try self.arrayOfDictionaries(root, "stableFeedbackSemantics")
                values[0]["role"] = values[1]["role"]
                root["stableFeedbackSemantics"] = values
            }),
            ("legacy alias", { root in
                var values = try self.arrayOfDictionaries(root, "stableFeedbackSemantics")
                values[0]["deprecatedAliases"] = ["s8.4.mail.attachment-count"]
                root["stableFeedbackSemantics"] = values
            }),
            ("copy", { root in
                var values = try self.arrayOfDictionaries(root, "publicCopyBindings")
                values[0]["value"] = "Submit"
                root["publicCopyBindings"] = values
            }),
            ("report", { root in
                var values = try self.arrayOfDictionaries(root, "historicReportBindings")
                values[0]["sha256"] = String(repeating: "a", count: 64)
                root["historicReportBindings"] = values
            }),
            ("brand revision", { root in root["brandRevisionDisposition"] = "ACTIVATED" }),
            ("app icon", { root in root["appIconDisposition"] = "ACTIVATED" }),
        ]
        for (label, mutate) in mutations {
            var hostile = pristine
            try mutate(&hostile)
            XCTAssertFalse(try c28Valid(hostile), label)
        }

        var missing = pristine
        missing.removeValue(forKey: "stableFeedbackSemantics")
        XCTAssertFalse(try c28Valid(missing))
        var corrupt = pristine
        corrupt["affectedConsumerGraph"] = "corrupt"
        XCTAssertFalse(try c28Valid(corrupt))
    }

    func testV23P04C28I01InterruptedCorrectionPreservesAcceptedC27BaselineAndNoPartialReceipt() throws {
        let corpus = try object(corpusPath)
        let recovery = try dictionary(corpus, "manifestLastRecovery")
        XCTAssertEqual(recovery["protocol"] as? String, "MANIFEST_LAST_ATOMIC_REPLACE")
        XCTAssertEqual(recovery["deterministicRetry"] as? Bool, true)
        let boundaries = try arrayOfDictionaries(recovery, "boundaries")
        XCTAssertEqual(try boundaries.map { try string($0, "boundary") }, [
            "BEFORE_ARTIFACTS", "AFTER_ARTIFACTS_BEFORE_MANIFEST", "AFTER_MANIFEST",
        ])
        XCTAssertEqual(try boundaries.map { try integer($0, "acceptedSetCount") }, [0, 0, 1])
        XCTAssertEqual(try boundaries.map { try integer($0, "retryAcceptedSetCount") }, [1, 1, 1])
        let predecessor = try dictionary(corpus, "predecessor")
        XCTAssertEqual(try sha256(data(c27InventoryPath)), predecessor["inventorySHA256"] as? String)
        try assertHistoricBytes(corpus)
    }

    func testV23P04C28R01RejectedDirectionAndFailedRetryPreserveAcceptedBrandRevision() throws {
        let corpus = try object(corpusPath)
        XCTAssertEqual(corpus["brandRevisionDisposition"] as? String, "UNCHANGED_NO_ACCEPTED_DIRECTION")
        XCTAssertEqual(corpus["appIconDisposition"] as? String, "NO_CHANGE_NO_ACCEPTED_BRAND_INTENT")
        XCTAssertEqual(corpus["persistentKinds"] as? [String], [])
        XCTAssertEqual(corpus["technicalIdentityDisposition"] as? String, "UNCHANGED_EXACT_C27_BINDING")
        let flags = try dictionary(corpus, "statusFlags")
        XCTAssertEqual(Set(flags.keys), ["acceptance", "adoption", "native", "publication", "release"])
        XCTAssertTrue(flags.values.allSatisfy { $0 as? Bool == false })
        let ledger = try object(try string(dictionary(corpus, "correctionLedger"), "path"))
        let ledgerFlags = try dictionary(ledger, "statusFlags")
        XCTAssertTrue(ledgerFlags.values.allSatisfy { $0 as? Bool == false })
        let lifecycle = try dictionary(ledger, "lifecycle")
        XCTAssertEqual(lifecycle["persistentKindCount"] as? Int, 0)
        XCTAssertEqual(lifecycle["writerCount"] as? Int, 0)
        XCTAssertEqual(lifecycle["migrationCount"] as? Int, 0)
        XCTAssertEqual(lifecycle["workspaceMutationReceiptCreated"] as? Bool, false)
        let brandRevision = try dictionary(ledger, "brandRevisionImplementationReceipt")
        XCTAssertEqual(brandRevision["authorizedChange"] as? Bool, false)
        XCTAssertEqual(brandRevision["activated"] as? Bool, false)
        let recovery = try dictionary(corpus, "manifestLastRecovery")
        XCTAssertEqual(recovery["deterministicRetry"] as? Bool, true)
        XCTAssertTrue(try c28Valid(corpus))
    }

    private func c28Valid(_ root: [String: Any]) throws -> Bool {
        do { return try c28ValidUnchecked(root) } catch { return false }
    }

    private func c28ValidUnchecked(_ root: [String: Any]) throws -> Bool {
        guard root["brandRevisionDisposition"] as? String == "UNCHANGED_NO_ACCEPTED_DIRECTION",
              root["appIconDisposition"] as? String == "NO_CHANGE_NO_ACCEPTED_BRAND_INTENT",
              root["persistentKinds"] as? [String] == [],
              root["technicalIdentityDisposition"] as? String == "UNCHANGED_EXACT_C27_BINDING" else {
            return false
        }
        let conformance = try dictionary(root, "conformance")
        guard conformance["dynamicTypeMaximum"] as? String == "AX5",
              Set(try strings(conformance, "appearanceProfiles")) == ["DARK", "INCREASED_CONTRAST", "LIGHT"],
              conformance["inheritedCommonStateCount"] as? Int == 18,
              conformance["nonColorStatusRequired"] as? Bool == true,
              conformance["claimDisposition"] as? String == "UNCHANGED" else { return false }

        let expected: [(String, String, String)] = [
            ("feedback.mail.screen", "SCREEN", "feedback.mail.composer.title"),
            ("feedback.mail.recipient", "GROUP", "feedback.mail.recipient"),
            ("feedback.mail.attachment-count", "STATUS", "feedback.mail.attachment_count"),
            ("feedback.mail.body", "TEXT_FIELD", "feedback.mail.message.label"),
            ("feedback.mail.done", "BUTTON", "common.done"),
        ]
        let semantics = try arrayOfDictionaries(root, "stableFeedbackSemantics")
        guard semantics.count == expected.count,
              try semantics.enumerated().allSatisfy({ index, value in
                  let semanticID = try string(value, "id")
                  let role = try string(value, "role")
                  let labelKey = try string(value, "labelKey")
                  let deprecatedAliases = try strings(value, "deprecatedAliases")
                  return semanticID == expected[index].0
                      && role == expected[index].1
                      && labelKey == expected[index].2
                      && deprecatedAliases.isEmpty
              }),
              Set(try semantics.map { try string($0, "role") }).count == expected.count else {
            return false
        }
        let graph = try arrayOfDictionaries(root, "affectedConsumerGraph")
        guard graph.count == expected.count,
              try graph.enumerated().allSatisfy({ index, value in
                  let consumerID = try string(value, "consumerID")
                  let role = try string(value, "role")
                  let labelKey = try string(value, "labelKey")
                  let productionOwner = try string(value, "productionOwner")
                  return consumerID == expected[index].0
                      && role == expected[index].1
                      && labelKey == expected[index].2
                      && productionOwner
                          == "FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift"
              }) else { return false }
        try assertPublicCopy(root, registry: BundledLocalizationCatalogV1.registry())
        try assertHistoricBytes(root)
        return try productionLegacyMailReferences().isEmpty
    }

    private func assertPublicCopy(
        _ root: [String: Any], registry: LocalizationKeyRegistryV1
    ) throws {
        let expected = Dictionary(uniqueKeysWithValues: try arrayOfDictionaries(root, "publicCopyBindings").map {
            (try string($0, "key"), try string($0, "value"))
        })
        XCTAssertEqual(expected, [
            "common.done": "Done",
            "feedback.mail.attachment_count": "Diagnostic attachments: %lld",
            "feedback.mail.composer.title": "Feedback composer",
            "feedback.mail.message.label": "Feedback message",
            "feedback.mail.recipient": "To: %@",
        ])
        for (key, value) in expected {
            XCTAssertEqual(try registry.definition(for: LocalizationKeyV1(key)).englishDefaultValue, value)
        }
        let attachment = try XCTUnwrap(
            try arrayOfDictionaries(root, "publicCopyBindings").first {
                $0["key"] as? String == "feedback.mail.attachment_count"
            }
        )
        XCTAssertEqual(attachment["one"] as? String, "Diagnostic attachment: %lld")
        XCTAssertEqual(attachment["other"] as? String, "Diagnostic attachments: %lld")
    }

    private func assertHistoricBytes(_ root: [String: Any]) throws {
        for binding in try arrayOfDictionaries(root, "historicReportBindings") {
            XCTAssertEqual(try sha256(data(string(binding, "path"))), binding["sha256"] as? String)
        }
    }

    private func assertCorrectedAuthorityParity(
        corpus: [String: Any], ledger: [String: Any]
    ) throws {
        let authority = try dictionary(corpus, "authority")
        XCTAssertEqual(Set(authority.keys), [
            "allocationRevision", "appBaseHead", "appBaseTree", "contextDigest",
            "coordinationHead", "coordinationLedgerDigest", "coordinationTree",
            "correctionSequence", "frozenS10ReservationDigest",
            "hydrationCorrectionReceiptDigest", "ownerAuthorizedPathAllocationDigest",
            "pathFenceDigest", "projectionDigest", "provisionalPrerequisiteDigest",
            "supersedesAllocationDigest",
        ])
        let exactStrings = [
            "appBaseHead": "803f75bc94a46b7b0ca50b14f1a49401f38550f1",
            "appBaseTree": "6f1cc0077cf74a1adb532124880b1cd5e4a031cc",
            "contextDigest": "1b2bff5c876c8f618dae7015b12d4dd51d431c6756678824d72421b4d55a80a9",
            "coordinationHead": "b30a1640d495bd2d6641ea2dbd816d8d4d23a186",
            "coordinationLedgerDigest": "5dd37b9b75422a8366b9e052781d09d022951ed2b3cbe51492765ab58cf2eb5f",
            "coordinationTree": "f5b3106d41380a906cfa1c0cbf9cdcc8268b4d22",
            "frozenS10ReservationDigest": "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a",
            "hydrationCorrectionReceiptDigest": "2b610d2031667696ba09337e194c8b42e39e09265fc6245a3f94fdd6271ac294",
            "ownerAuthorizedPathAllocationDigest": "27c242e6c316767b3731c3bda81948ad8a8dc5258b54c385994248c24033f48c",
            "pathFenceDigest": "52a48f30deafc62962e99607f690e84fb393f668c548a01fe496b96b450d3817",
            "projectionDigest": "a7064d17aa0bdd7ef1401b411087ff38c64ecefff7a3a9515039aa009d963df5",
            "provisionalPrerequisiteDigest": "83888037dd5c9762466f711f232ef5ecad7f34ffce1d773795f10dd8920763ce",
            "supersedesAllocationDigest": "f296173b2ae29f892447395bba5d2a48817607375e8da8d3173faf5ff739f3c1",
        ]
        for (key, value) in exactStrings {
            XCTAssertEqual(authority[key] as? String, value, key)
        }
        XCTAssertEqual(authority["allocationRevision"] as? Int, 2)
        XCTAssertEqual(authority["correctionSequence"] as? Int, 507)
        let pins = try dictionary(ledger, "sourcePins")
        XCTAssertEqual(authority["appBaseHead"] as? String, pins["acceptedAppHead"] as? String)
        XCTAssertEqual(authority["appBaseTree"] as? String, pins["acceptedAppTree"] as? String)
        XCTAssertEqual(authority["allocationRevision"] as? Int, pins["allocationRevision"] as? Int)
        XCTAssertEqual(authority["contextDigest"] as? String, pins["contextDigest"] as? String)
        XCTAssertEqual(authority["coordinationHead"] as? String, pins["coordinationAuthorityHead"] as? String)
        XCTAssertEqual(authority["coordinationTree"] as? String, pins["coordinationAuthorityTree"] as? String)
        XCTAssertEqual(authority["correctionSequence"] as? Int, pins["casSequence"] as? Int)
        XCTAssertEqual(
            authority["hydrationCorrectionReceiptDigest"] as? String,
            pins["coordinationCorrectionTransitionDigest"] as? String
        )
        XCTAssertEqual(
            authority["ownerAuthorizedPathAllocationDigest"] as? String,
            pins["ownerAuthorizedPathAllocationDigest"] as? String
        )
        XCTAssertEqual(authority["pathFenceDigest"] as? String, pins["pathFenceDigest"] as? String)
        XCTAssertEqual(
            authority["provisionalPrerequisiteDigest"] as? String,
            pins["provisionalPrerequisiteDigest"] as? String
        )
        XCTAssertEqual(
            authority["coordinationLedgerDigest"] as? String,
            pins["coordinationLedgerDigest"] as? String
        )
        XCTAssertEqual(authority["projectionDigest"] as? String, pins["sourceProjectionDigest"] as? String)
        XCTAssertEqual(
            authority["frozenS10ReservationDigest"] as? String,
            pins["frozenS10ReservationDigest"] as? String
        )
        XCTAssertEqual(
            authority["supersedesAllocationDigest"] as? String,
            pins["supersedesOwnerAuthorizedPathAllocationDigest"] as? String
        )
    }

    private func assertDeferredClusterParity(
        corpus: [String: Any], ledger: [String: Any]
    ) throws {
        let corpusClusters = try arrayOfDictionaries(corpus, "deferredS10Clusters")
        let ledgerClusters = try arrayOfDictionaries(ledger, "deferredAcceptedS10_6Clusters")
        let exactIDs = [
            "all-other-shipping-phase-number-ids-in-S10-reserved-ui-root-paths",
            "visual-DesignTokens-and-WorklightComponents",
            "saved-photo-RecordWork-and-IssueDetail",
            "app-icon-and-artwork",
        ]
        XCTAssertEqual(try corpusClusters.map { try string($0, "clusterID") }, exactIDs)
        XCTAssertEqual(try ledgerClusters.map { try string($0, "clusterID") }, exactIDs)
        XCTAssertEqual(corpusClusters.count, ledgerClusters.count)
        for (corpusCluster, ledgerCluster) in zip(corpusClusters, ledgerClusters) {
            XCTAssertEqual(corpusCluster["adopted"] as? Bool, false)
            XCTAssertEqual(ledgerCluster["adopted"] as? Bool, false)
            XCTAssertEqual(
                corpusCluster["disposition"] as? String,
                ledgerCluster["disposition"] as? String
            )
            XCTAssertEqual(
                corpusCluster["reservationDigest"] as? String,
                ledgerCluster["reservationDigest"] as? String
            )
            XCTAssertEqual(
                corpusCluster["reservationDigest"] as? String,
                "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
            )
            let ledgerMembers = try arrayOfDictionaries(ledgerCluster, "memberPaths")
            XCTAssertEqual(
                try strings(corpusCluster, "memberPaths"),
                try ledgerMembers.map { try string($0, "path") }
            )
            for member in ledgerMembers {
                XCTAssertEqual(Set(member.keys), [
                    "acceptedBaseByteLength", "acceptedBasePresence", "acceptedBaseSHA256", "path",
                ])
                let path = try string(member, "path")
                if path.contains("/AppIcon.appiconset/") {
                    XCTAssertEqual(member["acceptedBasePresence"] as? Bool, false)
                    XCTAssertTrue(member["acceptedBaseByteLength"] is NSNull)
                    XCTAssertTrue(member["acceptedBaseSHA256"] is NSNull)
                } else {
                    XCTAssertEqual(member["acceptedBasePresence"] as? Bool, true)
                    XCTAssertGreaterThan(try integer(member, "acceptedBaseByteLength"), 0)
                    XCTAssertEqual(try string(member, "acceptedBaseSHA256").count, 64)
                }
            }
        }
    }

    private func productionLegacyMailReferences() throws -> [String] {
        let root = repositoryRoot.appendingPathComponent("FieldEvidenceApp")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ))
        var matches: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true,
                  ["swift", "json", "xcstrings", "plist"].contains(url.pathExtension) else { continue }
            if String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("s8.4.mail.") {
                matches.append(url.path)
            }
        }
        return matches.sorted()
    }

    private func mutateConformance(
        _ key: String, _ value: Any, _ root: inout [String: Any]
    ) throws {
        var conformance = try dictionary(root, "conformance")
        conformance[key] = value
        root["conformance"] = conformance
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

    private func arrayOfDictionaries(_ root: [String: Any], _ key: String) throws -> [[String: Any]] {
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
