import CryptoKit
import Foundation
import XCTest

final class V9_90BrandHIGStateInventoryTests: XCTestCase {
    private let inventoryPath = "docs/product/brand/V23P04C27BrandHIGStateInventoryV1.json"
    private let corpusPath = "FieldEvidenceAppTests/Fixtures/V21/Brand/V23P04C27BrandHIGStateInventoryCorpusV1.json"
    private let contractPath = "docs/design/v23/tooling/V23P04C27BrandHIGStateInventoryContractV1.json"
    private let evidencePath = "docs/design/v23/tooling/V23P04C27BrandHIGStateInventoryEvidenceReceiptV1.json"
    private let impactPath = "docs/design/v23/tooling/V23P04C27BrandImpactManifestV1.json"
    private let toolingManifestPath = "docs/design/v23/tooling/V23-P04-C27-tooling-manifest.json"

    func testV23P04C27G01CompleteBrandHIGStateInventoryAndFreeze() throws {
        let root = try object(inventoryPath)
        XCTAssertEqual(root["schema"] as? String, "V23P04C27BrandHIGStateInventoryV1")
        XCTAssertEqual(root["schemaVersion"] as? Int, 1)
        XCTAssertEqual(root["cardID"] as? String, "V23-P04-C27")
        XCTAssertEqual(root["syntheticOnly"] as? Bool, true)

        let contracts = try dictionary(root, "contracts")
        XCTAssertEqual(Set(contracts.keys), [
            "affectedConsumerGraph", "appIconReleaseManifest", "applicationStateInventory",
            "brandHIGStateInventory", "brandPrePolishFreezeReceipt", "brandVocabularyMap",
            "technicalIdentityFreeze",
        ])
        XCTAssertEqual(
            try primaryContractNames(contracts),
            [
                "BrandHIGStateInventoryContractV1", "ApplicationStateInventoryV1",
                "BrandVocabularyMapV1", "TechnicalIdentityFreezeV1",
            ]
        )
        XCTAssertEqual(
            try typedSubrecordNames(contracts),
            ["AffectedConsumerGraphV1", "BrandPrePolishFreezeReceiptV1", "AppIconReleaseManifestV1"]
        )

        let states = try dictionary(contracts, "applicationStateInventory")
        let rendererOwners = try arrayOfDictionaries(states, "rendererOwners")
        XCTAssertFalse(rendererOwners.isEmpty)
        let rendererIdentities = try rendererOwners.flatMap { owner -> [String] in
            let path = try string(owner, "path")
            return try strings(owner, "renderers").map { "\(path)#\($0)" }
        }
        XCTAssertEqual(Set(rendererIdentities).count, rendererIdentities.count)
        XCTAssertEqual(Set(try strings(states, "roots")), ["ASSETS", "REPORTS", "TODAY", "WORK"])
        XCTAssertTrue(Set(try strings(states, "commonStates")).isSuperset(of: [
            "LOADING_PROGRESS", "EMPTY", "DISABLED", "PERMISSION_DENIED", "OFFLINE",
            "SAVE_COMMIT", "ERROR_RETRY", "STALE_ASYNC_COMPLETION", "KEYBOARD_FOCUS",
            "BACKGROUND_COVER", "RESTORATION", "INTERRUPTION",
        ]))
        XCTAssertTrue(Set(try strings(states, "accessibilityVariants")).isSuperset(of: [
            "AX1", "AX2", "AX3", "AX4", "AX5", "VOICEOVER", "VOICE_CONTROL",
            "SWITCH_CONTROL", "DARK", "HIGH_CONTRAST", "REDUCE_MOTION", "RTL",
        ]))

        let freeze = try dictionary(contracts, "brandPrePolishFreezeReceipt")
        XCTAssertEqual(freeze["automaticBaselineUpdate"] as? Bool, false)
        XCTAssertEqual(freeze["inFlightExceptionCountFrozen"] as? Bool, false)
        XCTAssertEqual(freeze["freezeDisposition"] as? String, "PRE_POLISH_INVENTORY_ONLY")
        XCTAssertTrue(try c27FlagsAreClosed(root))
        XCTAssertTrue(try allBindingsMatchRepository(root))
        XCTAssertTrue(try rendererOwnersMatchRepository(states))
    }

    func testV23P04C27A01GovernedReuseAndDualRuntimeSemanticParity() throws {
        let root = try object(inventoryPath)
        let contracts = try dictionary(root, "contracts")
        let state = try dictionary(contracts, "applicationStateInventory")
        XCTAssertEqual(try strings(state, "runtimeProfiles"), [
            "MINIMUM_IOS_18", "LATEST_ACCEPTED_STABLE_SHIPPING_RUNTIME",
        ])
        XCTAssertEqual(state["unknownOwnerDisposition"] as? String, "FAIL_CLOSED")
        XCTAssertEqual(Set(try strings(state, "evidenceRecipes")), [
            "STATIC_SOURCE_DIGEST", "SYNTHETIC_UI", "SYNTHETIC_UNIT",
            "TARGETED_ACCESSIBILITY", "TARGETED_INTERRUPTION", "TARGETED_RECOVERY",
        ])

        let freeze = try dictionary(contracts, "brandPrePolishFreezeReceipt")
        XCTAssertEqual(Set(try strings(freeze, "reentryTriggers")), [
            "AUDIT_SIGNATURE", "COLOR", "DEVICE_RUNTIME", "DYNAMIC_TYPE", "GEOMETRY",
            "LOCALE", "RENDERER", "SEMANTIC_IDENTITY", "TEXT",
        ])
        XCTAssertEqual(freeze["automaticBaselineUpdate"] as? Bool, false)

        let corpus = try object(corpusPath)
        XCTAssertEqual(corpus["schema"] as? String, "V23P04C27BrandHIGStateInventoryCorpusV1")
        let cases = try arrayOfDictionaries(corpus, "cases")
        let caseIDs = try cases.map { try string($0, "caseID") }
        XCTAssertEqual(Set(caseIDs).count, caseIDs.count)
        XCTAssertTrue(try cases.contains { row in
            let caseID = try self.string(row, "caseID")
            let expected = try self.string(row, "expected")
            return caseID == "R02_REUSED_HEAD_WITH_CHANGED_INPUT_BYTES"
                && expected == "REJECT_CHANGED_INPUT_DIGEST"
        })
        XCTAssertEqual(Set(try strings(freeze, "reentryTriggers")), [
            "AUDIT_SIGNATURE", "COLOR", "DEVICE_RUNTIME", "DYNAMIC_TYPE", "GEOMETRY",
            "LOCALE", "RENDERER", "SEMANTIC_IDENTITY", "TEXT",
        ])
    }

    func testV23P04C27H01HostileIdentityVocabularyStateAndIconDriftFailClosed() throws {
        let pristine = try object(inventoryPath)
        XCTAssertTrue(try c27InventoryValid(pristine))
        let corpus = try object(corpusPath)
        let hostileCases = try arrayOfDictionaries(corpus, "cases")
        let unknownOwner = try XCTUnwrap(hostileCases.first {
            $0["caseID"] as? String == "H12_UNKNOWN_RENDERER_OWNER"
        })
        XCTAssertEqual(unknownOwner["expected"] as? String, "REJECT_UNKNOWN_OWNER")
        XCTAssertEqual(
            (unknownOwner["mutation"] as? [String: Any])?["rendererPath"] as? String,
            "FieldEvidenceApp/UnknownView.swift"
        )

        let mutations: [(String, (inout [String: Any]) throws -> Void)] = [
            ("technical rename", { root in
                var contracts = try self.dictionary(root, "contracts")
                var identity = try self.dictionary(contracts, "technicalIdentityFreeze")
                identity["renameAllowed"] = true
                contracts["technicalIdentityFreeze"] = identity
                root["contracts"] = contracts
            }),
            ("bundle identity", { root in
                try self.mutateTechnicalIdentity("bundleIDs", value: ["com.example.assetrounds"], root: &root)
            }),
            ("backup UTI", { root in
                try self.mutateTechnicalIdentity("backupUTI", value: "com.example.assetroundsbackup", root: &root)
            }),
            ("backup extension", { root in
                try self.mutateTechnicalIdentity("backupExtension", value: "assetroundsbackup", root: &root)
            }),
            ("storage root", { root in
                try self.mutateTechnicalIdentity("storageRoots", value: ["AssetRoundsData"], root: &root)
            }),
            ("StoreKit product", { root in
                try self.mutateTechnicalIdentity("storeKitProductIDs", value: ["com.example.assetrounds.monthly"], root: &root)
            }),
            ("entry point", { root in
                try self.mutateTechnicalIdentity("entryPointIdentity", value: "AssetRoundsApp", root: &root)
            }),
            ("target identity", { root in
                try self.mutateTechnicalIdentity("targetNames", value: ["AssetRounds"], root: &root)
            }),
            ("module identity", { root in
                try self.mutateTechnicalIdentity("moduleNames", value: ["AssetRounds"], root: &root)
            }),
            ("visible residue", { root in
                var contracts = try self.dictionary(root, "contracts")
                var vocabulary = try self.dictionary(contracts, "brandVocabularyMap")
                vocabulary["residuePolicy"] = "ALLOW_FIELD_EVIDENCE"
                contracts["brandVocabularyMap"] = vocabulary
                root["contracts"] = contracts
            }),
            ("package leakage", { root in
                var contracts = try self.dictionary(root, "contracts")
                var vocabulary = try self.dictionary(contracts, "brandVocabularyMap")
                vocabulary["genericShell"] = try self.strings(vocabulary, "genericShell") + ["sign"]
                contracts["brandVocabularyMap"] = vocabulary
                root["contracts"] = contracts
            }),
            ("missing renderer owner", { root in try self.dropStateValue("rendererOwners", from: &root) }),
            ("missing recipe", { root in try self.dropStateValue("evidenceRecipes", from: &root) }),
            ("missing AX edge", { root in
                var contracts = try self.dictionary(root, "contracts")
                var state = try self.dictionary(contracts, "applicationStateInventory")
                state["accessibilityVariants"] = try self.strings(state, "accessibilityVariants").filter { $0 != "AX5" }
                contracts["applicationStateInventory"] = state
                root["contracts"] = contracts
            }),
            ("missing consumer edge", { root in
                var contracts = try self.dictionary(root, "contracts")
                var graph = try self.dictionary(contracts, "affectedConsumerGraph")
                graph["edges"] = []
                contracts["affectedConsumerGraph"] = graph
                root["contracts"] = contracts
            }),
            ("partial ALL_RENDERERS expansion", { root in
                var contracts = try self.dictionary(root, "contracts")
                var graph = try self.dictionary(contracts, "affectedConsumerGraph")
                var edges = try self.arrayOfDictionaries(graph, "edges")
                let index = try XCTUnwrap(edges.firstIndex { $0["source"] as? String == "DESIGN_TOKENS" })
                edges[index]["consumers"] = ["ReportsRootView"]
                graph["edges"] = edges
                contracts["affectedConsumerGraph"] = graph
                root["contracts"] = contracts
            }),
            ("unknown renderer path", { root in
                var contracts = try self.dictionary(root, "contracts")
                var state = try self.dictionary(contracts, "applicationStateInventory")
                var owners = try self.arrayOfDictionaries(state, "rendererOwners")
                owners.append(["path": "FieldEvidenceApp/UnknownView.swift", "renderers": ["UnknownView"]])
                state["rendererOwners"] = owners
                contracts["applicationStateInventory"] = state
                root["contracts"] = contracts
            }),
            ("nonexistent renderer symbol", { root in
                var contracts = try self.dictionary(root, "contracts")
                var state = try self.dictionary(contracts, "applicationStateInventory")
                var owners = try self.arrayOfDictionaries(state, "rendererOwners")
                var first = try XCTUnwrap(owners.first)
                first["renderers"] = try self.strings(first, "renderers") + ["NonexistentRendererSymbol"]
                owners[0] = first
                state["rendererOwners"] = owners
                contracts["applicationStateInventory"] = state
                root["contracts"] = contracts
            }),
            ("duplicate renderer state", { root in
                var contracts = try self.dictionary(root, "contracts")
                var state = try self.dictionary(contracts, "applicationStateInventory")
                var owners = try self.arrayOfDictionaries(state, "rendererOwners")
                owners.append(try XCTUnwrap(owners.first))
                state["rendererOwners"] = owners
                contracts["applicationStateInventory"] = state
                root["contracts"] = contracts
            }),
            ("automatic baseline", { root in
                var contracts = try self.dictionary(root, "contracts")
                var freeze = try self.dictionary(contracts, "brandPrePolishFreezeReceipt")
                freeze["automaticBaselineUpdate"] = true
                contracts["brandPrePolishFreezeReceipt"] = freeze
                root["contracts"] = contracts
            }),
            ("fabricated icon", { root in
                var contracts = try self.dictionary(root, "contracts")
                var icons = try self.dictionary(contracts, "appIconReleaseManifest")
                icons["appStoreArtwork1024"] = "SUPPLIED"
                contracts["appIconReleaseManifest"] = icons
                root["contracts"] = contracts
            }),
            ("C26 draft adoption", { root in
                var discovery = try self.dictionary(root, "discovery")
                var drafts = try self.arrayOfDictionaries(discovery, "c26Drafts")
                drafts[0]["adopted"] = true
                discovery["c26Drafts"] = drafts
                root["discovery"] = discovery
            }),
        ]
        for (label, mutate) in mutations {
            var hostile = pristine
            try mutate(&hostile)
            XCTAssertFalse(try c27InventoryValid(hostile), label)
        }

        var missingKey = pristine
        var missingContracts = try dictionary(missingKey, "contracts")
        missingContracts.removeValue(forKey: "applicationStateInventory")
        missingKey["contracts"] = missingContracts
        XCTAssertFalse(try c27InventoryValid(missingKey), "missing typed key must fail closed")

        var wrongType = pristine
        wrongType["contracts"] = ["applicationStateInventory": "corrupt"]
        XCTAssertFalse(try c27InventoryValid(wrongType), "decoder/type failure must fail closed")

        var extraContract = pristine
        var extraContracts = try dictionary(extraContract, "contracts")
        extraContracts["SecondRuntimeStore"] = ["contract": "SecondRuntimeStoreV1"]
        extraContract["contracts"] = extraContracts
        XCTAssertFalse(try c27InventoryValid(extraContract), "unknown contract key must fail closed")
    }

    func testV23P04C27I01ManifestLastInterruptionAndDeterministicRetry() throws {
        let evidence = try object(evidencePath)
        let interruption = try dictionary(evidence, "generatorInterruptionProtocol")
        XCTAssertEqual(interruption["protocol"] as? String, "MANIFEST_LAST_ATOMIC_REPLACE")
        XCTAssertEqual(interruption["deterministicRerun"] as? Bool, true)
        XCTAssertEqual(interruption["realWorktreeUnchanged"] as? Bool, true)
        let rows = try arrayOfDictionaries(interruption, "rows")
        XCTAssertEqual(try rows.map { try string($0, "boundary") }, [
            "BEFORE_ARTIFACTS", "AFTER_ARTIFACTS_BEFORE_MANIFEST", "AFTER_MANIFEST",
        ])
        XCTAssertEqual(try rows.map { try integer($0, "acceptedSetCount") }, [0, 0, 1])
        XCTAssertEqual(try rows.map { try integer($0, "retryAcceptedSetCount") }, [1, 1, 1])
        XCTAssertTrue(rows.allSatisfy { $0["manifestLast"] as? Bool == true })
        XCTAssertTrue(rows.allSatisfy { $0["retryDeterministic"] as? Bool == true })
    }

    func testV23P04C27R01PreflightRemainsProvisionalUntilLaterAuthorities() throws {
        for path in [inventoryPath, contractPath, evidencePath, impactPath, toolingManifestPath] {
            let root = try object(path)
            XCTAssertTrue(try c27FlagsAreClosed(root), path)
        }
        let contract = try object(contractPath)
        XCTAssertEqual(contract["provisional"] as? Bool, true)
        let semantics = try dictionary(contract, "semantics")
        XCTAssertEqual(semantics["sevenContracts"] as? String, "NONPERSISTENT_INVENTORY_EVIDENCE")
        XCTAssertEqual(semantics["newDurableRecordCount"] as? Int, 0)
        XCTAssertEqual(try strings(semantics, "newDurableFamilies"), [])
        XCTAssertEqual(try object(toolingManifestPath)["finalHashesSealed"] as? Bool, false)

        let preflight = try String(decoding: data("Scripts/release-preflight.sh"), as: UTF8.self)
        XCTAssertTrue(preflight.contains("verify_p04_c27_contracts.py --complete --json"))
        XCTAssertTrue(preflight.contains("generate_p04_c27_contracts.py --check"))
        XCTAssertTrue(preflight.contains("assert all(value is False for value in flags.values())"))
        XCTAssertTrue(preflight.contains("manifest[\"finalHashesSealed\"] is False"))
        XCTAssertTrue(preflight.contains("uiAcceptanceCredit\"] is False"))
    }

    private func c27InventoryValid(_ root: [String: Any]) throws -> Bool {
        do {
            return try c27InventoryValidUnchecked(root)
        } catch {
            return false
        }
    }

    private func c27InventoryValidUnchecked(_ root: [String: Any]) throws -> Bool {
        guard try c27FlagsAreClosed(root),
              let contracts = root["contracts"] as? [String: Any],
              Set(contracts.keys) == [
                  "affectedConsumerGraph", "appIconReleaseManifest", "applicationStateInventory",
                  "brandHIGStateInventory", "brandPrePolishFreezeReceipt", "brandVocabularyMap",
                  "technicalIdentityFreeze",
              ],
              try primaryContractNames(contracts) == [
                  "BrandHIGStateInventoryContractV1", "ApplicationStateInventoryV1",
                  "BrandVocabularyMapV1", "TechnicalIdentityFreezeV1",
              ],
              try typedSubrecordNames(contracts) == [
                  "AffectedConsumerGraphV1", "BrandPrePolishFreezeReceiptV1", "AppIconReleaseManifestV1",
              ] else { return false }
        let identity = try dictionary(contracts, "technicalIdentityFreeze")
        guard identity["renameAllowed"] as? Bool == false,
              identity["historicDisplayMutationAllowed"] as? Bool == false,
              identity["backupUTI"] as? String == "com.palatis3.fieldrecordbackup",
              identity["backupExtension"] as? String == "fieldrecordbackup",
              identity["entryPointIdentity"] as? String == "FieldEvidenceAppApp",
              try strings(identity, "bundleIDs") == [
                  "com.palatis3.fieldrecord", "com.palatis3.fieldrecord.tests",
                  "com.palatis3.fieldrecord.uitests",
              ],
              try strings(identity, "storageRoots") == [
                  "FieldEvidenceData", "FieldEvidenceOperations", "FieldEvidenceRestore",
              ],
              try strings(identity, "storeKitProductIDs") == [
                  "com.palatis3.fieldrecord.sub.solo.monthly.v1",
              ],
              try strings(identity, "targetNames") == [
                  "FieldEvidenceApp", "FieldEvidenceAppTests", "FieldEvidenceAppUITests",
              ],
              try strings(identity, "moduleNames") == [
                  "FieldEvidenceApp", "FieldEvidenceAppTests", "FieldEvidenceAppUITests",
              ],
              try technicalIdentitySourcesMatchRepository(identity) else { return false }
        let vocabulary = try dictionary(contracts, "brandVocabularyMap")
        let generic = Set(try strings(vocabulary, "genericShell"))
        guard vocabulary["residuePolicy"] as? String == "ZERO_UNALLOWLISTED_VISIBLE_FIELD_EVIDENCE",
              generic == ["asset", "evidence", "report", "work", "workspace"],
              generic.isDisjoint(with: ["sign", "lighting", "luminaire", "survey"]) else { return false }
        let state = try dictionary(contracts, "applicationStateInventory")
        let owners = try arrayOfDictionaries(state, "rendererOwners")
        let identities = try owners.flatMap { owner -> [String] in
            let path = try string(owner, "path")
            return try strings(owner, "renderers").map { "\(path)#\($0)" }
        }
        guard !owners.isEmpty,
              Set(identities).count == identities.count,
              !((state["evidenceRecipes"] as? [String]) ?? []).isEmpty,
              Set(try strings(state, "accessibilityVariants")).contains("AX5"),
              try rendererOwnersMatchRepository(state) else { return false }
        let graph = try dictionary(contracts, "affectedConsumerGraph")
        guard try affectedConsumerGraphIsComplete(graph, rendererCount: identities.count) else { return false }
        let freeze = try dictionary(contracts, "brandPrePolishFreezeReceipt")
        guard freeze["automaticBaselineUpdate"] as? Bool == false,
              freeze["inFlightExceptionCountFrozen"] as? Bool == false else { return false }
        let icons = try dictionary(contracts, "appIconReleaseManifest")
        guard icons["appStoreArtwork1024"] as? String == "NOT_PRODUCED",
              icons["selectedBuildSetting"] is NSNull,
              icons["selectedSourcePath"] is NSNull else { return false }
        let discovery = try dictionary(root, "discovery")
        return try arrayOfDictionaries(discovery, "c26Drafts").allSatisfy {
            $0["adopted"] as? Bool == false
        }
    }

    private func c27FlagsAreClosed(_ root: [String: Any]) throws -> Bool {
        let flags = try dictionary(root, "statusFlags")
        let keys = Set(flags.keys)
        let productKeys: Set<String> = ["acceptance", "adoption", "hosted", "native", "publication", "release"]
        let toolingKeys = productKeys.union(["activation", "physicalDevice"])
        return (keys == productKeys || keys == toolingKeys)
            && flags.values.allSatisfy { $0 as? Bool == false }
    }

    private func allBindingsMatchRepository(_ root: [String: Any]) throws -> Bool {
        let discovery = try dictionary(root, "discovery")
        let bindings = try arrayOfDictionaries(discovery, "criticalInputs")
            + arrayOfDictionaries(discovery, "c26Drafts")
        return try bindings.allSatisfy { binding in
            let path = try string(binding, "path")
            let expected = try string(binding, "sha256")
            return !path.hasPrefix("/") && !path.contains("..") && sha256(try data(path)) == expected
        }
    }

    private func primaryContractNames(_ contracts: [String: Any]) throws -> [String] {
        try ["brandHIGStateInventory", "applicationStateInventory", "brandVocabularyMap", "technicalIdentityFreeze"]
            .map { try string(dictionary(contracts, $0), "contract") }
    }

    private func typedSubrecordNames(_ contracts: [String: Any]) throws -> [String] {
        try ["affectedConsumerGraph", "brandPrePolishFreezeReceipt", "appIconReleaseManifest"]
            .map { try string(dictionary(contracts, $0), "contract") }
    }

    private func dropStateValue(_ key: String, from root: inout [String: Any]) throws {
        var contracts = try dictionary(root, "contracts")
        var state = try dictionary(contracts, "applicationStateInventory")
        state.removeValue(forKey: key)
        contracts["applicationStateInventory"] = state
        root["contracts"] = contracts
    }

    private func mutateTechnicalIdentity(
        _ key: String, value: Any, root: inout [String: Any]
    ) throws {
        var contracts = try dictionary(root, "contracts")
        var identity = try dictionary(contracts, "technicalIdentityFreeze")
        identity[key] = value
        contracts["technicalIdentityFreeze"] = identity
        root["contracts"] = contracts
    }

    private func technicalIdentitySourcesMatchRepository(_ identity: [String: Any]) throws -> Bool {
        let paths = try strings(identity, "backupIdentitySources") + [
            try string(identity, "schemaIdentitySource"),
            try string(identity, "wireIdentitySource"),
        ]
        return Set(paths).count == paths.count && paths.allSatisfy {
            !$0.hasPrefix("/") && !$0.contains("..")
                && FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent($0).path)
        }
    }

    private func rendererOwnersMatchRepository(_ state: [String: Any]) throws -> Bool {
        let owners = try arrayOfDictionaries(state, "rendererOwners")
        for owner in owners {
            let path = try string(owner, "path")
            guard !path.hasPrefix("/"), !path.contains("..") else { return false }
            let bytes: Data
            do {
                bytes = try data(path)
            } catch {
                return false
            }
            let source = String(decoding: bytes, as: UTF8.self)
            let renderers = try strings(owner, "renderers")
            guard !renderers.isEmpty, renderers.allSatisfy({ source.contains($0) }) else { return false }
        }
        return true
    }

    private func affectedConsumerGraphIsComplete(
        _ graph: [String: Any], rendererCount: Int
    ) throws -> Bool {
        guard graph["unknownConsumerDisposition"] as? String == "FAIL_CLOSED",
              graph["ordering"] as? String == "SOURCE_THEN_CONSUMER_ASCENDING",
              rendererCount > 0 else { return false }
        let expected: [String: Set<String>] = [
            "DESIGN_TOKENS": ["ALL_RENDERERS"],
            "SHARED_COMPONENTS": ["ALL_RENDERERS"],
            "BRAND_VOCABULARY": ["ALL_PUBLIC_COPY", "REPORTS", "SUPPORT_EXPORT"],
            "ROUTE_REGISTRY": ["NAVIGATION", "RESTORATION", "PRIVATE_DISCOVERY"],
            "SEMANTIC_IDENTITIES": ["VOICEOVER", "VOICE_CONTROL", "UI_TESTS"],
            "TECHNICAL_IDENTITIES": ["BACKUP", "RESTORE", "DELETE", "REPORT", "SEARCH"],
        ]
        let edges = try arrayOfDictionaries(graph, "edges")
        guard edges.count == expected.count else { return false }
        var observed: [String: Set<String>] = [:]
        for edge in edges {
            let source = try string(edge, "source")
            guard observed[source] == nil else { return false }
            observed[source] = Set(try strings(edge, "consumers"))
        }
        guard observed == expected else { return false }
        let allRendererSources = observed.keys.filter {
            observed[$0] == Set(["ALL_RENDERERS"])
        }
        let expandedConsumerCount = observed.values.reduce(0) { result, consumers in
            result + (consumers == ["ALL_RENDERERS"] ? rendererCount : consumers.count)
        }
        let explicitConsumerCount = expected.values
            .filter { $0 != ["ALL_RENDERERS"] }
            .reduce(0) { $0 + $1.count }
        return allRendererSources.count == 2
            && expandedConsumerCount == rendererCount * 2 + explicitConsumerCount
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    }

    private func object(_ relativePath: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(relativePath)) as? [String: Any])
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

    private func sha256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
