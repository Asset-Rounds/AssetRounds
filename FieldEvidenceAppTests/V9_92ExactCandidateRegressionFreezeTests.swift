import CryptoKit
import Foundation
import XCTest

final class V9_92ExactCandidateRegressionFreezeTests: XCTestCase {
    private let corpusPath = "FieldEvidenceAppTests/Fixtures/V23/Brand/V23P04C29ExactCandidateRegressionFreezeCorpusV1.json"

    func testV23P04C29G01ExactCandidateFreezeBindsBrandHIGAccessibilityLocalizationJourneyAndReleaseState() throws {
        let corpus = try object(corpusPath)
        XCTAssertEqual(Set(corpus.keys), Self.rootKeys)
        XCTAssertEqual(corpus["schema"] as? String, "V23P04C29ExactCandidateRegressionFreezeCorpusV1")
        XCTAssertEqual(corpus["schemaVersion"] as? Int, 1)
        XCTAssertEqual(corpus["cardID"] as? String, "V23-P04-C29")
        XCTAssertEqual(corpus["syntheticOnly"] as? Bool, true)
        XCTAssertEqual(corpus["containsCustomerData"] as? Bool, false)
        XCTAssertEqual(
            try objects(corpus, "prerequisites").map { $0["cardID"] as? String },
            ["V23-P00-C13", "V23-P04-C28"]
        )
        XCTAssertTrue(closed(corpus))
        try assertObservedSelfTestEnvelope(corpus)
        try assertMatrixBinding(corpus)
        XCTAssertTrue(try falseFlags(corpus, key: "statusFlags"))
    }

    func testV23P04C29A01MinimumIOS18AndLatestStableResolveSeparatelyWithSemanticParity() throws {
        let corpus = try object(corpusPath)
        let profiles = try objects(corpus, "runtimeProfiles")
        XCTAssertEqual(profiles.map { $0["profileID"] as? String }, ["MINIMUM_IOS_18", "LATEST_ACCEPTED_STABLE_SHIPPING_RUNTIME"])
        XCTAssertTrue(profiles.allSatisfy { ($0["status"] as? String) == "NOT_RUN" })
        XCTAssertEqual(try strings(corpus, "semanticParityDimensions"), ["ACCESSIBILITY", "ACTION", "CONTENT", "DATA_TRUTH", "DURABILITY", "ROUTE", "TASK"])
        XCTAssertTrue(closed(corpus))
    }

    func testV23P04C29H01UnknownStaleCorruptCoverageContrastAccessibilityLocalizationJourneyAndReleaseDriftFailClosed() throws {
        let pristine = try object(corpusPath)
        XCTAssertTrue(closed(pristine))
        let paths = objectPaths(in: pristine)
        XCTAssertFalse(paths.isEmpty)
        for path in paths {
            var extra = pristine; mutateObject(at: path, in: &extra) { $0["__hostile_extra__"] = true }
            XCTAssertFalse(closed(extra), "extra key at \(path)")
            var missing = pristine; mutateObject(at: path, in: &missing) { value in value.removeValue(forKey: value.keys.sorted().first!) }
            XCTAssertFalse(closed(missing), "missing key at \(path)")
            var wrongType = pristine; mutateObject(at: path, in: &wrongType) { value in value[value.keys.sorted().first!] = ["wrong"] }
            XCTAssertFalse(closed(wrongType), "wrong type at \(path)")
        }
        var stale = pristine
        mutateObject(at: ["authority"], in: &stale) { $0["coordinationHead"] = String(repeating: "0", count: 40) }
        XCTAssertFalse(closed(stale))
        var promoted = pristine
        mutateObject(at: ["statusFlags"], in: &promoted) { $0["acceptance"] = true }
        XCTAssertFalse(closed(promoted))
        var foreignObservedCandidate = pristine
        mutateObject(at: ["productLedger", "observedSelfTest", "candidate"], in: &foreignObservedCandidate) {
            $0["tree"] = String(repeating: "f", count: 40)
        }
        XCTAssertFalse(observedStaticBindingsMatch(foreignObservedCandidate))
        var foreignObservedAuthority = pristine
        mutateObject(at: ["productLedger", "observedSelfTest", "authority"], in: &foreignObservedAuthority) {
            $0["contextDigest"] = String(repeating: "f", count: 64)
        }
        XCTAssertFalse(observedStaticBindingsMatch(foreignObservedAuthority))
    }

    func testV23P04C29I01ManifestLastInterruptionPreservesCandidateAndNoPartialReceipt() throws {
        let corpus = try object(corpusPath)
        let recovery = try dictionary(corpus, "manifestLastRecovery")
        XCTAssertEqual(recovery["protocol"] as? String, "MANIFEST_LAST_ATOMIC_REPLACE")
        let rows = try objects(recovery, "boundaries")
        XCTAssertEqual(rows.map { $0["boundary"] as? String }, ["BEFORE_ARTIFACTS", "AFTER_ARTIFACTS_BEFORE_MANIFEST", "AFTER_MANIFEST"])
        XCTAssertEqual(rows.map { $0["acceptedSetCount"] as? Int }, [0, 0, 1])
        XCTAssertTrue(closed(corpus))
    }

    func testV23P04C29R01DeterministicRetryPreservesFrozenCandidateWithoutPromotion() throws {
        let corpus = try object(corpusPath)
        try assertObservedSelfTestEnvelope(corpus)
        XCTAssertTrue(try falseFlags(corpus, key: "statusFlags"))
        XCTAssertTrue(try falseFlags(corpus, key: "negativeClaims"))
        XCTAssertEqual(try dictionary(corpus, "diagnosticPolicy")["promotionAllowed"] as? Bool, false)
    }

    private static let rootKeys: Set<String> = ["schema", "schemaVersion", "cardID", "syntheticOnly", "containsCustomerData", "authority", "candidateFreeze", "prerequisites", "productLedger", "evidenceRows", "runtimeProfiles", "blockedEvidence", "manifestLastRecovery", "hostileCases", "diagnosticPolicy", "negativeClaims", "selectors", "semanticParityDimensions", "statusFlags", "matrixBinding", "closedShape"]

    private func assertMatrixBinding(_ corpus: [String: Any]) throws {
        let binding = try dictionary(corpus, "matrixBinding")
        XCTAssertEqual(binding["candidateRuntimeCount"] as? Int, 2)
        XCTAssertEqual(binding["commonJourneyCount"] as? Int, 14)
        XCTAssertEqual(binding["featureJourneyCount"] as? Int, 17)
        XCTAssertEqual(binding["accessibilityLabelCount"] as? Int, 9)
        XCTAssertEqual(binding["closureCount"] as? Int, 16)
        XCTAssertEqual(binding["c28S10ReservationCount"] as? Int, 4)
        XCTAssertEqual(binding["unresolvedEvidenceCount"] as? Int, 7)
        XCTAssertLessThanOrEqual(binding["maximumShardCount"] as? Int ?? .max, 5)
        XCTAssertEqual(binding["scenarioIDs"] as? [String], ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(binding["semanticParityDimensions"] as? [String], ["ACCESSIBILITY", "ACTION", "CONTENT", "DATA_TRUTH", "DURABILITY", "ROUTE", "TASK"])

        let ledger = try object("docs/product/brand/V23P04C29ExactCandidateRegressionFreezeV1.json")
        let matrix = try dictionary(ledger, "matrix")
        XCTAssertEqual(try strings(matrix, "commonJourneyRows"), [
            "J01_FIRST_ENTRY", "J02_REAL_WORKSPACE_CREATE_IMPORT_SELECT", "J03_SITE_LOCATION_ASSET_CREATE_FIND_SCAN", "J04_OFFLINE_PREPARE", "J05_ROUND_START_RESUME", "J06_EVIDENCE_CAPTURE_CURATE", "J07_VALIDATION_INCOMPLETE_RESOLUTION", "J08_COMPLETE_NEXT_CLOSE", "J09_REPORT_PREVIEW_SHARE_EXPORT", "J10_BACKUP_RESTORE_RECOVERY", "J11_SETTINGS_ACCESSIBILITY_HELP", "J12_PURCHASE_RESTORE", "J13_DELETE_ERASE", "J14_PRACTICE_START_SWITCH_LEAVE",
        ])
        XCTAssertEqual(try strings(matrix, "featureJourneyRows"), (1...17).map { String(format: "FJ%02d", $0) })
        XCTAssertEqual(try objects(matrix, "scenarioRows").map { $0["id"] as? String }, ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertTrue(try objects(matrix, "scenarioRows").allSatisfy { ($0["status"] as? String) == "NOT_RUN" })
        XCTAssertTrue(try objects(matrix, "candidateRuntimeRows").allSatisfy { ($0["status"] as? String) == "NOT_RUN" })
        XCTAssertTrue(try objects(matrix, "accessibilityLabelRows").allSatisfy { ($0["status"] as? String) == "NOT_RUN" })
        XCTAssertTrue(try objects(matrix, "c28S10ReservationRows").allSatisfy { ($0["disposition"] as? String) == "DEFERRED_PENDING_ACCEPTED_S10_6" })
        XCTAssertEqual(
            try objects(matrix, "closureRows").map { "\($0["cardID"] as? String ?? ""):\($0["featureJourneyID"] as? String ?? "NONE")" },
            ["V23-P04-C30:FJ01", "V23-P04-C31:FJ02", "V23-P04-C32:FJ02", "V23-P04-C33:FJ03", "V23-P04-C34:FJ04", "V23-P04-C35:FJ05", "V23-P04-C36:FJ06", "V23-P04-C37:NONE", "V23-P04-C38:FJ07", "V23-P04-C39:NONE", "V23-P04-C40:FJ08", "V23-P04-C41:FJ12", "V23-P04-C42:FJ02", "V23-P04-C43:FJ17", "V23-P04-C44:FJ13", "V23-P04-C45:FJ14"]
        )
    }

    /// The source rows include this fixture's own bytes.  Their final digest can
    /// only be checked by the generator/verifier after the complete fence freezes.
    /// The static corpus still freezes every non-self-referential field and shape.
    private func assertObservedSelfTestEnvelope(_ root: [String: Any]) throws {
        let ledger = try dictionary(root, "productLedger")
        let observed = try dictionary(ledger, "observedSelfTest")
        XCTAssertEqual(observed["schema"] as? String, "V23P04C29ObservedSelfTestV1")
        XCTAssertEqual(observed["cardID"] as? String, "V23-P04-C29")
        XCTAssertTrue(observedStaticBindingsMatch(root))
        let sourceRows = try objects(observed, "sourceRows")
        let scripts = try dictionary(observed, "scripts")
        let digest = observed["canonicalResultSHA256"]
        let pending = sourceRows.isEmpty
            && scripts["generatorSHA256"] is NSNull
            && scripts["verifierSHA256"] is NSNull
            && digest is NSNull
        if !pending {
            XCTAssertEqual(digest as? String, sha(canonicalObservedBytes(observed)))
            XCTAssertEqual(scripts["generatorSHA256"] as? String, sha(try data("Scripts/v23/generate_p04_c29_contracts.py")))
            XCTAssertEqual(scripts["verifierSHA256"] as? String, sha(try data("Scripts/v23/verify_p04_c29_contracts.py")))
            XCTAssertFalse(sourceRows.isEmpty)
        }
        let commands = try objects(observed, "commands")
        XCTAssertEqual(commands.map { $0["command"] as? String }, [
            "python -B Scripts/v23/generate_p04_c29_contracts.py --self-test --json",
            "python -B Scripts/v23/verify_p04_c29_contracts.py --complete --json",
        ])
        XCTAssertEqual(commands.map { $0["mode"] as? String }, ["GENERATOR_MANIFEST_LAST_RECOVERY", "COMPLETE_STATIC_PROVISIONAL"])
        XCTAssertEqual(try objects(observed, "manifestLastRows").map { $0["boundary"] as? String }, ["BEFORE_ARTIFACTS", "AFTER_ARTIFACTS_BEFORE_MANIFEST", "AFTER_MANIFEST"])
    }

    private func observedStaticBindingsMatch(_ root: [String: Any]) -> Bool {
        do {
            let observed = try dictionary(try dictionary(root, "productLedger"), "observedSelfTest")
            let observedCandidate = try canonicalData(dictionary(observed, "candidate"))
            let candidate = try canonicalData(dictionary(root, "candidateFreeze"))
            let observedAuthority = try canonicalData(dictionary(observed, "authority"))
            let authority = try canonicalData(dictionary(root, "authority"))
            return observedCandidate == candidate && observedAuthority == authority
        } catch {
            return false
        }
    }

    private func canonicalObservedBytes(_ observed: [String: Any]) throws -> Data {
        var basis = observed
        basis.removeValue(forKey: "canonicalResultSHA256")
        return try JSONSerialization.data(withJSONObject: basis, options: [.sortedKeys])
    }

    private func canonicalData(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private func closed(_ root: [String: Any]) -> Bool {
        do {
            let pristine = try object(corpusPath)
            let closedShape = try dictionary(root, "closedShape")
            let allowed = try dictionary(closedShape, "objectKeys")
            let shapes = try Dictionary(uniqueKeysWithValues: allowed.map { key, value in
                (key, Set(try XCTUnwrap(value as? [String])))
            })
            guard Set(root.keys) == Self.rootKeys, shapes["root"] == Self.rootKeys else { return false }
            guard Set(closedShape.keys) == Set(["objectKeys", "arrays"]),
                  allowed.values.allSatisfy({ $0 is [String] }) else { return false }
            try validate(value: root, shapes: shapes)
            guard typeSignature(root) == typeSignature(pristine) else { return false }
            let authorityBytes = try canonicalData(dictionary(root, "authority"))
            let pristineAuthorityBytes = try canonicalData(dictionary(pristine, "authority"))
            let candidateBytes = try canonicalData(dictionary(root, "candidateFreeze"))
            let pristineCandidateBytes = try canonicalData(dictionary(pristine, "candidateFreeze"))
            guard authorityBytes == pristineAuthorityBytes,
                  candidateBytes == pristineCandidateBytes,
                  try falseFlags(root, key: "statusFlags") else { return false }
            return true
        } catch { return false }
    }

    private func validate(value: Any, shapes: [String: Set<String>]) throws {
        if let object = value as? [String: Any] {
            if object.keys.contains("objectKeys") { return }
            guard shapes.values.contains(Set(object.keys)) else { throw ValidationError.shape }
            for child in object.values { try validate(value: child, shapes: shapes) }
        } else if let array = value as? [Any] {
            for child in array { try validate(value: child, shapes: shapes) }
        }
    }

    /// A recursive fixture fingerprint freezes primitive type, object keys, and
    /// every array row.  This catches hostile wrong-type mutations at leaves that
    /// a key-only JSON closure declaration cannot represent.
    private func typeSignature(_ value: Any) -> String {
        if let object = value as? [String: Any] {
            return "{\(object.keys.sorted().map { "\($0):\(typeSignature(object[$0]!))" }.joined(separator: ","))}"
        }
        if let array = value as? [Any] {
            return "[\(array.map { typeSignature($0) }.joined(separator: ","))]"
        }
        if value is NSNull { return "null" }
        if value is Bool { return "bool" }
        if value is NSNumber { return "number" }
        return value is String ? "string" : "unsupported"
    }

    private enum ValidationError: Error { case shape }
    private func objectPaths(in root: [String: Any]) -> [[String]] {
        var paths: [[String]] = []
        func visit(_ value: Any, _ path: [String]) {
            if let dictionary = value as? [String: Any] {
                paths.append(path)
                for key in dictionary.keys.sorted() { visit(dictionary[key]!, path + [key]) }
            }
            if let array = value as? [Any] { for (index, child) in array.enumerated() { visit(child, path + ["#\(index)"]) } }
        }
        visit(root, []); return paths
    }
    private func mutateObject(at path: [String], in root: inout [String: Any], _ body: (inout [String: Any]) -> Void) {
        func mutate(_ value: inout Any, _ remaining: ArraySlice<String>) {
            guard let next = remaining.first else { var object = value as! [String: Any]; body(&object); value = object; return }
            if next.hasPrefix("#") { var array = value as! [Any]; let index = Int(next.dropFirst())!; mutate(&array[index], remaining.dropFirst()); value = array }
            else { var object = value as! [String: Any]; mutate(&object[next]!, remaining.dropFirst()); value = object }
        }
        var value: Any = root; mutate(&value, path[...]); root = value as! [String: Any]
    }
    private func falseFlags(_ root: [String: Any], key: String, allowing: Set<String> = []) throws -> Bool {
        let values = try dictionary(root, key)
        return values.allSatisfy { allowing.contains($0.key) || ($0.value as? Bool) == false }
    }
    private var rootURL: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }
    private func data(_ path: String) throws -> Data { try Data(contentsOf: rootURL.appendingPathComponent(path)) }
    private func object(_ path: String) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: data(path)) as? [String: Any]) }
    private func dictionary(_ root: [String: Any], _ key: String) throws -> [String: Any] { try XCTUnwrap(root[key] as? [String: Any]) }
    private func objects(_ root: [String: Any], _ key: String) throws -> [[String: Any]] { try XCTUnwrap(root[key] as? [[String: Any]]) }
    private func strings(_ root: [String: Any], _ key: String) throws -> [String] { try XCTUnwrap(root[key] as? [String]) }
    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
