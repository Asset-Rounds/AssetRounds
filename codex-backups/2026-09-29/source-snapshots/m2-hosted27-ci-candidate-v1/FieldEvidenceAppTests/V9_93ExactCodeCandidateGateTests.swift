import CryptoKit
import Foundation
import XCTest

final class V9_93ExactCodeCandidateGateTests: XCTestCase {
    private let ledgerPath = "Release/V23P05C01ExactCodeCandidateGateV1.json"
    private let corpusPath = "FieldEvidenceAppTests/Fixtures/V23/Release/V23P05C01ExactCodeCandidateGateCorpusV1.json"
    private let selectorIDs = [
        "P03ShippingSurfaceSetV1", "P04ShippingSurfaceSetV1", "P04BrandClosureSetV1",
        "PublicCapabilityTruthSetV1", "AutonomousRequiredAcceptedSetV1",
        "ContactPurposeSeparationSetV1", "KernelConformanceSubjectSetV1",
    ]

    func testV23P05C01G01ExactCodeCandidateGate() throws {
        let ledger = try object(ledgerPath)
        XCTAssertEqual(ledger["schema"] as? String, "V23P05C01ExactCodeCandidateGateV1")
        XCTAssertEqual(ledger["schemaVersion"] as? Int, 1)
        XCTAssertTrue(try valid(ledger))
        let card = try dictionary(ledger, "card")
        XCTAssertEqual(card["id"] as? String, "V23-P05-C01")
        XCTAssertEqual(card["ordinal"] as? Int, 134)
        XCTAssertEqual(card["classification"] as? String, "PREPARE_NOW")
        XCTAssertEqual(try objects(ledger, "selectorRows").map { $0["id"] as? String }, selectorIDs)
        XCTAssertEqual(try objects(ledger, "selectorRows").map { $0["memberCount"] as? Int }, [19, 40, 65, 15, 132, 11, 72])
        let prerequisite = try dictionary(ledger, "prerequisite")
        XCTAssertEqual(prerequisite["cardID"] as? String, "V23-P04-C29")
        XCTAssertEqual(prerequisite["acceptance"] as? Bool, false)
        XCTAssertEqual(prerequisite["checkpointDigest"] as? String, "b5a01f55325d5bbebc8e5744d4ddcf926936f73ed9c42b36a1f64e59d7bc2b89")
        XCTAssertEqual(prerequisite["verificationDigest"] as? String, "45cb4f66f35ea76c024526a0d5a1cac4d4b642b6797b4565b40eb1646d224f38")
        XCTAssertEqual(prerequisite["boundaryDigest"] as? String, "a4669291ed3722c46c30067066367d669ac00a850fda9e673fc147354ad1719f")
        try assertNoCreditAndStaticOnly(ledger)
        try assertSourceHashClosure(ledger)
    }

    func testV23P05C01A01AlternateCandidateGate() throws {
        let ledger = try object(ledgerPath)
        let corpus = try object(corpusPath)
        XCTAssertEqual(corpus["schema"] as? String, "V23P05C01ExactCodeCandidateGateCorpusV1")
        XCTAssertEqual(corpus["cardID"] as? String, "V23-P05-C01")
        XCTAssertEqual(corpus["customerData"] as? Bool, false)
        XCTAssertEqual(try objects(corpus, "cases").map { $0["id"] as? String }, ["G01", "A01", "H01_MALFORMED", "H01_DUPLICATE", "H01_STALE_IDENTITY", "H01_FALSE_READY", "H01_FALSE_RELEASE", "I01", "R01"])
        let counts = try dictionary(corpus, "requiredCounts")
        XCTAssertEqual(counts["selectorMembers"] as? [Int], [19, 40, 65, 15, 132, 11, 72])
        XCTAssertEqual(counts["provisionalStateCountVector"] as? [Int], [112, 14, 5, 1])
        XCTAssertEqual(counts["commonJourneys"] as? Int, 14)
        XCTAssertEqual(counts["featureJourneys"] as? Int, 17)
        // Owner-delegated decision (2026-09-25, owner decision 14): the frozen P05-C01 corpus
        // (FieldEvidenceAppTests/Fixtures/V23/Release/V23P05C01ExactCodeCandidateGateCorpusV1.json at
        // 5f17cdcd) names this count requiredCounts.logicalAcceptanceLanes; "logicalLanes" never existed.
        XCTAssertEqual(counts["logicalAcceptanceLanes"] as? Int, 5)
        XCTAssertTrue(try valid(ledger))
        XCTAssertEqual(try strings(try dictionary(ledger, "journeyGates"), "commonJourneyIDs"), ["J01_FIRST_ENTRY", "J02_REAL_WORKSPACE_CREATE_IMPORT_SELECT", "J03_SITE_LOCATION_ASSET_CREATE_FIND_SCAN", "J04_OFFLINE_PREPARE", "J05_ROUND_START_RESUME", "J06_EVIDENCE_CAPTURE_CURATE", "J07_VALIDATION_INCOMPLETE_RESOLUTION", "J08_COMPLETE_NEXT_CLOSE", "J09_REPORT_PREVIEW_SHARE_EXPORT", "J10_BACKUP_RESTORE_RECOVERY", "J11_SETTINGS_ACCESSIBILITY_HELP", "J12_PURCHASE_RESTORE", "J13_DELETE_ERASE", "J14_PRACTICE_START_SWITCH_LEAVE"])
        XCTAssertEqual(try strings(try dictionary(ledger, "journeyGates"), "featureJourneyIDs"), (1...17).map { String(format: "FJ%02d", $0) })
        XCTAssertEqual(try objects(ledger, "scenarioRows").map { $0["id"] as? String }, ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(try objects(ledger, "logicalAcceptanceLanes").map { $0["id"] as? String }, [
            "COMPILE_STATIC_ARCHITECTURE_CLAIMS_LOCALIZATION",
            "UNIT_CONTRACT_LIFECYCLE_HOSTILE_PARSER",
            "INTEGRATION_INTERRUPTION_RECOVERY_COMPATIBILITY",
            "UI_JOURNEY_ACCESSIBILITY_VISUAL_AFFECTED_HIG",
            "COVERAGE_UNINSTRUMENTED_PERFORMANCE_ARCHIVE_RELEASE_EVIDENCE",
        ])
        XCTAssertEqual(try objects(ledger, "logicalAcceptanceLanes").map { $0["status"] as? String }, ["NOT_RUN", "NOT_RUN", "NOT_RUN", "BLOCKED", "BLOCKED"])
    }

    func testV23P05C01H01HostileCandidateGate() throws {
        let pristine = try object(ledgerPath)
        XCTAssertTrue(try valid(pristine))
        var duplicateSelector = pristine
        var selectors = try objects(duplicateSelector, "selectorRows")
        selectors.append(selectors[0]); duplicateSelector["selectorRows"] = selectors
        XCTAssertFalse(try valid(duplicateSelector))
        var duplicateMember = pristine
        var evidence = try dictionary(duplicateMember, "provisionalEvidence")
        var members = try strings(evidence, "orderedMemberIDs")
        members.append(members[0]); evidence["orderedMemberIDs"] = members; duplicateMember["provisionalEvidence"] = evidence
        XCTAssertFalse(try valid(duplicateMember))
        var stale = pristine
        var candidate = try dictionary(stale, "candidate")
        candidate["baseHead"] = String(repeating: "0", count: 40); stale["candidate"] = candidate
        XCTAssertFalse(try valid(stale))
        var falseReady = pristine
        evidence = try dictionary(falseReady, "provisionalEvidence"); evidence["acceptedCount"] = 1; falseReady["provisionalEvidence"] = evidence
        XCTAssertFalse(try valid(falseReady))
        var releaseClaim = pristine
        var flags = try dictionary(releaseClaim, "flags"); flags["release"] = true; releaseClaim["flags"] = flags
        XCTAssertFalse(try valid(releaseClaim))
        var malformed = pristine; malformed.removeValue(forKey: "readOnlyBindings")
        XCTAssertFalse(try valid(malformed))
    }

    func testV23P05C01I01InterruptionCandidateGate() throws {
        let ledger = try object(ledgerPath)
        var interrupted = ledger
        var bindings = try objects(interrupted, "readOnlyBindings")
        bindings.removeLast(); interrupted["readOnlyBindings"] = bindings
        XCTAssertFalse(try valid(interrupted))
        XCTAssertFalse(try anyCredit(interrupted))
        XCTAssertEqual(try dictionary(ledger, "candidate")["status"] as? String, "PROVISIONAL_STATIC_ONLY")
    }

    func testV23P05C01R01RecoveryCandidateGate() throws {
        let first = try object(ledgerPath)
        let replay = try object(ledgerPath)
        XCTAssertTrue(try valid(first))
        XCTAssertTrue(try valid(replay))
        XCTAssertEqual(try canonical(first), try canonical(replay))
        try assertNoCreditAndStaticOnly(replay)
        XCTAssertTrue(try strings(try object(corpusPath), "forbiddenOutcomes").allSatisfy { ["READY", "ACCEPTED", "RELEASE_READY", "RELEASED", "PHASE_INTEGRATED", "P05_C02", "P05_C03", "P06"].contains($0) })
    }

    private func valid(_ ledger: [String: Any]) throws -> Bool {
        guard ledger["schema"] as? String == "V23P05C01ExactCodeCandidateGateV1",
              let card = ledger["card"] as? [String: Any], card["id"] as? String == "V23-P05-C01", card["ordinal"] as? Int == 134,
              let candidate = ledger["candidate"] as? [String: Any], candidate["baseHead"] as? String == "2952775307a182d183461f81157af6cb3819be69", candidate["baseTree"] as? String == "36b3c5f0993519aa703a341f6e650989dc5f1102", candidate["status"] as? String == "PROVISIONAL_STATIC_ONLY",
              let selectorRows = ledger["selectorRows"] as? [[String: Any]], selectorRows.map({ $0["id"] as? String }) == selectorIDs, selectorRows.map({ $0["memberCount"] as? Int }) == [19, 40, 65, 15, 132, 11, 72], Set(selectorRows.compactMap { $0["id"] as? String }).count == 7,
              let evidence = ledger["provisionalEvidence"] as? [String: Any], let members = evidence["orderedMemberIDs"] as? [String], members.count == 132, Set(members).count == 132, evidence["acceptedCount"] as? Int == 0, evidence["predicateSatisfied"] as? Bool == false, evidence["creditGranted"] as? Bool == false,
              let journeys = ledger["journeyGates"] as? [String: Any], (journeys["commonJourneyIDs"] as? [String])?.count == 14, (journeys["featureJourneyIDs"] as? [String])?.count == 17, journeys["status"] as? String == "NOT_RUN",
              let lanes = ledger["scenarioRows"] as? [[String: Any]], lanes.map({ $0["id"] as? String }) == ["G01", "A01", "H01", "I01", "R01"],
              let acceptanceLanes = ledger["logicalAcceptanceLanes"] as? [[String: Any]], acceptanceLanes.count == 5,
              let bindings = ledger["readOnlyBindings"] as? [[String: Any]], bindings.count == 17,
              let lifecycle = ledger["lifecycle"] as? [String: Bool], lifecycle.values.allSatisfy({ !$0 }),
              let flags = ledger["flags"] as? [String: Bool], flags.filter({ $0.key != "requiresAcceptedS10_6" }).values.allSatisfy({ !$0 }), flags["requiresAcceptedS10_6"] == true
        else { return false }
        return true
    }

    private func assertNoCreditAndStaticOnly(_ ledger: [String: Any]) throws {
        XCTAssertFalse(try anyCredit(ledger))
        let flags = try dictionary(ledger, "flags")
        for key in ["native", "hosted", "physical", "acceptance", "adoption", "publication", "release", "phaseIntegration"] { XCTAssertEqual(flags[key] as? Bool, false, key) }
        XCTAssertEqual(flags["requiresAcceptedS10_6"] as? Bool, true)
        XCTAssertEqual(try strings(ledger, "prohibitions"), ["NO_XCODE", "NO_IOS_DEVICE", "NO_UDID", "NO_WORKFLOW_INVENTION", "NO_SIGNING", "NO_UPLOAD", "NO_SUBMISSION", "NO_P05_C02_C03_OR_P06_WORK"])
    }

    private func anyCredit(_ ledger: [String: Any]) throws -> Bool {
        let evidence = try dictionary(ledger, "provisionalEvidence")
        let flags = try dictionary(ledger, "flags")
        return (evidence["acceptedCount"] as? Int ?? 0) != 0 || (evidence["predicateSatisfied"] as? Bool ?? true) || (evidence["creditGranted"] as? Bool ?? true) || flags.filter({ $0.key != "requiresAcceptedS10_6" }).values.contains { ($0 as? Bool) == true }
    }

    private func assertSourceHashClosure(_ ledger: [String: Any]) throws {
        let bindings = try objects(ledger, "readOnlyBindings")
        XCTAssertEqual(bindings.count, 17)
        for binding in bindings {
            let path = try XCTUnwrap(binding["path"] as? String)
            XCTAssertEqual(binding["sha256"] as? String, digest(try cardTimeData(path)), path)
        }
        XCTAssertEqual(
            Set(Self.cardHistory.map(\.path)).subtracting(bindings.compactMap { $0["path"] as? String }),
            []
        )
    }

    // Owner-delegated decision (2026-09-25): by analogy with owner decision 7, this card-time
    // test proves the committed P05-C01 history, not live CI state. The receipt-bound record
    // (never edited) binds the CI selector and workflow bytes as committed at 5f17cdcd, the
    // commit that wrote it; those CI-state paths are read from exact git-blob copies indexed by
    // docs/design/v23/integration/v23-card-history/manifest.json, each admitted only when its
    // byte count, SHA-256 and git blob id equal the pins below (recheck: git rev-parse
    // 5f17cdcd:<path>). Every other binding path is still read live.
    private struct CardHistoryEntry {
        let path: String
        let byteCount: Int
        let sha256: String
        let gitBlobOID: String
        let copy: String
    }
    private static let cardHistoryDirectory = "docs/design/v23/integration/v23-card-history"
    private static let cardHistoryCommit = "5f17cdcd63a4ee7cbdfe50c73c0b0265bdbc1ef3"
    private static let cardHistory: [CardHistoryEntry] = [
        .init(path: "Scripts/ci-selection.json", byteCount: 340,
              sha256: "03C23506919733DDE0174448E446D26DF4753C505BE242587886F142D281314F",
              gitBlobOID: "2e8d194fbb52f0bdcc1bd420af4c254638eb9a49", copy: "blobs/03C23506919733DD.json"),
        .init(path: ".github/workflows/ios-ci.yml", byteCount: 23_068,
              sha256: "BCD64E2A42752D28844435241B5ABFCA911D04190375CBBDBFC10B45ACBA97D7",
              gitBlobOID: "bade6a6442bd77a6c15eaefa70726b1efc1b3c73", copy: "blobs/BCD64E2A42752D28.yml"),
        // Owner-delegated decision (2026-09-25): the other five CI-state bindings (controller and
        // worker workflows, controller, capacity contracts, release test plan) are card-time
        // history too (owner decision 7 by analogy); pinned to their bytes at 5f17cdcd.
        .init(path: ".github/workflows/v23-controller.yml", byteCount: 1_009,
              sha256: "9191E22EF1485AF2DC3DD6A1F0201FE16FE2E6F884BED89FC701F1B4EB4B817B",
              gitBlobOID: "41ddf4caef03d8ac0041eb2d7a9da96266dfa19d", copy: "blobs/9191E22EF1485AF2.yml"),
        .init(path: ".github/workflows/v23-worker.yml", byteCount: 5_758,
              sha256: "EE00DD9C894CFDC353B53E52813498C81A7A6D5486920931EEC2CBE1CACA2F51",
              gitBlobOID: "d0a1b108b9b11e7c3d31cb65ff9a718587e7dc33", copy: "blobs/EE00DD9C894CFDC3.yml"),
        .init(path: "Scripts/v23/controller.py", byteCount: 3_060,
              sha256: "F5634CF788AFE80911DB6DBEDFF53464B23556EFF5EEF4037A7F625343738B35",
              gitBlobOID: "b5b49853485fbbfc35878f926db5d7eb499a965c", copy: "blobs/F5634CF788AFE809.py"),
        .init(path: "Scripts/v23/controller_contracts.py", byteCount: 47_899,
              sha256: "64F2A2D6975AE17CDAB96CA1DDAA78FEB5EEB8990325EE632C01F1CD79CCB977",
              gitBlobOID: "d24d453bb0c4460ad2090b73157e673486d83659", copy: "blobs/64F2A2D6975AE17C.py"),
        .init(path: "TestPlans/V23-ReleaseCandidate.xctestplan", byteCount: 781,
              sha256: "0539566B34917618F575650D256A2AE125FEA6E8C31365C07871C52556F4B606",
              gitBlobOID: "213268188de10f7e5b919272410c9cb501f09e09", copy: "blobs/0539566B34917618.xctestplan"),
    ]

    private func cardTimeData(_ path: String) throws -> Data {
        guard let entry = Self.cardHistory.first(where: { $0.path == path }) else { return try data(path) }
        let index = try object("\(Self.cardHistoryDirectory)/manifest.json")
        XCTAssertEqual(index["document_id"] as? String, "v23-card-history-v1")
        let rows = try objects(index, "entries").filter { ($0["path"] as? String) == path }
        XCTAssertEqual(rows.count, 1, path)
        let row = try XCTUnwrap(rows.first, path)
        XCTAssertEqual(row["card_id"] as? String, "V23-P05-C01", path)
        XCTAssertEqual(row["commit"] as? String, Self.cardHistoryCommit, path)
        XCTAssertEqual(row["byte_count"] as? Int, entry.byteCount, path)
        XCTAssertEqual(row["sha256"] as? String, entry.sha256, path)
        XCTAssertEqual(row["git_blob_oid"] as? String, entry.gitBlobOID, path)
        XCTAssertEqual(row["copy"] as? String, entry.copy, path)
        let bytes = try data("\(Self.cardHistoryDirectory)/\(entry.copy)")
        XCTAssertEqual(bytes.count, entry.byteCount, path)
        XCTAssertEqual(digest(bytes).uppercased(), entry.sha256, path)
        var blob = Insecure.SHA1()
        blob.update(data: Data("blob \(bytes.count)\u{0}".utf8))
        blob.update(data: bytes)
        XCTAssertEqual(blob.finalize().map { String(format: "%02x", $0) }.joined(), entry.gitBlobOID, path)
        return bytes
    }

    private var rootURL: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }
    private func data(_ path: String) throws -> Data { try Data(contentsOf: rootURL.appendingPathComponent(path)) }
    private func object(_ path: String) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: data(path)) as? [String: Any]) }
    private func dictionary(_ object: [String: Any], _ key: String) throws -> [String: Any] { try XCTUnwrap(object[key] as? [String: Any]) }
    private func objects(_ object: [String: Any], _ key: String) throws -> [[String: Any]] { try XCTUnwrap(object[key] as? [[String: Any]]) }
    private func strings(_ object: [String: Any], _ key: String) throws -> [String] { try XCTUnwrap(object[key] as? [String]) }
    private func canonical(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
