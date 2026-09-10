import CryptoKit
import Foundation
import XCTest

final class S10_6BrandReleaseTests: XCTestCase {
    private let productHead = "0adebd72ae0226a80e14eaf515ca133072fb1c76"
    private let evidenceHead = "e2189af36a89caf815cf078756341c1f1542f7df"
    private let receiptHead = "0d54add4a5d09ec3b54483a1fc2a55d8eea8b0e3"

    private let historicalMutableSourcePaths: Set<String> = [
        "Release/PrivacyReviewV1.md",
        "Release/UnsignedRCMetadataV1.json",
        "Release/LaunchSmokeEvidenceIndexV1.json",
        "docs/design/s10/s10-activation.json",
        "docs/design/s10/s10-store-readiness.json",
    ]

    func testBuiltPrivacyManifestEqualsSourceAndReviewDescribesSourceOnlyTruth() throws {
        let sourcePrivacy = try data("FieldEvidenceApp/PrivacyInfo.xcprivacy")
        let builtPrivacyURL = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        )
        XCTAssertEqual(try Data(contentsOf: builtPrivacyURL), sourcePrivacy)

        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: sourcePrivacy,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((plist["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        XCTAssertEqual((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)

        let review = try json(
            "docs/design/s10/evidence/s10.6/privacy-supply-chain-review.json"
        )
        XCTAssertEqual(review["document_status"] as? String, "PREPARED_SOURCE_REVIEW")
        XCTAssertEqual(review["review_scope"] as? String,
                       "source_only_no_archive_no_signing_no_runtime_network_capture")
        XCTAssertEqual(review["source_product_head"] as? String, productHead)
        XCTAssertEqual(review["accepted_s10_4_evidence_head"] as? String, evidenceHead)
        XCTAssertEqual(review["accepted_s10_4_receipt_head"] as? String, receiptHead)
        XCTAssertEqual(review["release_ready"] as? Bool, false)

        let sourceFiles = try rows(review, "source_files")
        XCTAssertEqual(sourceFiles.count, 36)
        let paths = try sourceFiles.map { try string($0, "path") }
        XCTAssertEqual(Set(paths).count, 36)
        for row in sourceFiles {
            let path = try string(row, "path")
            let recordedHash = try string(row, "sha256")
            XCTAssertTrue(isSHA256(recordedHash), path)
            guard !historicalMutableSourcePaths.contains(path) else { continue }
            XCTAssertEqual(try data(path).sha256, recordedHash, path)
        }

        let privacy = try object(review, "privacy_manifest")
        XCTAssertEqual(privacy["path"] as? String, "FieldEvidenceApp/PrivacyInfo.xcprivacy")
        XCTAssertEqual(privacy["tracking"] as? Bool, false)
        XCTAssertEqual((privacy["tracking_domains"] as? [Any])?.count, 0)
        XCTAssertEqual((privacy["collected_data_types"] as? [Any])?.count, 0)
        let accessed = try rows(privacy, "accessed_api_types")
        XCTAssertEqual(
            Set(try accessed.map { try string($0, "category") }),
            [
                "NSPrivacyAccessedAPICategoryDiskSpace",
                "NSPrivacyAccessedAPICategoryFileTimestamp",
                "NSPrivacyAccessedAPICategoryUserDefaults",
            ]
        )
        let reasons = try Dictionary(uniqueKeysWithValues: accessed.map {
            (try string($0, "category"), Set(try strings($0, "reasons")))
        })
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryDiskSpace"], ["E174.1"])
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"], ["3B52.1", "C617.1"])
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])

        let archive = try object(review, "archive_privacy_report")
        XCTAssertEqual(archive["status"] as? String, "NOT_RUN")
        XCTAssertNil(archive["archive_identity"] as? String)
        XCTAssertNil(archive["privacy_report_sha256"] as? String)
    }

    func testExactTwelveRuntimeAssetsMatchActivationManifestAndSourceHashes() throws {
        let activation = try json("docs/design/s10/s10-activation.json")
        let manifest = try json("docs/design/s10/authority/asset-manifest.json")
        let review = try json(
            "docs/design/s10/evidence/s10.6/privacy-supply-chain-review.json"
        )
        XCTAssertTrue(validateRuntimeAssetReview(review, activation: activation, manifest: manifest))

        let runtimeAssets = try rows(review, "runtime_assets")
        for row in runtimeAssets {
            let path = try string(row, "path")
            XCTAssertEqual(try data(path).sha256, try string(row, "sha256"), path)
        }
        let comparison = try object(review, "runtime_asset_allowlist_comparison")
        XCTAssertEqual(comparison["expected_count"] as? Int, 12)
        XCTAssertEqual(comparison["actual_count"] as? Int, 12)
        XCTAssertEqual(comparison["source_status"] as? String, "PASS")
        XCTAssertEqual(comparison["archive_asset_inventory_status"] as? String, "NOT_RUN")
    }

    func testPreparationMetadataAndFourHistoricalCheckpointsRemainTruthfullyPending() throws {
        let metadata = try json("Release/UnsignedRCMetadataV1.json")
        let smoke = try json("Release/LaunchSmokeEvidenceIndexV1.json")
        let stages = try json("docs/design/s10/s10-stage-checkpoints.json")
        let store = try json("docs/design/s10/s10-store-readiness.json")
        let lock = try json("docs/design/s10/s10-evidence-lock.json")
        let screenshotManifest = try json(
            "docs/design/s10/evidence/s10.6/store-screenshot-manifest.json"
        )
        let privacyReview = try json(
            "docs/design/s10/evidence/s10.6/privacy-supply-chain-review.json"
        )

        XCTAssertTrue(validatePendingPreparation(
            metadata: metadata,
            smoke: smoke,
            stages: stages,
            store: store,
            lock: lock,
            screenshotManifest: screenshotManifest,
            privacyReview: privacyReview
        ))
        XCTAssertFalse(hasPhysicalAndLegalPrerequisites(
            screenshotManifest: screenshotManifest,
            privacyReview: privacyReview
        ))
    }

    func testStoreManifestPreservesFiveFrozenSlotsAndClaimProvenanceWithoutMedia() throws {
        let store = try json("docs/design/s10/s10-store-readiness.json")
        let manifest = try json(
            "docs/design/s10/evidence/s10.6/store-screenshot-manifest.json"
        )
        XCTAssertEqual(manifest["document_status"] as? String, "prepared_not_approved")
        XCTAssertEqual(manifest["source_product_head"] as? String, productHead)
        XCTAssertEqual(manifest["accepted_automated_evidence_head"] as? String, evidenceHead)
        XCTAssertEqual(manifest["accepted_automated_receipt_head"] as? String, receiptHead)
        XCTAssertEqual(manifest["release_ready"] as? Bool, false)
        XCTAssertEqual(manifest["physical_verification_status"] as? String, "DEFERRED")

        let plan = try object(store, "plan")
        let frozenSlots = try rows(plan, "screenshot_slots")
        let slots = try rows(manifest, "slots")
        let expectedStateIDs = [
            "state.sign-detail.ready",
            "state.capture.wide-preview",
            "state.report-detail.ready",
            "state.issue.recheck-due",
            "state.backup.ready",
        ]
        XCTAssertEqual(slots.count, 5)
        XCTAssertEqual(try slots.map { try string($0, "slot_id") },
                       try frozenSlots.map { try string($0, "slot_id") })
        XCTAssertEqual(slots.compactMap { $0["slot_order"] as? Int }, Array(1...5))
        XCTAssertEqual(try slots.map { try string($0, "story_role") },
                       try frozenSlots.map { try string($0, "story_role") })
        XCTAssertEqual(slots.compactMap { $0["screen_state_id"] as? String }, expectedStateIDs)
        for (slot, frozen) in zip(slots, frozenSlots) {
            for key in [
                "gate_id", "device_class", "device_profile_id", "locale_profile_id",
                "orientation", "pixel_width", "pixel_height", "slot_id", "slot_order",
                "story_role",
            ] {
                XCTAssertEqual(String(describing: slot[key]), String(describing: frozen[key]), key)
            }
            XCTAssertEqual(slot["pixel_width"] as? Int, frozen["pixel_width"] as? Int)
            XCTAssertEqual(slot["pixel_height"] as? Int, frozen["pixel_height"] as? Int)
            XCTAssertEqual(slot["source_product_head"] as? String, productHead)
            XCTAssertEqual(slot["source_run_id"] as? String, "34481147676")
            XCTAssertEqual(slot["source_artifact_id"] as? String, "10155130147")
            XCTAssertFalse(try string(slot, "path").isEmpty)
            XCTAssertTrue(isSHA256(try string(slot, "sha256")))
            XCTAssertEqual(slot["s10_4_visual_review_status"] as? String, "APPROVED")
            XCTAssertEqual(slot["store_review_status"] as? String, "NOT_RUN")
            XCTAssertEqual(slot["store_approved"] as? Bool, false)
            XCTAssertTrue(slot["store_reviewer"] is NSNull)
            XCTAssertTrue(slot["store_review_evidence_id"] is NSNull)
        }

        let plannedClaims = try rows(plan, "planned_claims")
        let claims = try rows(manifest, "claims")
        XCTAssertEqual(claims.count, 5)
        XCTAssertEqual(try claims.map { try string($0, "claim_id") },
                       try plannedClaims.map { try string($0, "claim_id") })
        for (claim, planned) in zip(claims, plannedClaims) {
            XCTAssertEqual(claim["gate_id"] as? String, planned["gate_id"] as? String)
            XCTAssertEqual(claim["text"] as? String, planned["text"] as? String)
            XCTAssertEqual(try strings(claim, "screen_state_ids"),
                           try strings(planned, "screen_state_ids"))
            XCTAssertEqual(Set(claim.keys), Set(planned.keys))
        }

        let pendingGates = try strings(manifest, "pending_gates")
        XCTAssertTrue(pendingGates.contains("physical_s10_5"))
        XCTAssertTrue(pendingGates.contains("dated_trademark_name_claim_url_clearance"))
        let clearance = try object(manifest, "rights_and_clearance")
        XCTAssertEqual(clearance["name_clearance_status"] as? String, "PENDING")
        XCTAssertEqual(clearance["claim_clearance_status"] as? String, "PENDING")
        XCTAssertEqual(clearance["url_clearance_status"] as? String, "PENDING")
        XCTAssertTrue(clearance["dated_clearance_evidence"] is NSNull)
    }

    func testMutationsFailClosedForAssetsReadinessPhysicalAndLegalEvidence() throws {
        let activation = try json("docs/design/s10/s10-activation.json")
        let assetManifest = try json("docs/design/s10/authority/asset-manifest.json")
        let review = try json(
            "docs/design/s10/evidence/s10.6/privacy-supply-chain-review.json"
        )
        XCTAssertTrue(validateRuntimeAssetReview(review, activation: activation, manifest: assetManifest))

        var extraAsset = deepCopy(review)
        var assets = try rows(extraAsset, "runtime_assets")
        assets.append([
            "path": "FieldEvidenceApp/Resources/Assets.xcassets/extra.png",
            "sha256": String(repeating: "A", count: 64),
        ])
        extraAsset["runtime_assets"] = assets
        XCTAssertFalse(validateRuntimeAssetReview(extraAsset, activation: activation, manifest: assetManifest))

        var wrongHash = deepCopy(review)
        var wrongAssets = try rows(wrongHash, "runtime_assets")
        wrongAssets[0]["sha256"] = String(repeating: "0", count: 64)
        wrongHash["runtime_assets"] = wrongAssets
        XCTAssertFalse(validateRuntimeAssetReview(wrongHash, activation: activation, manifest: assetManifest))

        let smoke = try json("Release/LaunchSmokeEvidenceIndexV1.json")
        let stages = try json("docs/design/s10/s10-stage-checkpoints.json")
        let store = try json("docs/design/s10/s10-store-readiness.json")
        let lock = try json("docs/design/s10/s10-evidence-lock.json")
        let screenshots = try json(
            "docs/design/s10/evidence/s10.6/store-screenshot-manifest.json"
        )
        let metadata = try json("Release/UnsignedRCMetadataV1.json")

        var falseReady = deepCopy(metadata)
        falseReady["releaseReady"] = true
        XCTAssertFalse(validatePendingPreparation(
            metadata: falseReady, smoke: smoke, stages: stages, store: store,
            lock: lock, screenshotManifest: screenshots, privacyReview: review
        ))
        var readyClaimScreenshots = deepCopy(screenshots)
        readyClaimScreenshots["release_ready"] = true
        readyClaimScreenshots["physical_verification_status"] = "PASS"
        var completeClearance = try object(readyClaimScreenshots, "rights_and_clearance")
        completeClearance["name_clearance_status"] = "PASS"
        completeClearance["claim_clearance_status"] = "PASS"
        completeClearance["url_clearance_status"] = "PASS"
        completeClearance["trademark_clearance_status"] = "CLEARED"
        completeClearance["trademark_evidence_id"] = "fixture-trademark-clearance"
        completeClearance["dated_clearance_evidence"] = ["evidence_id": "fixture"]
        readyClaimScreenshots["rights_and_clearance"] = completeClearance

        var missingPhysical = deepCopy(review)
        missingPhysical["store_readiness_gaps"] = []
        XCTAssertFalse(hasPhysicalAndLegalPrerequisites(
            screenshotManifest: readyClaimScreenshots,
            privacyReview: missingPhysical
        ))

        var fakePhysical = deepCopy(review)
        var physical = try object(fakePhysical, "physical_verification")
        physical["status"] = "PASS"
        fakePhysical["physical_verification"] = physical
        XCTAssertFalse(validatePendingPreparation(
            metadata: metadata, smoke: smoke, stages: stages, store: store,
            lock: lock, screenshotManifest: screenshots, privacyReview: fakePhysical
        ))
        var physicalComplete = deepCopy(review)
        var completedPhysical = try object(physicalComplete, "physical_verification")
        completedPhysical["status"] = "PASS"
        completedPhysical["s10_5_receipt"] = ["evidence_id": "fixture"]
        physicalComplete["physical_verification"] = completedPhysical
        physicalComplete["store_readiness_gaps"] = []
        XCTAssertTrue(hasPhysicalAndLegalPrerequisites(
            screenshotManifest: readyClaimScreenshots,
            privacyReview: physicalComplete
        ))

        var missingDatedEvidence = deepCopy(readyClaimScreenshots)
        var clearanceWithoutDatedEvidence = try object(
            missingDatedEvidence,
            "rights_and_clearance"
        )
        clearanceWithoutDatedEvidence.removeValue(forKey: "dated_clearance_evidence")
        missingDatedEvidence["rights_and_clearance"] = clearanceWithoutDatedEvidence
        XCTAssertFalse(hasPhysicalAndLegalPrerequisites(
            screenshotManifest: missingDatedEvidence,
            privacyReview: physicalComplete
        ))

        var emptyPhysicalReceipt = deepCopy(physicalComplete)
        var physicalWithEmptyReceipt = try object(
            emptyPhysicalReceipt,
            "physical_verification"
        )
        physicalWithEmptyReceipt["s10_5_receipt"] = [String: Any]()
        emptyPhysicalReceipt["physical_verification"] = physicalWithEmptyReceipt
        XCTAssertFalse(hasPhysicalAndLegalPrerequisites(
            screenshotManifest: readyClaimScreenshots,
            privacyReview: emptyPhysicalReceipt
        ))

        var missingLegalScreenshots = deepCopy(readyClaimScreenshots)
        var pendingClearance = try object(missingLegalScreenshots, "rights_and_clearance")
        pendingClearance["name_clearance_status"] = "PENDING"
        pendingClearance["claim_clearance_status"] = "PENDING"
        pendingClearance["url_clearance_status"] = "PENDING"
        pendingClearance["dated_clearance_evidence"] = NSNull()
        missingLegalScreenshots["rights_and_clearance"] = pendingClearance
        XCTAssertFalse(hasPhysicalAndLegalPrerequisites(
            screenshotManifest: missingLegalScreenshots,
            privacyReview: physicalComplete
        ))

        var fakeReleaseCheckpoint = deepCopy(stages)
        var checkpoints = try rows(fakeReleaseCheckpoint, "checkpoints")
        checkpoints.append(["stage": "Release"])
        fakeReleaseCheckpoint["checkpoints"] = checkpoints
        XCTAssertFalse(validatePendingPreparation(
            metadata: metadata, smoke: smoke, stages: fakeReleaseCheckpoint, store: store,
            lock: lock, screenshotManifest: screenshots, privacyReview: review
        ))
    }

    private func validateRuntimeAssetReview(
        _ review: [String: Any],
        activation: [String: Any],
        manifest: [String: Any]
    ) -> Bool {
        guard let card = (activation["cards"] as? [[String: Any]])?
                .first(where: { $0["card_id"] as? String == "S10.2" }),
              let allowedPaths = card["allowed_paths"] as? [String],
              let manifestRows = manifest["files"] as? [[String: Any]],
              let runtimeRows = review["runtime_assets"] as? [[String: Any]]
        else { return false }

        let destinations = allowedPaths.filter {
            $0.hasPrefix("FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/")
                || $0.hasPrefix("FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/")
                || $0.hasPrefix("FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/")
        }
        guard destinations.count == 12,
              Set(destinations).count == 12,
              runtimeRows.count == 12,
              Set(runtimeRows.compactMap { $0["path"] as? String }) == Set(destinations)
        else { return false }

        var manifestHashes = [String: String]()
        for row in manifestRows {
            guard let path = row["path"] as? String,
                  let hash = row["sha256"] as? String,
                  manifestHashes.updateValue(hash, forKey: path) == nil
            else { return false }
        }
        for row in runtimeRows {
            guard let destination = row["path"] as? String,
                  let hash = row["sha256"] as? String,
                  isSHA256(hash),
                  let source = packageSourcePath(for: destination),
                  manifestHashes[source] == hash
            else { return false }
        }
        guard let comparison = review["runtime_asset_allowlist_comparison"] as? [String: Any]
        else { return false }
        return comparison["expected_count"] as? Int == 12
            && comparison["actual_count"] as? Int == 12
            && (comparison["missing_paths"] as? [Any])?.isEmpty == true
            && (comparison["unexpected_paths"] as? [Any])?.isEmpty == true
            && (comparison["content_hash_mismatches"] as? [Any])?.isEmpty == true
            && comparison["source_status"] as? String == "PASS"
            && comparison["archive_asset_inventory_status"] as? String == "NOT_RUN"
    }

    private func validatePendingPreparation(
        metadata: [String: Any],
        smoke: [String: Any],
        stages: [String: Any],
        store: [String: Any],
        lock: [String: Any],
        screenshotManifest: [String: Any],
        privacyReview: [String: Any]
    ) -> Bool {
        guard metadata["releaseReady"] as? Bool == false,
              metadata["unsigned"] as? Bool == true,
              let brand = metadata["brandRefresh"] as? [String: Any],
              brand["card"] as? String == "S10.6",
              brand["preparationStatus"] as? String == "prepared_pending_verification",
              brand["sourceProductHead"] as? String == productHead,
              brand["acceptedAutomatedEvidenceHead"] as? String == evidenceHead,
              brand["acceptedAutomatedReceiptHead"] as? String == receiptHead,
              brand["physicalVerificationStatus"] as? String == "DEFERRED",
              brand["storeStatus"] as? String == "planned",
              brand["evidenceLockStatus"] as? String == "template",
              brand["finalF25Status"] as? String == "NOT_RUN",
              brand["releaseReady"] as? Bool == false,
              let pendingGates = brand["pendingGates"] as? [String],
              !pendingGates.isEmpty,
              brand["evidencePaths"] as? [String: Any] != nil,
              let finalSmoke = smoke["finalRCSmoke"] as? [String: Any],
              let candidate = finalSmoke["brandedCandidate"] as? [String: Any],
              candidate["card"] as? String == "S10.6",
              candidate["selector"] as? String == "FieldEvidenceAppUITests/S10_6BrandReleaseUITests",
              candidate["sourceProductHead"] as? String == productHead,
              candidate["evidenceStatus"] as? String == "NOT_RUN",
              candidate["physicalVerificationStatus"] as? String == "DEFERRED",
              candidate["releaseReady"] as? Bool == false,
              let checkpoints = stages["checkpoints"] as? [[String: Any]],
              checkpoints.compactMap({ $0["stage"] as? String }) == [
                "Inventory", "ComponentSystem", "Migration", "AutomatedLab",
              ],
              store["document_status"] as? String == "planned",
              lock["document_status"] as? String == "template",
              lock["final_product_head"] as? String == "REQUIRED_AFTER_S10_RELEASE_CANDIDATE",
              lock["release_evidence_head"] as? String == "REQUIRED_AFTER_S10_RELEASE_EVIDENCE",
              (lock["documents"] as? [[String: Any]])?.count == 6,
              (lock["machine_gate_ids"] as? [Any])?.isEmpty == true,
              (lock["field_evidence_ids"] as? [Any])?.isEmpty == true,
              (lock["app_store_evidence_ids"] as? [Any])?.isEmpty == true,
              (lock["app_store_claims"] as? [Any])?.isEmpty == true,
              screenshotManifest["release_ready"] as? Bool == false,
              screenshotManifest["physical_verification_status"] as? String == "DEFERRED",
              privacyReview["release_ready"] as? Bool == false,
              let physical = privacyReview["physical_verification"] as? [String: Any],
              physical["status"] as? String == "DEFERRED",
              physical["s10_5_receipt"] is NSNull,
              physical["blocks_release_ready"] as? Bool == true,
              let gaps = privacyReview["store_readiness_gaps"] as? [[String: Any]],
              Set(gaps.compactMap { $0["gate"] as? String }).isSuperset(of: [
                "physical_s10_5_evidence",
                "dated_trademark_name_claim_and_url_clearance",
              ])
        else { return false }
        return true
    }

    // Necessary evidence only. Full release readiness remains outside this bounded test helper.
    private func hasPhysicalAndLegalPrerequisites(
        screenshotManifest: [String: Any],
        privacyReview: [String: Any]
    ) -> Bool {
        guard let clearance = screenshotManifest["rights_and_clearance"] as? [String: Any],
              clearance["grant_accepted"] as? Bool == true,
              let grantEvidenceID = clearance["grant_evidence_id"] as? String,
              !grantEvidenceID.isEmpty,
              clearance["trademark_clearance_status"] as? String == "CLEARED",
              let trademarkEvidenceID = clearance["trademark_evidence_id"] as? String,
              !trademarkEvidenceID.isEmpty,
              clearance["name_clearance_status"] as? String == "PASS",
              clearance["claim_clearance_status"] as? String == "PASS",
              clearance["url_clearance_status"] as? String == "PASS",
              let datedEvidence = clearance["dated_clearance_evidence"] as? [String: Any],
              let datedEvidenceID = datedEvidence["evidence_id"] as? String,
              !datedEvidenceID.isEmpty,
              let physical = privacyReview["physical_verification"] as? [String: Any],
              physical["status"] as? String == "PASS",
              let receipt = physical["s10_5_receipt"] as? [String: Any],
              let receiptEvidenceID = receipt["evidence_id"] as? String,
              !receiptEvidenceID.isEmpty,
              let gaps = privacyReview["store_readiness_gaps"] as? [[String: Any]],
              !gaps.contains(where: {
                  let gate = $0["gate"] as? String
                  return gate == "physical_s10_5_evidence"
                      || gate == "dated_trademark_name_claim_and_url_clearance"
              })
        else { return false }
        return true
    }

    private func packageSourcePath(for destination: String) -> String? {
        let prefix = "FieldEvidenceApp/Resources/Assets.xcassets/"
        guard destination.hasPrefix(prefix) else { return nil }
        let relative = String(destination.dropFirst(prefix.count))
        if relative.hasPrefix("AppIcon.appiconset/") {
            return "AppIcon/" + String(relative.dropFirst("AppIcon.appiconset/".count))
        }
        if relative.hasPrefix("AssetRoundsBrandSymbol.imageset/")
            || relative.hasPrefix("AssetRoundsBrandSymbolTemplate.imageset/") {
            return "Brand/XcodeImagesets/" + relative
        }
        return nil
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    }

    private func json(_ relativePath: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: data(relativePath)) as? [String: Any],
            relativePath
        )
    }

    private func object(_ value: [String: Any], _ key: String) throws -> [String: Any] {
        try XCTUnwrap(value[key] as? [String: Any], key)
    }

    private func rows(_ value: [String: Any], _ key: String) throws -> [[String: Any]] {
        try XCTUnwrap(value[key] as? [[String: Any]], key)
    }

    private func string(_ value: [String: Any], _ key: String) throws -> String {
        try XCTUnwrap(value[key] as? String, key)
    }

    private func strings(_ value: [String: Any], _ key: String) throws -> [String] {
        try XCTUnwrap(value[key] as? [String], key)
    }

    private func deepCopy(_ value: [String: Any]) -> [String: Any] {
        let data = try! JSONSerialization.data(withJSONObject: value)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func isSHA256(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-F]{64}$"#, options: .regularExpression) != nil
    }
}

private extension Data {
    var sha256: String {
        SHA256.hash(data: self).map { String(format: "%02X", $0) }.joined()
    }
}
