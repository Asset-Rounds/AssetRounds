import CryptoKit
import Foundation
import XCTest

/// Owner decision A (2026-09-25): S10 card-time state tests prove their facts against the
/// committed S10 history instead of today's live CI and record files.
///
/// Each entry is the exact git blob of `path` at `commit`, copied to
/// `docs/design/v23/integration/s10-card-history/blobs/` and indexed by `manifest.json`
/// there. A copy is admitted only when its byte count, SHA-256 and git blob id equal the
/// pins below, and its bindings to the receipt-bound S10 records hold:
/// `docs/design/s10/s10-stage-checkpoints.json` (five accepted receipts), the S10.4
/// amendment manifest it binds, and the S10.4 validator that manifest binds. Reviewers can
/// recheck every row with `git rev-parse <commit>:<path>`.
enum S10CardHistoryV1 {
    enum Card: String, CaseIterable {
        case inventory = "S10.1"
        case componentSystem = "S10.2"
        case migration = "S10.3"
        case automatedLab = "S10.4"

        var gateID: String {
            switch self {
            case .inventory: return "s10.1-inventory"
            case .componentSystem: return "s10.2-component-system"
            case .migration: return "s10.3-migration"
            case .automatedLab: return "s10.4-automated-lab"
            }
        }
    }

    /// E, K and C follow the S10 receipt model recorded in the stage checkpoints.
    enum CommitRole: String {
        case productHead = "E"
        case evidenceHead = "K"
        case receipt = "C"
    }

    enum Binding: Equatable {
        /// The sha256 is recorded for this document by the named gate's checkpoint row.
        case checkpointDocument(gateID: String, documentType: String)
        /// The copy holds exactly one checkpoint row, equal to the card's current row.
        case checkpointRow
        /// The S10.4 validator records `Get-GitBlobSha256 '<E>' '<path>'` equal to the sha256.
        case validatorLine
        /// The checkpoint-bound S10.4 manifest records the sha256 at this key path.
        case manifestField([String])
        /// The checkpoint-bound S10.4 manifest records this path's head SHA-256 and git blob id.
        case manifestHeadRow
        /// The historical E manifest copy lists this overlay file's byte count and sha256.
        case historicalOverlay
        /// The historical E manifest copy's base authority records this path and sha256.
        case historicalBase(pathKey: String, hashKey: String)
        /// Bound only by the git blob id; recheck with `git rev-parse <commit>:<path>`.
        case gitBlobOnly
    }

    struct Entry {
        let card: Card
        let path: String
        let commit: String
        let role: CommitRole
        let byteCount: Int
        let sha256: String
        let gitBlobOID: String
        let bindings: [Binding]

        var copyPath: String {
            let fileExtension = (path as NSString).pathExtension
            return "\(S10CardHistoryV1.directory)/blobs/\(sha256.prefix(16)).\(fileExtension)"
        }
    }

    struct HistoryFailure: Error, CustomStringConvertible {
        let description: String
    }

    static let directory = "docs/design/v23/integration/s10-card-history"
    static let checkpointsPath = "docs/design/s10/s10-stage-checkpoints.json"
    static let automationRoot = "docs/design/s10/authority/s10.4-automation-amendment-v1"

    private static let e1 = "44e9f9471f8ced9ecdd85f241a79c3750c38412d"
    private static let k1 = "29a49d0145980bf1cb3c1f6ec260a6af579902d4"
    private static let c1 = "fc26103d120eff3a632d353cce4f0d9168a35040"
    private static let e2 = "28c5851a432db026251012de1e396a5896c9f91f"
    private static let e3 = "e1004c9cfeff932e904046e0ad1aa31d2bb2c139"
    private static let e4 = "0adebd72ae0226a80e14eaf515ca133072fb1c76"

    static let entries: [Entry] = [
        .init(card: .inventory, path: "docs/design/s10/s10-stage-checkpoints.json", commit: c1, role: .receipt,
              byteCount: 2_669, sha256: "4EB92CA3DF6D9EF0DC49450A88F921191D8D78C87E0B02026A19EA007C26D1AA",
              gitBlobOID: "e06a4a0c8a5c7f8431795af1cdfb3ea6cee8ab2d", bindings: [.checkpointRow]),
        .init(card: .inventory, path: "docs/design/s10/s10-screen-state-inventory.json", commit: k1, role: .evidenceHead,
              byteCount: 173_645, sha256: "40CF1DC0BD5BA1373CEBADE6956FFCDB100B34279764173BBBB2DBE01D524B71",
              gitBlobOID: "2a3f525c097008d16c341ac541d55da9ad92fd65",
              bindings: [.checkpointDocument(gateID: "s10.1-inventory", documentType: "screen_state_inventory")]),
        .init(card: .inventory, path: "docs/design/s10/s10-accessibility-common-tasks.json", commit: k1, role: .evidenceHead,
              byteCount: 58_904, sha256: "B7EDB1DD18BAB6DEE1884DA52C15F63AD5AD06045F58444C61442957558999F0",
              gitBlobOID: "e4bae1d13d1bc879d4efc5d5052b755b8f71f33c",
              bindings: [.checkpointDocument(gateID: "s10.1-inventory", documentType: "accessibility_common_tasks")]),
        .init(card: .inventory, path: "docs/design/s10/s10-token-coverage.json", commit: k1, role: .evidenceHead,
              byteCount: 70_212, sha256: "7F6310CD68E1EEA01EC4AB47D0AB56BDF5C15644794FD7360C36AB498BD2A428",
              gitBlobOID: "7bce6000101fb8e44b051d4336c204b49129b9dd",
              bindings: [.checkpointDocument(gateID: "s10.1-inventory", documentType: "token_coverage")]),
        .init(card: .inventory, path: "docs/design/s10/s10-visual-regression.json", commit: k1, role: .evidenceHead,
              byteCount: 145_044, sha256: "C111BB31056801C996049E94B3B1ACEFCDAAC6BBABD80576644F751799319AB1",
              gitBlobOID: "52a6e8bf2678a421b0ecddfb5af057f14fc1277e",
              bindings: [.checkpointDocument(gateID: "s10.1-inventory", documentType: "visual_regression")]),
        .init(card: .inventory, path: "docs/design/s10/s10-experience-validation.json", commit: k1, role: .evidenceHead,
              byteCount: 7_128, sha256: "804341D6E9E287EE19954576B1E9FB38B887163B6C5C255D94FCCC1EB279F69F",
              gitBlobOID: "0689172951f8529ce876419a37324bb4dd51e322",
              bindings: [.checkpointDocument(gateID: "s10.1-inventory", documentType: "experience_validation")]),
        .init(card: .inventory, path: "docs/design/s10/s10-store-readiness.json", commit: k1, role: .evidenceHead,
              byteCount: 8_649, sha256: "D8AB503B5864C812E4E808DC214D9351E95BA58DC496D6505905E69408DAEABA",
              gitBlobOID: "7a72ccd5c8270ec335f0aa805d606a5be184a534",
              bindings: [.checkpointDocument(gateID: "s10.1-inventory", documentType: "store_readiness")]),
        .init(card: .inventory, path: "Scripts/ci-selection.json", commit: e1, role: .productHead,
              byteCount: 348, sha256: "2845C608EE15C2B53990C613D19981FFA713F02BD034CF2E007B7514573BF012",
              gitBlobOID: "4cc7d79942d42b7e649cadfa3bb38a03676c2593", bindings: [.gitBlobOnly]),
        .init(card: .componentSystem, path: "docs/design/s10/s10-token-coverage.json", commit: e2, role: .productHead,
              byteCount: 70_212, sha256: "7F6310CD68E1EEA01EC4AB47D0AB56BDF5C15644794FD7360C36AB498BD2A428",
              gitBlobOID: "7bce6000101fb8e44b051d4336c204b49129b9dd",
              bindings: [.checkpointDocument(gateID: "s10.1-inventory", documentType: "token_coverage")]),
        .init(card: .componentSystem, path: "Scripts/ci-selection.json", commit: e2, role: .productHead,
              byteCount: 346, sha256: "55236E8C1FD515B5517BC1813CD6B065320DEDD0380CC51257426696969BBD88",
              gitBlobOID: "933598e9f8e7817466b5a9d84f2f03a395134738", bindings: [.gitBlobOnly]),
        .init(card: .migration, path: "docs/design/s10/s10-token-coverage.json", commit: e3, role: .productHead,
              byteCount: 70_817, sha256: "D52B72B86D40AB93EE58BD467A0B83834D7F58ABAB39C08096DFBF094719B476",
              gitBlobOID: "30197325f25445b588802e20acf41cc63b3af29e",
              bindings: [.checkpointDocument(gateID: "s10.2-component-system", documentType: "token_coverage")]),
        .init(card: .migration, path: "Scripts/ci-selection.json", commit: e3, role: .productHead,
              byteCount: 348, sha256: "5EFEF5082CD41316FF7FFA13663B4F6A641A536B8D93DF3DCCAB8C0196F217B5",
              gitBlobOID: "3e4f27a298ee37ffc6ff65fb21528c619ea9e715", bindings: [.gitBlobOnly]),
        .init(card: .migration, path: "FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift", commit: e3, role: .productHead,
              byteCount: 69_419, sha256: "E23F458F7E23A1721069C25C97AE4BDCAD02A45DC37D24C7F5EB38840C1FF818",
              gitBlobOID: "ab2bdcd84f3432a5a1fe2b8ee501b4cddb0128d1", bindings: [.gitBlobOnly]),
        .init(card: .automatedLab, path: ".github/workflows/ios-ci-worker.yml", commit: e4, role: .productHead,
              byteCount: 358_152, sha256: "DA888041E1743303935415DD6BEE50D185E892784FC9570C123B888290E4EE25",
              gitBlobOID: "139526a9bc66ee142fda234087124214e33efeb9",
              bindings: [.validatorLine, .manifestField(["github_environment_contract", "worker_source_sha256"])]),
        .init(card: .automatedLab, path: ".github/workflows/ios-ci.yml", commit: e4, role: .productHead,
              byteCount: 111_753, sha256: "64BEB60B465EB71B708FB19FEC2061E6F05FFA74A3D93955A88BB3CADC9D3A85",
              gitBlobOID: "b99960edae5ee7a103dd274ea321a9fbfd519331", bindings: [.validatorLine]),
        .init(card: .automatedLab, path: "Scripts/build-smoke.sh", commit: e4, role: .productHead,
              byteCount: 2_439, sha256: "1FBA2AF708AC653E61B7B3F63D22202D80AE3A116E3201958A232C59CCF3A419",
              gitBlobOID: "1b501459c45212ac2a8cc6ff3f2f9b8aaffa3e28", bindings: [.manifestHeadRow]),
        .init(card: .automatedLab, path: "Scripts/ci-selection.json", commit: e4, role: .productHead,
              byteCount: 354, sha256: "692DD6F7DBCF771170191E7839C6B6281FB0A72603475FF2D0D81E35078330E2",
              gitBlobOID: "c45e329467d06f01a1bcdfcc2e6d34da54bfc541", bindings: [.gitBlobOnly]),
        .init(card: .automatedLab, path: "Scripts/s10-4-ci.py", commit: e4, role: .productHead,
              byteCount: 125_982, sha256: "58BFD7988C9A4DDD847D96532BBE5A9BB617ADDC5C3B1521F9FEE06F28228354",
              gitBlobOID: "120a4f2e357b231a9189c7c5c1317db1deaad4c0", bindings: [.validatorLine]),
        .init(card: .automatedLab, path: "Scripts/test-s10-4-ci.py", commit: e4, role: .productHead,
              byteCount: 105_462, sha256: "857AA47537D225FE2DF7AFAAD0C0EF4DB60509CCCE910E334920927571FB74B0",
              gitBlobOID: "a4ab774fae0d9a2effa14a043b332035268d4628", bindings: [.validatorLine]),
        .init(card: .automatedLab, path: "Scripts/test-smoke.sh", commit: e4, role: .productHead,
              byteCount: 21_721, sha256: "B867B89806AD6864E2F7569226C3DD0FF00A5559B75DB7ECECAE46198BEDECD7",
              gitBlobOID: "93ea7e6b26d59ec558bf982b2d0fae1c2e01bbfc", bindings: [.manifestHeadRow]),
        .init(card: .automatedLab, path: "\(automationRoot)/manifest.json", commit: e4, role: .productHead,
              byteCount: 26_259, sha256: "F29BB5F29C0876BEAE1C32C7D6A418BC29AB43C8882CCDC0F622922FD042238C",
              gitBlobOID: "f9dd3c74eeaec8ecd9b44431ef194a11d6d9b415",
              bindings: [.validatorLine, .manifestField(["required_profile_acceptance_policy", "native_manifest_sha256"])]),
        .init(card: .automatedLab, path: "\(automationRoot)/s10-visual-regression.schema.json", commit: e4, role: .productHead,
              byteCount: 54_103, sha256: "46C2DE3BE87CCA26CDFFA4F952E248732C7827134828B4BB9E5EE36943DC9B0A",
              gitBlobOID: "fc5b3a56e34bf14892449ae8cee47f4d43cbed6c", bindings: [.historicalOverlay]),
        .init(card: .automatedLab, path: "\(automationRoot)/s10-accessibility-common-tasks.schema.json", commit: e4, role: .productHead,
              byteCount: 7_108, sha256: "E0893E86636F9F558103FED7173432998F18A459613EECAAB9A4B0CD65CEA0E3",
              gitBlobOID: "65d86819526388ef9d763de995b1be0fbf5bfade", bindings: [.historicalOverlay]),
        .init(card: .automatedLab, path: "\(automationRoot)/validate-s10-contracts.ps1", commit: e4, role: .productHead,
              byteCount: 109_768, sha256: "9C8F3ED23CCE2A8C2517A9B3E46DAE5AFD40DC5EF4857FF5164AD84228043678",
              gitBlobOID: "15c7581d9af158c7b78cce4b339ce1170539c7fc", bindings: [.historicalOverlay]),
        .init(card: .automatedLab, path: "docs/execution/V4_IMPLEMENTATION_RUNBOOK.md", commit: e4, role: .productHead,
              byteCount: 118_381, sha256: "4AEB0D438DCF1D3F82C25F2D343D3D5A69FBEB66F056AB5762BF010AB634DB69",
              gitBlobOID: "29dff475d3634e751e2627b082d4695cc19aba83",
              bindings: [.historicalBase(pathKey: "runbook_path", hashKey: "runbook_sha256")]),
        .init(card: .automatedLab, path: "docs/design/s10/s10-activation.json", commit: e4, role: .productHead,
              byteCount: 16_969, sha256: "804DD9E6D6DC87E358F16CB9A9C5DAAE0727D192067836C6687B5890485CD184",
              gitBlobOID: "535f71e479f6d047b8de64f1b9e24cd9d0226c7a",
              bindings: [.historicalBase(pathKey: "activation_path", hashKey: "activation_sha256")]),
        .init(card: .automatedLab, path: "docs/design/s10/s10-accessibility-common-tasks.json", commit: e4, role: .productHead,
              byteCount: 58_904, sha256: "B7EDB1DD18BAB6DEE1884DA52C15F63AD5AD06045F58444C61442957558999F0",
              gitBlobOID: "e4bae1d13d1bc879d4efc5d5052b755b8f71f33c",
              bindings: [.checkpointDocument(gateID: "s10.1-inventory", documentType: "accessibility_common_tasks")]),
        .init(card: .automatedLab, path: "docs/design/s10/s10-token-coverage.json", commit: e4, role: .productHead,
              byteCount: 75_169, sha256: "904BFF5904E25C43C3101038AA3836BDD9C66CE0E83E342A36F563D54988BBEE",
              gitBlobOID: "a323bbc2ddfae709dd23d7aa7d2db48d30a27aa4",
              bindings: [.checkpointDocument(gateID: "s10.3-migration", documentType: "token_coverage")]),
        .init(card: .automatedLab, path: "docs/design/s10/s10-visual-regression.json", commit: e4, role: .productHead,
              byteCount: 145_044, sha256: "C111BB31056801C996049E94B3B1ACEFCDAAC6BBABD80576644F751799319AB1",
              gitBlobOID: "52a6e8bf2678a421b0ecddfb5af057f14fc1277e",
              bindings: [.checkpointDocument(gateID: "s10.1-inventory", documentType: "visual_regression")]),
    ]

    static func entry(card: Card, path: String) -> Entry? {
        entries.first { $0.card == card && $0.path == path }
    }

    /// The exact card-time bytes of `path`, or nil when the card reads that path live.
    static func data(card: Card, path: String, repositoryRoot: URL) throws -> Data? {
        guard let match = Self.entry(card: card, path: path) else { return nil }
        return try verifiedCopy(match, repositoryRoot: repositoryRoot)
    }

    static func verifiedCopy(_ entry: Entry, repositoryRoot: URL) throws -> Data {
        let bytes = try Data(contentsOf: repositoryRoot.appendingPathComponent(entry.copyPath))
        guard bytes.count == entry.byteCount,
              sha256Hex(bytes) == entry.sha256,
              gitBlobOID(bytes) == entry.gitBlobOID
        else {
            throw HistoryFailure(
                description: "S10 card-history copy differs from its pinned git blob: "
                    + "\(entry.card.rawValue) \(entry.path) at \(entry.commit)"
            )
        }
        return bytes
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02X", $0) }.joined()
    }

    /// Git's object id for a blob: SHA-1 over "blob <byte count>\0" followed by the bytes.
    static func gitBlobOID(_ data: Data) -> String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(data.count)\u{0}".utf8))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Proves every copy the card reads is the recorded S10 history: the pinned blob, the
    /// index row, the card's E/K/C heads in the stage checkpoints, and each named binding.
    static func assertBoundToCommittedHistory(
        card: Card,
        repositoryRoot: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let cardEntries = entries.filter { $0.card == card }
        XCTAssertFalse(cardEntries.isEmpty, card.rawValue, file: file, line: line)
        XCTAssertEqual(
            Set(cardEntries.map(\.path)).count, cardEntries.count,
            "Duplicate history path for \(card.rawValue)", file: file, line: line
        )

        let index = try object(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: repositoryRoot.appendingPathComponent("\(directory)/manifest.json"))
            )
        )
        XCTAssertEqual(index["document_id"] as? String, "v23-s10-card-history-v1", file: file, line: line)
        let indexRows = try rows(index, "entries").filter { ($0["card_id"] as? String) == card.rawValue }
        XCTAssertEqual(indexRows.count, cardEntries.count, card.rawValue, file: file, line: line)
        for (row, entry) in zip(indexRows, cardEntries) {
            XCTAssertEqual(row["gate_id"] as? String, card.gateID, entry.path, file: file, line: line)
            XCTAssertEqual(row["path"] as? String, entry.path, file: file, line: line)
            XCTAssertEqual(row["commit"] as? String, entry.commit, entry.path, file: file, line: line)
            XCTAssertEqual(row["commit_role"] as? String, entry.role.rawValue, entry.path, file: file, line: line)
            XCTAssertEqual(row["byte_count"] as? Int, entry.byteCount, entry.path, file: file, line: line)
            XCTAssertEqual(row["sha256"] as? String, entry.sha256, entry.path, file: file, line: line)
            XCTAssertEqual(row["git_blob_oid"] as? String, entry.gitBlobOID, entry.path, file: file, line: line)
            XCTAssertEqual(
                row["copy"] as? String,
                String(entry.copyPath.dropFirst(directory.count + 1)),
                entry.path, file: file, line: line
            )
        }

        let checkpoints = try rows(
            object(JSONSerialization.jsonObject(
                with: Data(contentsOf: repositoryRoot.appendingPathComponent(checkpointsPath))
            )),
            "checkpoints"
        )
        func checkpoint(_ gateID: String) throws -> [String: Any] {
            let matches = checkpoints.filter { ($0["gate_id"] as? String) == gateID }
            guard matches.count == 1, let match = matches.first else {
                throw HistoryFailure(description: "Missing unique S10 checkpoint \(gateID)")
            }
            return match
        }
        let cardCheckpoint = try checkpoint(card.gateID)

        var automationManifest: [String: Any]?
        var validatorText: String?
        func currentAutomationManifest() throws -> [String: Any] {
            if let automationManifest { return automationManifest }
            let path = "\(automationRoot)/manifest.json"
            let bytes = try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
            let recorded = try rows(try checkpoint("s10.4-automated-lab"), "documents")
                .filter { ($0["path"] as? String) == path }
                .compactMap { $0["sha256"] as? String }
            XCTAssertEqual(recorded, [sha256Hex(bytes)], "Receipt-bound S10.4 manifest", file: file, line: line)
            let value = try object(JSONSerialization.jsonObject(with: bytes))
            automationManifest = value
            return value
        }
        func currentValidatorText() throws -> String {
            if let validatorText { return validatorText }
            let path = "\(automationRoot)/validate-s10-contracts.ps1"
            let bytes = try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
            let overlay = try rows(try currentAutomationManifest(), "overlay_files")
                .filter { ($0["path"] as? String) == "validate-s10-contracts.ps1" }
            XCTAssertEqual(overlay.count, 1, file: file, line: line)
            XCTAssertEqual(overlay.first?["sha256"] as? String, sha256Hex(bytes), "Manifest-bound validator", file: file, line: line)
            let value = String(decoding: bytes, as: UTF8.self)
            validatorText = value
            return value
        }
        func historicalAutomationManifest() throws -> [String: Any] {
            let path = "\(automationRoot)/manifest.json"
            let historical = try XCTUnwrap(
                entries.first { $0.card == .automatedLab && $0.path == path },
                file: file, line: line
            )
            return try object(JSONSerialization.jsonObject(
                with: verifiedCopy(historical, repositoryRoot: repositoryRoot)
            ))
        }

        for entry in cardEntries {
            let bytes = try verifiedCopy(entry, repositoryRoot: repositoryRoot)
            XCTAssertFalse(bytes.contains(0x0D), entry.path, file: file, line: line)
            switch entry.role {
            case .productHead:
                XCTAssertEqual(cardCheckpoint["product_head"] as? String, entry.commit, entry.path, file: file, line: line)
            case .evidenceHead:
                XCTAssertEqual(cardCheckpoint["evidence_head"] as? String, entry.commit, entry.path, file: file, line: line)
            case .receipt:
                break
            }
            for binding in entry.bindings {
                switch binding {
                case let .checkpointDocument(gateID, documentType):
                    let recorded = try rows(try checkpoint(gateID), "documents").filter {
                        ($0["path"] as? String) == entry.path
                            && ($0["document_type"] as? String) == documentType
                    }
                    XCTAssertEqual(recorded.count, 1, "\(gateID) \(entry.path)", file: file, line: line)
                    XCTAssertEqual(recorded.first?["sha256"] as? String, entry.sha256, "\(gateID) \(entry.path)", file: file, line: line)
                    if entry.role == .evidenceHead {
                        XCTAssertEqual(recorded.first?["blob_commit"] as? String, entry.commit, entry.path, file: file, line: line)
                    }
                case .checkpointRow:
                    let historicalRows = try rows(object(JSONSerialization.jsonObject(with: bytes)), "checkpoints")
                    XCTAssertEqual(historicalRows.count, 1, entry.path, file: file, line: line)
                    let historicalRow = try XCTUnwrap(historicalRows.first, file: file, line: line)
                    XCTAssertTrue(
                        NSDictionary(dictionary: historicalRow).isEqual(NSDictionary(dictionary: cardCheckpoint)),
                        "Receipt row at \(entry.commit) must equal the committed \(card.gateID) row",
                        file: file, line: line
                    )
                case .validatorLine:
                    let expected = "Assert-Equal (Get-GitBlobSha256 '\(entry.commit)' '\(entry.path)') '\(entry.sha256)'"
                    XCTAssertEqual(
                        try currentValidatorText().components(separatedBy: expected).count - 1, 1,
                        expected, file: file, line: line
                    )
                case let .manifestField(keyPath):
                    var value: Any? = try currentAutomationManifest()
                    for key in keyPath {
                        value = (value as? [String: Any])?[key]
                    }
                    XCTAssertEqual(value as? String, entry.sha256, keyPath.joined(separator: "."), file: file, line: line)
                case .manifestHeadRow:
                    let repair = try XCTUnwrap(
                        try currentAutomationManifest()["historical_native_ancestry_authorization_repair"] as? [String: Any],
                        file: file, line: line
                    )
                    let heads = try rows(repair, "h416_verified_paths") + rows(repair, "h417_verified_paths")
                    let matches = heads.filter {
                        ($0["path"] as? String) == entry.path
                            && ($0["headSHA256"] as? String) == entry.sha256
                            && ($0["headBlobOID"] as? String) == entry.gitBlobOID
                    }
                    XCTAssertFalse(matches.isEmpty, entry.path, file: file, line: line)
                case .historicalOverlay:
                    let name = (entry.path as NSString).lastPathComponent
                    let overlay = try rows(try historicalAutomationManifest(), "overlay_files").filter {
                        ($0["path"] as? String) == name
                    }
                    XCTAssertEqual(overlay.count, 1, name, file: file, line: line)
                    XCTAssertEqual(overlay.first?["byte_length"] as? Int, entry.byteCount, name, file: file, line: line)
                    XCTAssertEqual(overlay.first?["sha256"] as? String, entry.sha256, name, file: file, line: line)
                case let .historicalBase(pathKey, hashKey):
                    let base = try XCTUnwrap(
                        try historicalAutomationManifest()["base_authority"] as? [String: Any],
                        file: file, line: line
                    )
                    XCTAssertEqual(base[pathKey] as? String, entry.path, file: file, line: line)
                    XCTAssertEqual(base[hashKey] as? String, entry.sha256, entry.path, file: file, line: line)
                case .gitBlobOnly:
                    XCTAssertEqual(entry.gitBlobOID.count, 40, entry.path, file: file, line: line)
                }
            }
        }
    }

    private static func object(_ value: Any) throws -> [String: Any] {
        guard let object = value as? [String: Any] else {
            throw HistoryFailure(description: "Expected a JSON object")
        }
        return object
    }

    private static func rows(_ value: [String: Any], _ key: String) throws -> [[String: Any]] {
        guard let rows = value[key] as? [[String: Any]] else {
            throw HistoryFailure(description: "Expected an object array at \(key)")
        }
        return rows
    }
}
