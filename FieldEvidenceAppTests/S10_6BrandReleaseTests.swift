import CryptoKit
import Foundation
import XCTest

final class S10_6BrandReleaseTests: XCTestCase {
    private let productHead = "0adebd72ae0226a80e14eaf515ca133072fb1c76"
    private let evidenceHead = "e2189af36a89caf815cf078756341c1f1542f7df"
    private let receiptHead = "0d54add4a5d09ec3b54483a1fc2a55d8eea8b0e3"
    private let physicalResumePolicy = "explicit_owner_request_after_app_store_release"
    private let physicalDeferralPolicyID = "owner-s10-5-nonblocking-post-release-20260910"

    private enum PhaseEvidenceState: String, Equatable {
        case pendingPreparation = "PENDING"
        case evidenceReady = "EVIDENCE_READY"
        case closed = "CLOSED"
    }

    // These facts must be supplied by the repository/Git/API/artifact audit. The
    // JSON documents cannot prove their own ancestry, immutable originals, or review.
    private struct AuthenticatedChecks {
        var candidateHead: String
        var releaseEvidenceHead: String
        var receiptHead: String
        var ancestryVerified: Bool
        var originalsVerified: Bool
        var receiptCommitVerified: Bool
        var predecessorCheckpointHashes: [String]
        var documentHashes: [String: String]
        var verifiedHumanEvidenceIDs: Set<String>
        var verifiedHumanSlotSHA256: [String: [String: String]]
        var verifiedLegalEvidenceIDs: Set<String>
        var sealedDeferralSHA256: String
        var verifiedCIBinding: [String: String] = [:]
        var verifiedTerminalReviews: [String: [String: String]] = [:]
    }

    private struct PhaseDocuments {
        var metadata: [String: Any]
        var smoke: [String: Any]
        var stages: [String: Any]
        var store: [String: Any]
        var lock: [String: Any]
        var screenshots: [String: Any]
        var privacy: [String: Any]
    }

    private let phaseJSONPaths = [
        "Release/UnsignedRCMetadataV1.json",
        "Release/LaunchSmokeEvidenceIndexV1.json",
        "Release/PrivacyReviewV1.md",
        "docs/design/s10/s10-stage-checkpoints.json",
        "docs/design/s10/s10-store-readiness.json",
        "docs/design/s10/s10-evidence-lock.json",
        "docs/design/s10/evidence/s10.6/store-screenshot-manifest.json",
        "docs/design/s10/evidence/s10.6/privacy-supply-chain-review.json",
    ]

    private var nonSelfDocumentRoles: [String: String] { [
        phaseJSONPaths[1]: "launch_smoke",
        phaseJSONPaths[2]: "privacy_narrative",
        phaseJSONPaths[4]: "store_readiness",
        phaseJSONPaths[5]: "evidence_lock",
        phaseJSONPaths[6]: "store_manifest",
        phaseJSONPaths[7]: "privacy_supply_chain",
    ] }

    // The frozen V4.1 checkpoint schema permits these two document classes for
    // the seven S10.6 release records. Every record is a blob at evidence head K.
    private var releaseDocumentTypes: [String: String] { [
        phaseJSONPaths[0]: "release_evidence",
        phaseJSONPaths[1]: "release_evidence",
        phaseJSONPaths[2]: "release_evidence",
        phaseJSONPaths[4]: "store_readiness",
        phaseJSONPaths[5]: "release_evidence",
        phaseJSONPaths[6]: "release_evidence",
        phaseJSONPaths[7]: "release_evidence",
    ] }

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
        XCTAssertTrue(["PREPARED_SOURCE_REVIEW", "PREPARED_SOURCE_AND_SCOPED_HUMAN_REVIEW"]
            .contains(review["document_status"] as? String ?? ""))
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

        let status = phaseContentStatus(metadata)
        if status == "PENDING" {
            XCTAssertTrue(validatePendingPreparation(
                metadata: metadata, smoke: smoke, stages: stages, store: store,
                lock: lock, screenshotManifest: screenshotManifest,
                privacyReview: privacyReview
            ))
        }
        XCTAssertFalse(hasSupportedPhysicalEvidence(privacyReview))

        let documents = PhaseDocuments(
            metadata: metadata, smoke: smoke, stages: stages, store: store,
            lock: lock, screenshots: screenshotManifest, privacy: privacyReview
        )
        let activation = try json("docs/design/s10/s10-activation.json")
        let assetManifest = try json("docs/design/s10/authority/asset-manifest.json")
        let declaredState = try XCTUnwrap(PhaseEvidenceState(rawValue: status))
        let expectedState: PhaseEvidenceState = try rows(stages, "checkpoints").count == 5
            ? .closed : declaredState
        let validatedState = try XCTUnwrap(validatePhaseContent(
            documents, activation: activation, assetManifest: assetManifest
        ))
        XCTAssertEqual(validatedState, expectedState)
        // The actual checkout uses raw file bytes, not fixture JSON fingerprints.
        let envelope = try object(try object(metadata, "brandRefresh"), "phaseEvidence")
        for binding in try rows(envelope, "requiredNonSelfDocuments") {
            XCTAssertEqual(try data(try string(binding, "path")).sha256,
                           try string(binding, "sha256"))
        }
        if let release = try rows(stages, "checkpoints").last,
           release["stage"] as? String == "Release" {
            for binding in try rows(release, "documents") {
                XCTAssertEqual(try data(try string(binding, "path")).sha256,
                               try string(binding, "sha256"))
            }
        }
    }

    func testStoreManifestPreservesFiveFrozenSlotsAndClaimProvenanceWithoutMedia() throws {
        let store = try json("docs/design/s10/s10-store-readiness.json")
        let manifest = try json(
            "docs/design/s10/evidence/s10.6/store-screenshot-manifest.json"
        )
        XCTAssertNotNil(manifest["document_status"] as? String)
        XCTAssertEqual(manifest["source_product_head"] as? String, productHead)
        XCTAssertEqual(manifest["accepted_automated_evidence_head"] as? String, evidenceHead)
        XCTAssertEqual(manifest["accepted_automated_receipt_head"] as? String, receiptHead)
        XCTAssertEqual(manifest["release_ready"] as? Bool, false)
        XCTAssertEqual(manifest["physical_verification_status"] as? String, "DEFERRED")
        XCTAssertEqual(manifest["physical_verification_blocking"] as? Bool, false)
        XCTAssertEqual(try strings(manifest, "deferred_follow_ups"), ["physical_s10_5"])
        XCTAssertEqual(manifest["physical_resume_policy"] as? String, physicalResumePolicy)

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
            XCTAssertTrue(validStoreReviewTuple(slot), "Review must be a complete NOT_RUN or APPROVED tuple")
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
        XCTAssertFalse(pendingGates.contains("physical_s10_5"))
        // These non-stage bytes are frozen at K before C appends the receipt.
        XCTAssertTrue(pendingGates.contains("required_checkpoint_receipts"))
        XCTAssertFalse(pendingGates.contains("all_six_checkpoint_receipts"))
        let clearance = try object(manifest, "rights_and_clearance")
        if hasDatedLegalEvidence(manifest) {
            XCTAssertFalse(pendingGates.contains("dated_trademark_name_claim_url_clearance"))
        } else {
            XCTAssertTrue(pendingGates.contains("dated_trademark_name_claim_url_clearance"))
            XCTAssertEqual(clearance["name_clearance_status"] as? String, "PENDING")
            XCTAssertEqual(clearance["claim_clearance_status"] as? String, "PENDING")
            XCTAssertEqual(clearance["url_clearance_status"] as? String, "PENDING")
            XCTAssertTrue(clearance["dated_clearance_evidence"] is NSNull)
        }
    }

    func testMutationsFailClosedForAssetsReadinessPhysicalAndLegalEvidence() throws {
        let activation = try json("docs/design/s10/s10-activation.json")
        let assetManifest = try json("docs/design/s10/authority/asset-manifest.json")
        let source = try loadPhaseDocuments()
        let pendingFixture = try makePendingFixture(from: source)
        let review = pendingFixture.privacy
        let metadata = pendingFixture.metadata
        let smoke = pendingFixture.smoke
        let stages = pendingFixture.stages
        let store = pendingFixture.store
        let lock = pendingFixture.lock
        let screenshots = pendingFixture.screenshots
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

        var falseReady = deepCopy(metadata)
        falseReady["releaseReady"] = true
        XCTAssertFalse(validatePendingPreparation(
            metadata: falseReady, smoke: smoke, stages: stages, store: store,
            lock: lock, screenshotManifest: screenshots, privacyReview: review
        ))

        var falseBrandReady = deepCopy(metadata)
        var falseReadyBrand = try object(falseBrandReady, "brandRefresh")
        falseReadyBrand["releaseReady"] = true
        falseBrandReady["brandRefresh"] = falseReadyBrand
        XCTAssertFalse(validatePendingPreparation(
            metadata: falseBrandReady, smoke: smoke, stages: stages, store: store,
            lock: lock, screenshotManifest: screenshots, privacyReview: review
        ))

        var falseStoreReady = deepCopy(screenshots)
        falseStoreReady["release_ready"] = true
        XCTAssertFalse(validatePendingPreparation(
            metadata: metadata, smoke: smoke, stages: stages, store: store,
            lock: lock, screenshotManifest: falseStoreReady, privacyReview: review
        ))

        var falsePrivacyReady = deepCopy(review)
        falsePrivacyReady["release_ready"] = true
        XCTAssertFalse(validatePendingPreparation(
            metadata: metadata, smoke: smoke, stages: stages, store: store,
            lock: lock, screenshotManifest: screenshots, privacyReview: falsePrivacyReady
        ))

        var legalEvidenceScreenshots = deepCopy(screenshots)
        var completeClearance = try object(legalEvidenceScreenshots, "rights_and_clearance")
        completeClearance["name_clearance_status"] = "PASS"
        completeClearance["claim_clearance_status"] = "PASS"
        completeClearance["url_clearance_status"] = "PASS"
        completeClearance["trademark_clearance_status"] = "CLEARED"
        completeClearance["trademark_evidence_id"] = "fixture-trademark-clearance"
        completeClearance["dated_clearance_evidence"] = [
            "evidence_id": "fixture",
            "date": "2026-09-10",
            "scope": "trademark_name_five_claims_and_urls",
        ]
        legalEvidenceScreenshots["rights_and_clearance"] = completeClearance
        XCTAssertEqual(
            legalEvidenceScreenshots["physical_verification_status"] as? String,
            "DEFERRED"
        )
        XCTAssertTrue(hasDatedLegalEvidence(legalEvidenceScreenshots))

        var missingPhysical = deepCopy(review)
        missingPhysical["store_readiness_gaps"] = []
        XCTAssertFalse(hasSupportedPhysicalEvidence(missingPhysical))

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
        XCTAssertTrue(hasSupportedPhysicalEvidence(physicalComplete))

        var missingDatedEvidence = deepCopy(legalEvidenceScreenshots)
        var clearanceWithoutDatedEvidence = try object(
            missingDatedEvidence,
            "rights_and_clearance"
        )
        clearanceWithoutDatedEvidence.removeValue(forKey: "dated_clearance_evidence")
        missingDatedEvidence["rights_and_clearance"] = clearanceWithoutDatedEvidence
        XCTAssertFalse(hasDatedLegalEvidence(missingDatedEvidence))

        var emptyPhysicalReceipt = deepCopy(physicalComplete)
        var physicalWithEmptyReceipt = try object(
            emptyPhysicalReceipt,
            "physical_verification"
        )
        physicalWithEmptyReceipt["s10_5_receipt"] = [String: Any]()
        emptyPhysicalReceipt["physical_verification"] = physicalWithEmptyReceipt
        XCTAssertFalse(hasSupportedPhysicalEvidence(emptyPhysicalReceipt))

        var missingLegalScreenshots = deepCopy(legalEvidenceScreenshots)
        var pendingClearance = try object(missingLegalScreenshots, "rights_and_clearance")
        pendingClearance["name_clearance_status"] = "PENDING"
        pendingClearance["claim_clearance_status"] = "PENDING"
        pendingClearance["url_clearance_status"] = "PENDING"
        pendingClearance["dated_clearance_evidence"] = NSNull()
        missingLegalScreenshots["rights_and_clearance"] = pendingClearance
        XCTAssertFalse(hasDatedLegalEvidence(missingLegalScreenshots))

        var fakePhysicalCheckpoint = deepCopy(stages)
        var physicalCheckpoints = try rows(fakePhysicalCheckpoint, "checkpoints")
        physicalCheckpoints.append(["stage": "PhysicalExperience"])
        fakePhysicalCheckpoint["checkpoints"] = physicalCheckpoints
        XCTAssertFalse(validatePendingPreparation(
            metadata: metadata, smoke: smoke, stages: fakePhysicalCheckpoint, store: store,
            lock: lock, screenshotManifest: screenshots, privacyReview: review
        ))

        var fakeReleaseCheckpoint = deepCopy(stages)
        var checkpoints = try rows(fakeReleaseCheckpoint, "checkpoints")
        checkpoints.append(["stage": "Release"])
        fakeReleaseCheckpoint["checkpoints"] = checkpoints
        XCTAssertFalse(validatePendingPreparation(
            metadata: metadata, smoke: smoke, stages: fakeReleaseCheckpoint, store: store,
            lock: lock, screenshotManifest: screenshots, privacyReview: review
        ))

        let current = PhaseDocuments(
            metadata: metadata, smoke: smoke, stages: stages, store: store,
            lock: lock, screenshots: screenshots, privacy: review
        )
        let currentChecks = try fixtureChecks(for: current)
        XCTAssertEqual(
            evaluatePhaseEvidence(
                current, activation: activation, assetManifest: assetManifest,
                checks: currentChecks
            ),
            .pendingPreparation
        )
        var invalidPending = current
        var pendingBrand = try object(invalidPending.metadata, "brandRefresh")
        var pendingEnvelope = try object(pendingBrand, "phaseEvidence")
        pendingEnvelope["releaseEvidenceHead"] = String(repeating: "2", count: 40)
        pendingBrand["phaseEvidence"] = pendingEnvelope
        invalidPending.metadata["brandRefresh"] = pendingBrand
        XCTAssertNil(validatePhaseContent(invalidPending, activation: activation, assetManifest: assetManifest))
        XCTAssertFalse(isDate("2026-02-30"))

        // Actual approved slots may coexist with missing legal/F25 evidence.
        var partiallyReviewed = current
        partiallyReviewed.screenshots["slots"] = try rows(source.screenshots, "slots")
        partiallyReviewed.store["screenshots"] = try rows(source.store, "screenshots")
        if reviewedFiveSlotsRemainFrozen(partiallyReviewed) {
            partiallyReviewed.screenshots["pending_gates"] = try strings(partiallyReviewed.screenshots, "pending_gates")
                .filter { $0 != "store_creative_review" }
            var partialBrand = try object(partiallyReviewed.metadata, "brandRefresh")
            partialBrand["pendingGates"] = try strings(partialBrand, "pendingGates")
                .filter { $0 != "store_creative_review" }
            var partialEnvelope = try object(partialBrand, "phaseEvidence")
            let sourceEnvelope = try object(try object(source.metadata, "brandRefresh"), "phaseEvidence")
            partialEnvelope["humanStoreReview"] = try object(sourceEnvelope, "humanStoreReview")
            partialEnvelope["requiredNonSelfDocuments"] = try fixtureNonSelfBindings(partiallyReviewed)
            partialBrand["phaseEvidence"] = partialEnvelope
            partiallyReviewed.metadata["brandRefresh"] = partialBrand
            XCTAssertEqual(validatePhaseContent(partiallyReviewed, activation: activation,
                                                assetManifest: assetManifest), .pendingPreparation)
        }

        var ready = try makeEvidenceReadyFixture(from: current)
        XCTAssertEqual(validatePhaseContent(
            ready, activation: activation, assetManifest: assetManifest
        ), .evidenceReady)
        var readyChecks = try fixtureChecks(for: ready, fixtureReady: true)
        XCTAssertEqual(
            evaluatePhaseEvidence(
                ready, activation: activation, assetManifest: assetManifest,
                checks: readyChecks
            ),
            .evidenceReady
        )
        var beforeK = readyChecks
        beforeK.releaseEvidenceHead = ""
        beforeK.receiptHead = ""
        beforeK.receiptCommitVerified = false
        XCTAssertEqual(evaluatePhaseEvidence(ready, activation: activation, assetManifest: assetManifest,
                                             checks: beforeK), .evidenceReady)
        var unreviewedMirror = ready
        var mirrorRows = try rows(unreviewedMirror.store, "screenshots")
        mirrorRows[0]["status"] = "NOT_RUN"
        unreviewedMirror.store["screenshots"] = mirrorRows
        XCTAssertNil(validatePhaseContent(unreviewedMirror, activation: activation, assetManifest: assetManifest))
        var wrongTerminal = readyChecks
        wrongTerminal.verifiedTerminalReviews["fixture-human-store-review"] = [
            "headSHA": "0a48504502994fdb8a5d73c9e8cc307aba210821",
            "runID": "34527590250",
            "terminalScreenshotSHA256": "2E200B14E17E1F7632F5F7CF63681FB898C658124C02D08E1CBBF69835A83A7C",
        ]
        XCTAssertNil(evaluatePhaseEvidence(ready, activation: activation, assetManifest: assetManifest,
                                          checks: wrongTerminal))

        var closed = ready
        readyChecks = try fixtureChecks(for: closed, fixtureReady: true)
        closed.stages = try addingSyntheticReleaseCheckpoint(to: closed, checks: readyChecks)
        XCTAssertEqual(phaseDocumentsByPath(closed).mapValues(canonicalSHA256),
                       phaseDocumentsByPath(ready).mapValues(canonicalSHA256))
        XCTAssertEqual(validatePhaseContent(
            closed, activation: activation, assetManifest: assetManifest
        ), .closed)
        XCTAssertEqual(
            evaluatePhaseEvidence(
                closed, activation: activation, assetManifest: assetManifest,
                checks: readyChecks
            ),
            .closed
        )

        var mutation = ready
        var mutationBrand = try object(mutation.metadata, "brandRefresh")
        var mutationEnvelope = try object(mutationBrand, "phaseEvidence")
        mutationEnvelope["releaseEvidenceHead"] = readyChecks.releaseEvidenceHead
        mutationBrand["phaseEvidence"] = mutationEnvelope
        mutation.metadata["brandRefresh"] = mutationBrand
        XCTAssertNil(validatePhaseContent(
            mutation, activation: activation, assetManifest: assetManifest
        ))

        mutation = closed
        var schemaRows = try rows(mutation.stages, "checkpoints")
        var schemaDocuments = try rows(schemaRows[4], "documents")
        schemaDocuments[0]["blob_commit"] = String(repeating: "f", count: 40)
        schemaRows[4]["documents"] = schemaDocuments
        mutation.stages["checkpoints"] = schemaRows
        XCTAssertNil(validatePhaseContent(
            mutation, activation: activation, assetManifest: assetManifest
        ))

        mutation = closed
        schemaRows = try rows(mutation.stages, "checkpoints")
        schemaDocuments = try rows(schemaRows[4], "documents")
        schemaDocuments.append(schemaDocuments[0])
        schemaRows[4]["documents"] = schemaDocuments
        mutation.stages["checkpoints"] = schemaRows
        XCTAssertNil(validatePhaseContent(
            mutation, activation: activation, assetManifest: assetManifest
        ))

        mutation = closed
        schemaRows = try rows(mutation.stages, "checkpoints")
        schemaDocuments = try rows(schemaRows[4], "documents")
        schemaDocuments[0]["document_type"] = "activation"
        schemaRows[4]["documents"] = schemaDocuments
        mutation.stages["checkpoints"] = schemaRows
        XCTAssertNil(validatePhaseContent(
            mutation, activation: activation, assetManifest: assetManifest
        ))

        mutation = closed
        var mutatedStages = try rows(mutation.stages, "checkpoints")
        mutatedStages.insert(["stage": "PhysicalExperience"], at: 4)
        mutation.stages["checkpoints"] = mutatedStages
        XCTAssertNil(evaluatePhaseEvidence(
            mutation, activation: activation, assetManifest: assetManifest, checks: readyChecks
        ))

        mutation = closed
        mutatedStages = try rows(mutation.stages, "checkpoints")
        mutatedStages.append(mutatedStages[4])
        mutation.stages["checkpoints"] = mutatedStages
        XCTAssertNil(evaluatePhaseEvidence(
            mutation, activation: activation, assetManifest: assetManifest, checks: readyChecks
        ))

        mutation = closed
        mutatedStages = try rows(mutation.stages, "checkpoints")
        mutatedStages.swapAt(3, 4)
        mutation.stages["checkpoints"] = mutatedStages
        XCTAssertNil(evaluatePhaseEvidence(
            mutation, activation: activation, assetManifest: assetManifest, checks: readyChecks
        ))

        mutation = closed
        mutatedStages = try rows(mutation.stages, "checkpoints")
        mutatedStages[0]["gate_id"] = "mutated-predecessor"
        mutation.stages["checkpoints"] = mutatedStages
        XCTAssertNil(evaluatePhaseEvidence(
            mutation, activation: activation, assetManifest: assetManifest, checks: readyChecks
        ))

        mutation = closed
        var releaseRows = try rows(mutation.stages, "checkpoints")
        releaseRows[4]["product_head"] = String(repeating: "b", count: 40)
        mutation.stages["checkpoints"] = releaseRows
        XCTAssertNil(evaluatePhaseEvidence(
            mutation, activation: activation, assetManifest: assetManifest, checks: readyChecks
        ))

        var staleK = readyChecks
        staleK.releaseEvidenceHead = String(repeating: "c", count: 40)
        XCTAssertNil(evaluatePhaseEvidence(
            closed, activation: activation, assetManifest: assetManifest, checks: staleK
        ))

        for rejectedChecks in [
            replacingVerificationFlags(in: readyChecks, ancestry: false),
            replacingVerificationFlags(in: readyChecks, originals: false),
            replacingVerificationFlags(in: readyChecks, receiptCommit: false),
        ] {
            XCTAssertNil(evaluatePhaseEvidence(
                closed, activation: activation, assetManifest: assetManifest,
                checks: rejectedChecks
            ))
        }

        mutation = closed
        mutation.screenshots["accepted_automated_receipt_head"] = String(
            repeating: "d", count: 40
        )
        let staleCChecks = try fixtureChecks(for: mutation, fixtureReady: true)
        XCTAssertNil(evaluatePhaseEvidence(
            mutation, activation: activation, assetManifest: assetManifest,
            checks: staleCChecks
        ))

        var staleDocumentChecks = readyChecks
        var staleHashes = staleDocumentChecks.documentHashes
        staleHashes[phaseJSONPaths[1]] = String(repeating: "0", count: 64)
        staleDocumentChecks = replacingDocumentHashes(in: staleDocumentChecks, with: staleHashes)
        XCTAssertNil(evaluatePhaseEvidence(
            closed, activation: activation, assetManifest: assetManifest,
            checks: staleDocumentChecks
        ))

        var unboundDeferral = readyChecks
        unboundDeferral = replacingDeferralHash(
            in: unboundDeferral, with: String(repeating: "0", count: 64)
        )
        XCTAssertNil(evaluatePhaseEvidence(
            closed, activation: activation, assetManifest: assetManifest, checks: unboundDeferral
        ))

        mutation = closed
        var fakeHumanPrivacy = try object(mutation.privacy, "unsigned_preparation_ci")
        fakeHumanPrivacy["humanVisualReviewEvidenceID"] = "unverified-human-review"
        mutation.privacy["unsigned_preparation_ci"] = fakeHumanPrivacy
        var fakeHumanBrand = try object(mutation.metadata, "brandRefresh")
        fakeHumanBrand["unsignedPreparationCI"] = fakeHumanPrivacy
        mutation.metadata["brandRefresh"] = fakeHumanBrand
        var fakeHumanFinal = try object(mutation.smoke, "finalRCSmoke")
        var fakeHumanCandidate = try object(fakeHumanFinal, "brandedCandidate")
        fakeHumanCandidate["unsignedPreparationCI"] = fakeHumanPrivacy
        fakeHumanFinal["brandedCandidate"] = fakeHumanCandidate
        mutation.smoke["finalRCSmoke"] = fakeHumanFinal
        let fakeHumanChecks = try fixtureChecks(for: mutation, fixtureReady: true)
        XCTAssertNil(evaluatePhaseEvidence(
            mutation, activation: activation, assetManifest: assetManifest,
            checks: fakeHumanChecks
        ))

        mutation = closed
        var fakeSlotRows = try rows(mutation.screenshots, "slots")
        fakeSlotRows[0]["store_review_evidence_id"] = "unverified-slot-review"
        mutation.screenshots["slots"] = fakeSlotRows
        let fakeSlotChecks = try fixtureChecks(for: mutation, fixtureReady: true)
        XCTAssertNil(evaluatePhaseEvidence(
            mutation, activation: activation, assetManifest: assetManifest,
            checks: fakeSlotChecks
        ))

        mutation = closed
        var fakeLegal = try object(mutation.screenshots, "rights_and_clearance")
        let ownerAttestation = try object(fakeLegal, "owner_name_attestation")
        fakeLegal["dated_clearance_evidence"] = [
            "evidence_id": try string(ownerAttestation, "evidence_id"),
            "date": "2026-09-10",
        ]
        fakeLegal["trademark_evidence_id"] = try string(ownerAttestation, "evidence_id")
        mutation.screenshots["rights_and_clearance"] = fakeLegal
        let fakeLegalChecks = try fixtureChecks(for: mutation, fixtureReady: true)
        XCTAssertNil(evaluatePhaseEvidence(
            mutation, activation: activation, assetManifest: assetManifest,
            checks: fakeLegalChecks
        ))

        var extraAssetDocuments = closed
        var fixtureAssets = try rows(extraAssetDocuments.privacy, "runtime_assets")
        fixtureAssets.append([
            "path": "FieldEvidenceApp/Resources/Assets.xcassets/extra.png",
            "sha256": String(repeating: "A", count: 64),
        ])
        extraAssetDocuments.privacy["runtime_assets"] = fixtureAssets
        let extraAssetChecks = try authenticatedChecks(
            for: extraAssetDocuments, fixtureReady: true
        )
        XCTAssertNil(evaluatePhaseEvidence(
            extraAssetDocuments, activation: activation, assetManifest: assetManifest,
            checks: extraAssetChecks
        ))
    }

    private func phaseContentStatus(_ metadata: [String: Any]) -> String {
        let brand = metadata["brandRefresh"] as? [String: Any]
        let envelope = brand?["phaseEvidence"] as? [String: Any]
        return envelope?["contentStatus"] as? String ?? "PENDING"
    }

    private func loadPhaseDocuments() throws -> PhaseDocuments {
        PhaseDocuments(
            metadata: try json(phaseJSONPaths[0]), smoke: try json(phaseJSONPaths[1]),
            stages: try json(phaseJSONPaths[3]), store: try json(phaseJSONPaths[4]),
            lock: try json(phaseJSONPaths[5]), screenshots: try json(phaseJSONPaths[6]),
            privacy: try json(phaseJSONPaths[7])
        )
    }

    private func ciBinding(_ ci: [String: Any]) -> [String: String] {
        var binding = [String: String]()
        for key in ["evidenceID", "headSHA", "runID", "artifactID", "artifactSHA256",
                    "terminalScreenshotSHA256"] {
            if let value = ci[key] as? String { binding[key] = value }
        }
        return binding
    }

    private func terminalReviewBinding(_ ci: [String: Any]) -> [String: String] {
        var binding = [String: String]()
        for key in ["headSHA", "runID", "terminalScreenshotSHA256"] {
            if let value = ci[key] as? String { binding[key] = value }
        }
        return binding
    }

    private func validCommonEnvelope(
        _ envelope: [String: Any], documents: PhaseDocuments
    ) -> Bool {
        guard let predecessors = envelope["predecessorCheckpointSHA256"] as? [String],
              let checkpoints = documents.stages["checkpoints"] as? [[String: Any]],
              predecessors.count == 4,
              predecessors.allSatisfy(isSHA256),
              checkpoints.prefix(4).map({ canonicalSHA256($0) }) == predecessors,
              let rows = envelope["requiredNonSelfDocuments"] as? [[String: Any]],
              let required = requiredNonSelfDocumentPaths(documents),
              rows.count == required.count,
              Set(rows.compactMap { $0["path"] as? String }) == Set(required),
              rows.allSatisfy({ row in
                  Set(row.keys) == Set(["role", "path", "sha256"])
                    && nonSelfDocumentRoles[row["path"] as? String ?? ""] == row["role"] as? String
                    && isSHA256(row["sha256"] as? String ?? "")
              }),
              let sealed = envelope["sealedDeferral"] as? [String: Any],
              sealed["policyID"] as? String == physicalDeferralPolicyID,
              !(sealed["evidenceID"] as? String ?? "").isEmpty,
              let sealedHash = sealed["sha256"] as? String,
              isSHA256(sealedHash),
              validSealedDeferral(in: documents.privacy, expectedSHA256: sealedHash),
              let later = envelope["laterOwnerGates"] as? [String: Any],
              later["largerDisplayScreenshotSet"] as? String == "MISSING",
              later["archive"] as? String == "NOT_RUN",
              later["releaseVersionBuildLiveInputs"] as? String == "PENDING",
              later["appPrivacy"] as? String == "PENDING",
              unsignedCICopiesMatch(documents)
        else { return false }
        return true
    }

    private func validPendingEnvelope(
        _ envelope: [String: Any], documents: PhaseDocuments
    ) -> Bool {
        guard let brand = documents.metadata["brandRefresh"] as? [String: Any],
              let f25 = envelope["f25"] as? [String: Any],
              let f25Status = f25["status"] as? String,
              ["NOT_RUN", "PASS"].contains(f25Status),
              brand["finalF25Status"] as? String == f25Status,
              let ci = documents.privacy["unsigned_preparation_ci"] as? [String: Any],
              let human = envelope["humanStoreReview"] as? [String: Any],
              let clearance = envelope["datedClearance"] as? [String: Any],
              clearance["scope"] as? String == "trademark_name_five_claims_and_urls",
              let slots = documents.screenshots["slots"] as? [[String: Any]],
              slots.count == 5, slots.allSatisfy(validStoreReviewTuple),
              let pending = brand["pendingGates"] as? [String],
              let screenshotPending = documents.screenshots["pending_gates"] as? [String],
              ["final_f25_evidence", "store_creative_review", "dated_trademark_name_claim_url_clearance"]
                .allSatisfy({ pending.contains($0) == screenshotPending.contains($0) }),
              pending.contains("final_f25_evidence") == (f25Status == "NOT_RUN")
        else { return false }
        if f25Status == "NOT_RUN" {
            guard envelope["candidateHead"] is NSNull, f25["evidenceID"] is NSNull
            else { return false }
        } else {
            guard isGitSHA(envelope["candidateHead"] as? String ?? ""),
                  envelope["candidateHead"] as? String == ci["headSHA"] as? String,
                  f25["evidenceID"] as? String == ci["evidenceID"] as? String,
                  ci["status"] as? String == "PASS",
                  ci["unitPassed"] as? Int == 5, ci["uiPassed"] as? Int == 1
            else { return false }
        }
        let storesApproved = reviewedFiveSlotsRemainFrozen(documents)
        if storesApproved {
            guard human["status"] as? String == "APPROVED",
                  let evidenceID = human["evidenceID"] as? String,
                  !evidenceID.isEmpty,
                  isDate(human["reviewedDate"] as? String),
                  !(human["reviewer"] as? String ?? "").isEmpty,
                  slots.allSatisfy({ $0["store_review_evidence_id"] as? String == evidenceID })
            else { return false }
        } else {
            guard human["status"] as? String == "PENDING",
                  human["evidenceID"] is NSNull, human["reviewedDate"] is NSNull,
                  human["reviewer"] is NSNull
            else { return false }
        }
        let legalComplete = hasDatedLegalEvidence(documents.screenshots)
        if legalComplete {
            guard let rights = documents.screenshots["rights_and_clearance"] as? [String: Any],
                  let dated = rights["dated_clearance_evidence"] as? [String: Any],
                  clearance["status"] as? String == "PASS",
                  clearance["evidenceID"] as? String == dated["evidence_id"] as? String,
                  clearance["date"] as? String == dated["date"] as? String
            else { return false }
        } else {
            guard clearance["status"] as? String == "PENDING",
                  clearance["evidenceID"] is NSNull, clearance["date"] is NSNull
            else { return false }
        }
        guard pending.contains("store_creative_review") == !storesApproved,
              pending.contains("dated_trademark_name_claim_url_clearance") == !legalComplete
        else { return false }
        return f25Status != "PASS" || !storesApproved || !legalComplete
            || ci["humanVisualReview"] as? String != "APPROVED"
    }

    // Structural repository content only. This deliberately does not authenticate
    // Git ancestry, hosted originals, reviewers, or the later receipt commit.
    private func validatePhaseContent(
        _ documents: PhaseDocuments,
        activation: [String: Any],
        assetManifest: [String: Any]
    ) -> PhaseEvidenceState? {
        let declaredStatus = phaseContentStatus(documents.metadata)
        guard let declaredState = PhaseEvidenceState(rawValue: declaredStatus),
              declaredState != .closed
        else { return nil }
        guard let brand = documents.metadata["brandRefresh"] as? [String: Any],
              let envelope = brand["phaseEvidence"] as? [String: Any],
              envelope["schemaVersion"] as? Int == 1,
              envelope["contractID"] as? String == "s10.6-post-release-physical-deferral-v1",
              envelope["sourceProductHead"] as? String == productHead,
              envelope["releaseReady"] as? Bool == false,
              envelope["releaseEvidenceHead"] == nil,
              envelope["receiptHead"] == nil,
              validCommonEnvelope(envelope, documents: documents)
        else { return nil }
        if declaredState == .pendingPreparation {
            return validatePendingPreparation(
                metadata: documents.metadata, smoke: documents.smoke,
                stages: documents.stages, store: documents.store, lock: documents.lock,
                screenshotManifest: documents.screenshots, privacyReview: documents.privacy
            ) && validPendingEnvelope(envelope, documents: documents) ? declaredState : nil
        }
        guard
              let candidateHead = envelope["candidateHead"] as? String,
              isGitSHA(candidateHead),
              let predecessorHashes = envelope["predecessorCheckpointSHA256"] as? [String],
              predecessorHashes.count == 4,
              predecessorHashes.allSatisfy(isSHA256),
              let rows = documents.stages["checkpoints"] as? [[String: Any]],
              rows.count == 4 || rows.count == 5,
              rows.prefix(4).compactMap({ $0["stage"] as? String }) == [
                "Inventory", "ComponentSystem", "Migration", "AutomatedLab",
              ],
              rows.prefix(4).map({ canonicalSHA256($0) }) == predecessorHashes,
              !rows.contains(where: { $0["stage"] as? String == "PhysicalExperience" }),
              validateRuntimeAssetReview(
                documents.privacy, activation: activation, manifest: assetManifest
              ),
              reviewedFiveSlotsRemainFrozen(documents),
              hasDatedLegalEvidence(documents.screenshots),
              let f25 = envelope["f25"] as? [String: Any],
              f25["status"] as? String == "PASS",
              !(f25["evidenceID"] as? String ?? "").isEmpty,
              let human = envelope["humanStoreReview"] as? [String: Any],
              human["status"] as? String == "APPROVED",
              !(human["reviewer"] as? String ?? "").isEmpty,
              !(human["evidenceID"] as? String ?? "").isEmpty,
              isDate(human["reviewedDate"] as? String),
              let clearance = envelope["datedClearance"] as? [String: Any],
              clearance["status"] as? String == "PASS",
              !(clearance["evidenceID"] as? String ?? "").isEmpty,
              isDate(clearance["date"] as? String),
              clearance["scope"] as? String == "trademark_name_five_claims_and_urls",
              let sealed = envelope["sealedDeferral"] as? [String: Any],
              sealed["policyID"] as? String == physicalDeferralPolicyID,
              !(sealed["evidenceID"] as? String ?? "").isEmpty,
              isSHA256(sealed["sha256"] as? String ?? ""),
              let later = envelope["laterOwnerGates"] as? [String: Any],
              later["largerDisplayScreenshotSet"] as? String == "MISSING",
              later["archive"] as? String == "NOT_RUN",
              later["releaseVersionBuildLiveInputs"] as? String == "PENDING",
              later["appPrivacy"] as? String == "PENDING",
              let documentRows = envelope["requiredNonSelfDocuments"]
                as? [[String: Any]],
              let requiredPaths = requiredNonSelfDocumentPaths(documents),
              documentRows.count == requiredPaths.count,
              Set(documentRows.compactMap { $0["path"] as? String }).count
                == requiredPaths.count,
              Set(documentRows.compactMap { $0["path"] as? String }) == Set(requiredPaths),
              documentRows.allSatisfy({ row in
                  nonSelfDocumentRoles[row["path"] as? String ?? ""]
                    == row["role"] as? String
                    && isSHA256(row["sha256"] as? String ?? "")
              })
        else { return nil }
        if rows.count == 4 { return .evidenceReady }
        guard let release = rows.last,
              release["stage"] as? String == "Release",
              release["gate_id"] as? String == "s10.6-release-phase-evidence",
              release["product_head"] as? String == candidateHead,
              isGitSHA(release["evidence_head"] as? String ?? ""),
              release["evidence_head_role"] as? String == "K",
              let receiptDocuments = release["documents"] as? [[String: Any]],
              let receiptPaths = releaseReceiptDocumentPaths(documents),
              receiptDocuments.count == receiptPaths.count,
              Set(receiptDocuments.compactMap { $0["path"] as? String }).count
                == receiptPaths.count,
              let receiptHashes = try? Dictionary(uniqueKeysWithValues: receiptDocuments.map { row in
                  guard let path = row["path"] as? String,
                        let sha = row["sha256"] as? String else {
                      throw NSError(domain: "S10.6", code: 1)
                  }
                  return (path, sha)
              }),
              let envelopeHashes = try? Dictionary(uniqueKeysWithValues: documentRows.map { row in
                  guard let path = row["path"] as? String,
                        let sha = row["sha256"] as? String else {
                      throw NSError(domain: "S10.6", code: 2)
                  }
                  return (path, sha)
              }),
              Set(receiptHashes.keys) == Set(receiptPaths),
              receiptDocuments.allSatisfy({ row in
                  row["blob_commit"] as? String == release["evidence_head"] as? String
                    && releaseDocumentTypes[row["path"] as? String ?? ""]
                      == row["document_type"] as? String
              }),
              envelopeHashes.allSatisfy { receiptHashes[$0.key] == $0.value },
              isSHA256(receiptHashes[phaseJSONPaths[0]] ?? ""),
              let evidenceIDs = release["evidence_ids"] as? [String],
              !evidenceIDs.isEmpty,
              Set(evidenceIDs).count == evidenceIDs.count
        else { return nil }
        return .closed
    }

    private func isDate(_ value: String?) -> Bool {
        guard let value,
              value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    private func evaluatePhaseEvidence(
        _ documents: PhaseDocuments,
        activation: [String: Any],
        assetManifest: [String: Any],
        checks: AuthenticatedChecks
    ) -> PhaseEvidenceState? {
        guard let structuralState = validatePhaseContent(
            documents, activation: activation, assetManifest: assetManifest
        ) else { return nil }
        if structuralState == .pendingPreparation { return .pendingPreparation }

        guard documents.metadata["releaseReady"] as? Bool == false,
              documents.screenshots["release_ready"] as? Bool == false,
              documents.privacy["release_ready"] as? Bool == false,
              validateRuntimeAssetReview(
                documents.privacy, activation: activation, manifest: assetManifest
              ),
              let brand = documents.metadata["brandRefresh"] as? [String: Any],
              brand["sourceProductHead"] as? String == productHead,
              brand["acceptedAutomatedEvidenceHead"] as? String == evidenceHead,
              brand["acceptedAutomatedReceiptHead"] as? String == receiptHead,
              documents.screenshots["source_product_head"] as? String == productHead,
              documents.screenshots["accepted_automated_evidence_head"] as? String == evidenceHead,
              documents.screenshots["accepted_automated_receipt_head"] as? String == receiptHead,
              documents.privacy["source_product_head"] as? String == productHead,
              documents.privacy["accepted_s10_4_evidence_head"] as? String == evidenceHead,
              documents.privacy["accepted_s10_4_receipt_head"] as? String == receiptHead,
              documents.store["document_status"] as? String == "planned",
              documents.lock["document_status"] as? String == "template",
              documents.screenshots["physical_verification_status"] as? String == "DEFERRED",
              let physical = documents.privacy["physical_verification"] as? [String: Any],
              physical["status"] as? String == "DEFERRED",
              physical["s10_5_receipt"] is NSNull,
              physical["blocks_release_ready"] as? Bool == false,
              physical["resume_policy"] as? String == physicalResumePolicy,
              physical["deferral_policy_id"] as? String == physicalDeferralPolicyID,
              validSealedDeferral(in: documents.privacy, expectedSHA256: checks.sealedDeferralSHA256),
              let checkpoints = documents.stages["checkpoints"] as? [[String: Any]],
              checkpoints.count == 4 || checkpoints.count == 5,
              checkpoints.prefix(4).compactMap({ $0["stage"] as? String }) == [
                "Inventory", "ComponentSystem", "Migration", "AutomatedLab",
              ],
              checkpoints.prefix(4).map({ canonicalSHA256($0) })
                == checks.predecessorCheckpointHashes,
              !checkpoints.contains(where: { $0["stage"] as? String == "PhysicalExperience" }),
              Set(checkpoints.compactMap { $0["stage"] as? String }).count == checkpoints.count
        else { return nil }

        guard phaseGatesAreReady(documents, checks: checks),
              checks.ancestryVerified,
              checks.originalsVerified,
              isGitSHA(checks.candidateHead),
              authenticatedDocumentHashesMatch(documents, checks: checks)
        else { return nil }

        if structuralState == .evidenceReady { return .evidenceReady }
        guard checks.receiptCommitVerified,
              isGitSHA(checks.releaseEvidenceHead),
              isGitSHA(checks.receiptHead),
              let release = checkpoints.last,
              release["stage"] as? String == "Release",
              release["gate_id"] as? String == "s10.6-release-phase-evidence",
              release["product_head"] as? String == checks.candidateHead,
              release["evidence_head"] as? String == checks.releaseEvidenceHead,
              release["evidence_head_role"] as? String == "K",
              let releaseDocuments = release["documents"] as? [[String: Any]],
              let requiredDocumentPaths = releaseReceiptDocumentPaths(documents),
              Set(releaseDocuments.compactMap { $0["path"] as? String })
                == Set(requiredDocumentPaths),
              releaseDocuments.allSatisfy({ row in
                  guard let path = row["path"] as? String,
                        let hash = row["sha256"] as? String
                  else { return false }
                  return checks.documentHashes[path] == hash
              }),
              let evidenceIDs = release["evidence_ids"] as? [String],
              let expectedEvidenceIDs = phaseEnvelopeEvidenceIDs(documents),
              evidenceIDs.count == expectedEvidenceIDs.count,
              Set(evidenceIDs) == Set(expectedEvidenceIDs)
        else { return nil }
        return .closed
    }

    private func phaseGatesAreReady(
        _ documents: PhaseDocuments,
        checks: AuthenticatedChecks
    ) -> Bool {
        guard let brand = documents.metadata["brandRefresh"] as? [String: Any],
              brand["preparationStatus"] as? String == "phase_evidence_ready",
              brand["finalF25Status"] as? String == "PASS",
              brand["releaseReady"] as? Bool == false,
              let candidate = (documents.smoke["finalRCSmoke"] as? [String: Any])?
                ["brandedCandidate"] as? [String: Any],
              candidate["evidenceStatus"] as? String == "PASS",
              candidate["sourceProductHead"] as? String == productHead,
              let privacyCI = documents.privacy["unsigned_preparation_ci"] as? [String: Any],
              privacyCI["status"] as? String == "PASS",
              privacyCI["headSHA"] as? String == checks.candidateHead,
              privacyCI["sourceProductHead"] as? String == productHead,
              privacyCI["unitPassed"] as? Int == 5,
              privacyCI["uiPassed"] as? Int == 1,
              privacyCI["humanVisualReview"] as? String == "APPROVED",
              let humanID = privacyCI["humanVisualReviewEvidenceID"] as? String,
              checks.verifiedHumanEvidenceIDs.contains(humanID),
              terminalReviewBinding(privacyCI).count == 3,
              ciBinding(privacyCI).count == 6,
              checks.verifiedTerminalReviews[humanID] == terminalReviewBinding(privacyCI),
              checks.verifiedCIBinding == ciBinding(privacyCI),
              unsignedCICopiesMatch(documents),
              hasIndependentDatedLegalEvidence(documents.screenshots, checks: checks),
              reviewedFiveSlotsRemainFrozen(documents),
              externallyVerifiedFiveSlots(documents, checks: checks),
              phaseEnvelopeMatchesAuthenticatedGates(documents, checks: checks),
              reviewedFiveClaimsMatchClearance(documents),
              let privacyGaps = documents.privacy["store_readiness_gaps"] as? [[String: Any]],
              !privacyGaps.contains(where: { $0["gate"] as? String == "dated_trademark_name_claim_and_url_clearance" }),
              let apple = documents.screenshots["apple_specification_review"] as? [String: Any],
              apple["required_larger_display_set_status"] as? String == "MISSING",
              apple["store_upload_status"] as? String == "NOT_RUN",
              apple["resized_or_generated_screenshots"] as? Bool == false,
              let pending = brand["pendingGates"] as? [String],
              Set(pending).isSubset(of: Set([
                "required_6_5_or_6_9_screenshot_set",
                "owner_release_version_build_and_live_inputs",
                "archive_privacy_supply_chain_review",
                "required_checkpoint_receipts",
              ])),
              pending.contains("required_6_5_or_6_9_screenshot_set"),
              pending.contains("owner_release_version_build_and_live_inputs"),
              pending.contains("archive_privacy_supply_chain_review")
        else { return false }
        return true
    }

    private func reviewedFiveSlotsRemainFrozen(_ documents: PhaseDocuments) -> Bool {
        guard let plan = documents.store["plan"] as? [String: Any],
              let frozen = plan["screenshot_slots"] as? [[String: Any]],
              let slots = documents.screenshots["slots"] as? [[String: Any]],
              let mirrors = documents.store["screenshots"] as? [[String: Any]],
              frozen.count == 5,
              slots.count == 5,
              mirrors.count == 5,
              slots.map({ $0["slot_id"] as? String }) == frozen.map({ $0["slot_id"] as? String })
        else { return false }
        for (index, pair) in zip(slots, frozen).enumerated() {
            let (slot, expected) = pair
            let mirror = mirrors[index]
            guard slot["source_product_head"] as? String == productHead,
                  slot["store_review_status"] as? String == "APPROVED",
                  slot["store_approved"] as? Bool == true,
                  let reviewer = slot["store_reviewer"] as? String,
                  !reviewer.isEmpty,
                  let evidenceID = slot["store_review_evidence_id"] as? String,
                  !evidenceID.isEmpty,
                  isDate(slot["store_review_date"] as? String),
                  isSHA256(slot["sha256"] as? String ?? ""),
                  mirror["slot_id"] as? String == slot["slot_id"] as? String,
                  mirror["sha256"] as? String == slot["sha256"] as? String,
                  mirror["source_product_head"] as? String == productHead,
                  mirror["status"] as? String == "PASS",
                  mirror["reviewer"] as? String == reviewer,
                  (mirror["evidence_ids"] as? [String])?.contains(evidenceID) == true
            else { return false }
            for key in [
                "gate_id", "device_class", "device_profile_id", "locale_profile_id",
                "orientation", "pixel_width", "pixel_height", "slot_id", "slot_order",
                "story_role",
            ] {
                if String(describing: slot[key]) != String(describing: expected[key])
                    || String(describing: mirror[key]) != String(describing: expected[key]) {
                    return false
                }
            }
        }
        return true
    }

    private func validStoreReviewTuple(_ slot: [String: Any]) -> Bool {
        guard isSHA256(slot["sha256"] as? String ?? "") else { return false }
        switch slot["store_review_status"] as? String {
        case "NOT_RUN":
            return slot["store_approved"] as? Bool == false
                && slot["store_reviewer"] is NSNull
                && slot["store_review_evidence_id"] is NSNull
                && (slot["store_review_date"] == nil || slot["store_review_date"] is NSNull)
        case "APPROVED":
            return slot["store_approved"] as? Bool == true
                && !(slot["store_reviewer"] as? String ?? "").isEmpty
                && !(slot["store_review_evidence_id"] as? String ?? "").isEmpty
                && isDate(slot["store_review_date"] as? String)
        default:
            return false
        }
    }

    private func reviewedFiveClaimsMatchClearance(_ documents: PhaseDocuments) -> Bool {
        guard let plan = documents.store["plan"] as? [String: Any],
              let planned = plan["planned_claims"] as? [[String: Any]],
              let claims = documents.store["claims"] as? [[String: Any]],
              let rights = documents.screenshots["rights_and_clearance"] as? [String: Any],
              let dated = rights["dated_clearance_evidence"] as? [String: Any],
              let evidenceID = dated["evidence_id"] as? String,
              claims.count == 5, planned.count == 5
        else { return false }
        for (claim, expected) in zip(claims, planned) {
            guard claim["claim_id"] as? String == expected["claim_id"] as? String,
                  claim["text"] as? String == expected["text"] as? String,
                  claim["screen_state_ids"] as? [String] == expected["screen_state_ids"] as? [String],
                  claim["status"] as? String == "PASS",
                  !(claim["reviewer"] as? String ?? "").isEmpty,
                  (claim["evidence_ids"] as? [String])?.contains(evidenceID) == true
            else { return false }
        }
        return true
    }

    private func externallyVerifiedFiveSlots(
        _ documents: PhaseDocuments,
        checks: AuthenticatedChecks
    ) -> Bool {
        guard let brand = documents.metadata["brandRefresh"] as? [String: Any],
              let envelope = brand["phaseEvidence"] as? [String: Any],
              let human = envelope["humanStoreReview"] as? [String: Any],
              let envelopeEvidenceID = human["evidenceID"] as? String,
              let slots = documents.screenshots["slots"] as? [[String: Any]] else {
            return false
        }
        return slots.count == 5 && slots.allSatisfy { slot in
            guard let evidenceID = slot["store_review_evidence_id"] as? String,
                  let slotID = slot["slot_id"] as? String,
                  let hash = slot["sha256"] as? String,
                  evidenceID == envelopeEvidenceID,
                  checks.verifiedHumanEvidenceIDs.contains(evidenceID),
                  checks.verifiedHumanSlotSHA256[evidenceID]?[slotID] == hash
            else { return false }
            return true
        }
    }

    private func phaseEnvelopeMatchesAuthenticatedGates(
        _ documents: PhaseDocuments,
        checks: AuthenticatedChecks
    ) -> Bool {
        guard let brand = documents.metadata["brandRefresh"] as? [String: Any],
              let envelope = brand["phaseEvidence"] as? [String: Any],
              envelope["candidateHead"] as? String == checks.candidateHead,
              let f25 = envelope["f25"] as? [String: Any],
              let f25ID = f25["evidenceID"] as? String,
              let human = envelope["humanStoreReview"] as? [String: Any],
              let humanID = human["evidenceID"] as? String,
              let clearance = envelope["datedClearance"] as? [String: Any],
              let clearanceID = clearance["evidenceID"] as? String,
              let sealed = envelope["sealedDeferral"] as? [String: Any],
              let sealedID = sealed["evidenceID"] as? String,
              sealed["sha256"] as? String == checks.sealedDeferralSHA256,
              checks.verifiedHumanEvidenceIDs.contains(humanID),
              checks.verifiedLegalEvidenceIDs.contains(clearanceID),
              !f25ID.isEmpty, !sealedID.isEmpty
        else { return false }
        let ci = documents.privacy["unsigned_preparation_ci"] as? [String: Any]
        return ci?["evidenceID"] as? String == f25ID
            && phaseEnvelopeEvidenceIDs(documents) == [f25ID, humanID, clearanceID, sealedID]
    }

    private func phaseEnvelopeEvidenceIDs(_ documents: PhaseDocuments) -> [String]? {
        guard let brand = documents.metadata["brandRefresh"] as? [String: Any],
              let envelope = brand["phaseEvidence"] as? [String: Any],
              let f25 = envelope["f25"] as? [String: Any],
              let f25ID = f25["evidenceID"] as? String,
              let human = envelope["humanStoreReview"] as? [String: Any],
              let humanID = human["evidenceID"] as? String,
              let clearance = envelope["datedClearance"] as? [String: Any],
              let clearanceID = clearance["evidenceID"] as? String,
              let sealed = envelope["sealedDeferral"] as? [String: Any],
              let sealedID = sealed["evidenceID"] as? String,
              [f25ID, humanID, clearanceID, sealedID].allSatisfy({ !$0.isEmpty })
        else { return nil }
        return [f25ID, humanID, clearanceID, sealedID]
    }

    private func hasIndependentDatedLegalEvidence(
        _ screenshots: [String: Any],
        checks: AuthenticatedChecks
    ) -> Bool {
        guard hasDatedLegalEvidence(screenshots),
              let clearance = screenshots["rights_and_clearance"] as? [String: Any],
              let owner = clearance["owner_name_attestation"] as? [String: Any],
              let ownerID = owner["evidence_id"] as? String,
              let trademarkID = clearance["trademark_evidence_id"] as? String,
              let dated = clearance["dated_clearance_evidence"] as? [String: Any],
              let datedID = dated["evidence_id"] as? String,
              let date = dated["date"] as? String,
              date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              dated["scope"] as? String == "trademark_name_five_claims_and_urls",
              trademarkID != ownerID,
              datedID != ownerID,
              checks.verifiedLegalEvidenceIDs.contains(trademarkID),
              checks.verifiedLegalEvidenceIDs.contains(datedID)
        else { return false }
        return true
    }

    private func validSealedDeferral(
        in privacy: [String: Any],
        expectedSHA256: String
    ) -> Bool {
        guard let deferral = privacy["physical_deferral_owner_request"] as? [String: Any],
              deferral["policy_id"] as? String == physicalDeferralPolicyID,
              deferral["status"] as? String == "DEFERRED",
              deferral["blocking"] as? Bool == false,
              deferral["resume_policy"] as? String == physicalResumePolicy,
              let original = deferral["sealed_original_utf8"] as? String,
              let recorded = deferral["original_sha256"] as? String,
              Data(original.utf8).sha256 == recorded,
              recorded == expectedSHA256,
              let payload = try? JSONSerialization.jsonObject(with: Data(original.utf8))
                as? [String: Any],
              payload["physicalResult"] as? String == "DEFERRED",
              payload["physicalPassClaimed"] as? Bool == false,
              payload["automaticResumptionAuthorized"] as? Bool == false,
              payload["otherReleaseGatesWaived"] as? Bool == false,
              payload["signingUploadSubmissionAuthorized"] as? Bool == false
        else { return false }
        return true
    }

    private func unsignedCICopiesMatch(_ documents: PhaseDocuments) -> Bool {
        guard let metadataCI = (documents.metadata["brandRefresh"] as? [String: Any])?
                ["unsignedPreparationCI"] as? [String: Any],
              let smokeCI = ((documents.smoke["finalRCSmoke"] as? [String: Any])?
                ["brandedCandidate"] as? [String: Any])?["unsignedPreparationCI"]
                as? [String: Any],
              let privacyCI = documents.privacy["unsigned_preparation_ci"] as? [String: Any]
        else { return false }
        return canonicalSHA256(metadataCI) == canonicalSHA256(smokeCI)
            && canonicalSHA256(smokeCI) == canonicalSHA256(privacyCI)
    }

    private func authenticatedDocumentHashesMatch(
        _ documents: PhaseDocuments,
        checks: AuthenticatedChecks
    ) -> Bool {
        guard let required = releaseReceiptDocumentPaths(documents),
              let brand = documents.metadata["brandRefresh"] as? [String: Any],
              let envelope = brand["phaseEvidence"] as? [String: Any],
              let rows = envelope["requiredNonSelfDocuments"] as? [[String: Any]],
              let nonSelf = requiredNonSelfDocumentPaths(documents),
              rows.count == nonSelf.count,
              Set(rows.compactMap { $0["path"] as? String }).count == nonSelf.count
        else { return false }
        return Set(checks.documentHashes.keys) == Set(required)
            && checks.documentHashes.values.allSatisfy(isSHA256)
            && rows.allSatisfy { row in
                guard let path = row["path"] as? String,
                      let hash = row["sha256"] as? String
                else { return false }
                return checks.documentHashes[path] == hash
            }
    }

    private func phaseDocumentsByPath(
        _ documents: PhaseDocuments
    ) -> [String: [String: Any]] {
        [
            phaseJSONPaths[0]: documents.metadata,
            phaseJSONPaths[1]: documents.smoke,
            phaseJSONPaths[4]: documents.store,
            phaseJSONPaths[5]: documents.lock,
            phaseJSONPaths[6]: documents.screenshots,
            phaseJSONPaths[7]: documents.privacy,
        ]
    }

    // The current card names seven JSON inputs. The checkpoint document is the
    // eventual receipt container, so it cannot truthfully embed its own content hash.
    // The other required paths are derived from metadata.evidencePaths plus the two
    // release JSON roots rather than from the six-document preparation lock template.
    private func requiredNonSelfDocumentPaths(
        _ documents: PhaseDocuments
    ) -> [String]? {
        guard let brand = documents.metadata["brandRefresh"] as? [String: Any],
              let evidencePaths = brand["evidencePaths"] as? [String: Any],
              evidencePaths["stageCheckpoints"] as? String == phaseJSONPaths[3],
              evidencePaths["storeReadiness"] as? String == phaseJSONPaths[4],
              evidencePaths["evidenceLock"] as? String == phaseJSONPaths[5],
              evidencePaths["storeManifest"] as? String == phaseJSONPaths[6],
              evidencePaths["privacyReview"] as? String == phaseJSONPaths[7]
        else { return nil }
        return [phaseJSONPaths[1], phaseJSONPaths[2], phaseJSONPaths[4],
                phaseJSONPaths[5], phaseJSONPaths[6], phaseJSONPaths[7]]
    }

    private func releaseReceiptDocumentPaths(_ documents: PhaseDocuments) -> [String]? {
        guard requiredNonSelfDocumentPaths(documents) != nil else { return nil }
        return [phaseJSONPaths[0], phaseJSONPaths[1], phaseJSONPaths[2], phaseJSONPaths[4],
                phaseJSONPaths[5], phaseJSONPaths[6], phaseJSONPaths[7]]
    }

    // Synthetic fixtures only; actual checkout tests never fabricate external proof.
    private func fixtureChecks(
        for documents: PhaseDocuments,
        fixtureReady: Bool = false
    ) throws -> AuthenticatedChecks {
        let checkpoints = try rows(documents.stages, "checkpoints")
        let deferral = try object(documents.privacy, "physical_deferral_owner_request")
        let ci = try object(documents.privacy, "unsigned_preparation_ci")
        let values = phaseDocumentsByPath(documents)
        var hashes = Dictionary(uniqueKeysWithValues: values.map {
            ($0.key, canonicalSHA256($0.value))
        })
        hashes[phaseJSONPaths[2]] = try data(phaseJSONPaths[2]).sha256
        var slotBindings: [String: [String: String]] = [:]
        if fixtureReady {
            for slot in try rows(documents.screenshots, "slots") {
                let evidenceID = try string(slot, "store_review_evidence_id")
                let slotID = try string(slot, "slot_id")
                let hash = try string(slot, "sha256")
                slotBindings[evidenceID, default: [:]][slotID] = hash
            }
        }
        return AuthenticatedChecks(
            candidateHead: try string(ci, "headSHA"),
            releaseEvidenceHead: String(repeating: "2", count: 40),
            receiptHead: String(repeating: "3", count: 40),
            ancestryVerified: true,
            originalsVerified: true,
            receiptCommitVerified: true,
            predecessorCheckpointHashes: checkpoints.prefix(4).map { canonicalSHA256($0) },
            documentHashes: hashes,
            verifiedHumanEvidenceIDs: fixtureReady ? ["fixture-human-store-review"] : [],
            verifiedHumanSlotSHA256: slotBindings,
            verifiedLegalEvidenceIDs: fixtureReady ? [
                "fixture-independent-trademark-clearance",
                "fixture-independent-dated-clearance",
            ] : [],
            sealedDeferralSHA256: try string(deferral, "original_sha256"),
            verifiedCIBinding: ciBinding(ci),
            verifiedTerminalReviews: fixtureReady ? ["fixture-human-store-review": terminalReviewBinding(ci)] : [:]
        )
    }

    private func makePendingFixture(from source: PhaseDocuments) throws -> PhaseDocuments {
        var result = PhaseDocuments(
            metadata: deepCopy(source.metadata), smoke: deepCopy(source.smoke),
            stages: deepCopy(source.stages), store: deepCopy(source.store),
            lock: deepCopy(source.lock), screenshots: deepCopy(source.screenshots),
            privacy: deepCopy(source.privacy)
        )
        result.stages["checkpoints"] = Array(try rows(source.stages, "checkpoints").prefix(4))
        let pending = ["final_f25_evidence", "store_creative_review",
                       "dated_trademark_name_claim_url_clearance"]
            + laterOwnerPendingGates(includeReceipt: true)
        var brand = try object(result.metadata, "brandRefresh")
        brand["preparationStatus"] = "prepared_pending_verification"
        brand["finalF25Status"] = "NOT_RUN"
        brand["pendingGates"] = pending
        brand["releaseReady"] = false
        result.metadata["brandRefresh"] = brand
        result.metadata["releaseReady"] = false
        var finalSmoke = try object(result.smoke, "finalRCSmoke")
        var candidate = try object(finalSmoke, "brandedCandidate")
        candidate["evidenceStatus"] = "NOT_RUN"
        finalSmoke["brandedCandidate"] = candidate
        result.smoke["finalRCSmoke"] = finalSmoke
        result.screenshots["pending_gates"] = pending
        var slots = try rows(result.screenshots, "slots")
        for index in slots.indices {
            slots[index]["store_review_status"] = "NOT_RUN"
            slots[index]["store_approved"] = false
            slots[index]["store_reviewer"] = NSNull()
            slots[index]["store_review_evidence_id"] = NSNull()
            slots[index]["store_review_date"] = NSNull()
        }
        result.screenshots["slots"] = slots
        var mirrors = try rows(result.store, "screenshots")
        for index in mirrors.indices {
            mirrors[index]["status"] = "NOT_RUN"
            mirrors[index]["reviewer"] = ""
            mirrors[index]["evidence_ids"] = [String]()
        }
        result.store["screenshots"] = mirrors
        var clearance = try object(result.screenshots, "rights_and_clearance")
        clearance["trademark_clearance_status"] = "NOT_CLEARED"
        clearance["trademark_evidence_id"] = NSNull()
        for key in ["name_clearance_status", "claim_clearance_status", "url_clearance_status"] {
            clearance[key] = "PENDING"
        }
        clearance["dated_clearance_evidence"] = NSNull()
        result.screenshots["rights_and_clearance"] = clearance
        brand["phaseEvidence"] = [
            "schemaVersion": 1,
            "contractID": "s10.6-post-release-physical-deferral-v1",
            "contentStatus": "PENDING", "sourceProductHead": productHead,
            "candidateHead": NSNull(),
            "predecessorCheckpointSHA256": try rows(result.stages, "checkpoints").map { canonicalSHA256($0) },
            "requiredNonSelfDocuments": try fixtureNonSelfBindings(result),
            "f25": ["status": "NOT_RUN", "evidenceID": NSNull()],
            "humanStoreReview": ["status": "PENDING", "reviewer": NSNull(),
                                 "evidenceID": NSNull(), "reviewedDate": NSNull()],
            "datedClearance": ["status": "PENDING", "evidenceID": NSNull(),
                               "date": NSNull(), "scope": "trademark_name_five_claims_and_urls"],
            "sealedDeferral": [
                "policyID": physicalDeferralPolicyID, "evidenceID": "fixture-sealed-physical-deferral",
                "sha256": try string(try object(result.privacy, "physical_deferral_owner_request"), "original_sha256"),
            ],
            "laterOwnerGates": ["largerDisplayScreenshotSet": "MISSING", "archive": "NOT_RUN",
                                "releaseVersionBuildLiveInputs": "PENDING", "appPrivacy": "PENDING"],
            "releaseReady": false,
        ]
        result.metadata["brandRefresh"] = brand
        return result
    }

    // The encoded fixture bytes are synthetic. Actual file/Git bindings use data(path).
    private func fixtureNonSelfBindings(_ documents: PhaseDocuments) throws -> [[String: Any]] {
        let paths = try XCTUnwrap(requiredNonSelfDocumentPaths(documents))
        let values = phaseDocumentsByPath(documents)
        return try paths.map { path in
            let hash = path == phaseJSONPaths[2]
                ? try data(path).sha256
                : canonicalSHA256(try XCTUnwrap(values[path]))
            return ["role": try XCTUnwrap(nonSelfDocumentRoles[path]), "path": path, "sha256": hash]
        }
    }

    private func makeEvidenceReadyFixture(
        from source: PhaseDocuments
    ) throws -> PhaseDocuments {
        var result = PhaseDocuments(
            metadata: deepCopy(source.metadata), smoke: deepCopy(source.smoke),
            stages: deepCopy(source.stages), store: deepCopy(source.store),
            lock: deepCopy(source.lock), screenshots: deepCopy(source.screenshots),
            privacy: deepCopy(source.privacy)
        )
        result.stages["checkpoints"] = Array(try rows(source.stages, "checkpoints").prefix(4))
        let candidateHead = String(repeating: "1", count: 40)

        var ci = try object(result.privacy, "unsigned_preparation_ci")
        ci["headSHA"] = candidateHead
        ci["evidenceID"] = "fixture-f25-originals"
        ci["runID"] = "fixture-run"
        ci["artifactID"] = "fixture-artifact"
        ci["terminalScreenshotSHA256"] = String(repeating: "D", count: 64)
        ci["humanVisualReview"] = "APPROVED"
        ci["humanVisualReviewEvidenceID"] = "fixture-human-store-review"
        result.privacy["unsigned_preparation_ci"] = ci

        var brand = try object(result.metadata, "brandRefresh")
        brand["preparationStatus"] = "phase_evidence_ready"
        brand["finalF25Status"] = "PASS"
        brand["pendingGates"] = laterOwnerPendingGates(includeReceipt: true)
        brand["unsignedPreparationCI"] = ci
        result.metadata["brandRefresh"] = brand

        var finalSmoke = try object(result.smoke, "finalRCSmoke")
        var candidate = try object(finalSmoke, "brandedCandidate")
        candidate["evidenceStatus"] = "PASS"
        candidate["unsignedPreparationCI"] = ci
        finalSmoke["brandedCandidate"] = candidate
        result.smoke["finalRCSmoke"] = finalSmoke

        var slots = try rows(result.screenshots, "slots")
        for index in slots.indices {
            slots[index]["store_review_status"] = "APPROVED"
            slots[index]["store_approved"] = true
            slots[index]["store_reviewer"] = "fixture-human-reviewer"
            slots[index]["store_review_evidence_id"] = "fixture-human-store-review"
            slots[index]["store_review_date"] = "2026-09-10"
        }
        result.screenshots["slots"] = slots
        result.screenshots["pending_gates"] = laterOwnerPendingGates(includeReceipt: true)
        var mirrors = try rows(result.store, "screenshots")
        for index in mirrors.indices {
            mirrors[index]["status"] = "PASS"
            mirrors[index]["reviewer"] = "fixture-human-reviewer"
            mirrors[index]["evidence_ids"] = ["fixture-human-store-review"]
        }
        result.store["screenshots"] = mirrors

        var clearance = try object(result.screenshots, "rights_and_clearance")
        clearance["trademark_clearance_status"] = "CLEARED"
        clearance["trademark_evidence_id"] = "fixture-independent-trademark-clearance"
        clearance["name_clearance_status"] = "PASS"
        clearance["claim_clearance_status"] = "PASS"
        clearance["url_clearance_status"] = "PASS"
        clearance["dated_clearance_evidence"] = [
            "evidence_id": "fixture-independent-dated-clearance",
            "date": "2026-09-10",
            "scope": "trademark_name_five_claims_and_urls",
        ]
        result.screenshots["rights_and_clearance"] = clearance

        var claims = try rows(result.store, "claims")
        for index in claims.indices {
            claims[index]["status"] = "PASS"
            claims[index]["reviewer"] = "fixture-clearance-reviewer"
            claims[index]["evidence_ids"] = ["fixture-independent-dated-clearance"]
        }
        result.store["claims"] = claims
        result.privacy["store_readiness_gaps"] = try rows(result.privacy, "store_readiness_gaps")
            .filter { $0["gate"] as? String != "dated_trademark_name_claim_and_url_clearance" }

        let nonSelfRows = try fixtureNonSelfBindings(result)
        let predecessor = try rows(result.stages, "checkpoints").prefix(4)
            .map { canonicalSHA256($0) }
        var finalBrand = try object(result.metadata, "brandRefresh")
        finalBrand["phaseEvidence"] = [
            "schemaVersion": 1,
            "contractID": "s10.6-post-release-physical-deferral-v1",
            "contentStatus": "EVIDENCE_READY",
            "sourceProductHead": productHead,
            "candidateHead": candidateHead,
            "predecessorCheckpointSHA256": predecessor,
            "requiredNonSelfDocuments": nonSelfRows,
            "f25": ["status": "PASS", "evidenceID": "fixture-f25-originals"],
            "humanStoreReview": [
                "status": "APPROVED", "reviewer": "fixture-human-reviewer",
                "evidenceID": "fixture-human-store-review", "reviewedDate": "2026-09-10",
            ],
            "datedClearance": [
                "status": "PASS", "evidenceID": "fixture-independent-dated-clearance",
                "date": "2026-09-10", "scope": "trademark_name_five_claims_and_urls",
            ],
            "sealedDeferral": [
                "policyID": physicalDeferralPolicyID,
                "evidenceID": "fixture-sealed-physical-deferral",
                "sha256": try string(
                    try object(result.privacy, "physical_deferral_owner_request"),
                    "original_sha256"
                ),
            ],
            "laterOwnerGates": [
                "largerDisplayScreenshotSet": "MISSING", "archive": "NOT_RUN",
                "releaseVersionBuildLiveInputs": "PENDING", "appPrivacy": "PENDING",
            ],
            "releaseReady": false,
        ]
        result.metadata["brandRefresh"] = finalBrand
        return result
    }

    private func addingSyntheticReleaseCheckpoint(
        to documents: PhaseDocuments,
        checks: AuthenticatedChecks
    ) throws -> [String: Any] {
        var result = deepCopy(documents.stages)
        var checkpoints = try rows(result, "checkpoints")
        let candidateHead = try string(
            try object(
                try object(documents.metadata, "brandRefresh"), "phaseEvidence"
            ),
            "candidateHead"
        )
        checkpoints.append([
            "stage": "Release",
            "gate_id": "s10.6-release-phase-evidence",
            "product_head": candidateHead,
            "evidence_head": checks.releaseEvidenceHead,
            "evidence_head_role": "K",
            "documents": try XCTUnwrap(releaseReceiptDocumentPaths(documents)).map { path in
                [
                    "document_type": releaseDocumentTypes[path]!,
                    "path": path,
                    "blob_commit": checks.releaseEvidenceHead,
                    "sha256": checks.documentHashes[path]!,
                ]
            },
            "evidence_ids": [
                "fixture-f25-originals",
                "fixture-human-store-review",
                "fixture-independent-dated-clearance",
                "fixture-sealed-physical-deferral",
            ],
        ])
        result["checkpoints"] = checkpoints
        return result
    }

    private func laterOwnerPendingGates(includeReceipt: Bool) -> [String] {
        var gates = [
            "required_6_5_or_6_9_screenshot_set",
            "owner_release_version_build_and_live_inputs",
            "archive_privacy_supply_chain_review",
        ]
        if includeReceipt { gates.append("required_checkpoint_receipts") }
        return gates
    }

    private func replacingDocumentHashes(
        in source: AuthenticatedChecks, with hashes: [String: String]
    ) -> AuthenticatedChecks {
        var result = source
        result.documentHashes = hashes
        return result
    }

    private func replacingDeferralHash(
        in source: AuthenticatedChecks, with hash: String
    ) -> AuthenticatedChecks {
        var result = source
        result.sealedDeferralSHA256 = hash
        return result
    }

    private func replacingVerificationFlags(
        in source: AuthenticatedChecks, ancestry: Bool? = nil,
        originals: Bool? = nil, receiptCommit: Bool? = nil
    ) -> AuthenticatedChecks {
        var result = source
        result.ancestryVerified = ancestry ?? source.ancestryVerified
        result.originalsVerified = originals ?? source.originalsVerified
        result.receiptCommitVerified = receiptCommit ?? source.receiptCommitVerified
        return result
    }

    private func canonicalSHA256(_ value: [String: Any]) -> String {
        let bytes = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        return bytes.sha256
    }

    private func isGitSHA(_ value: String) -> Bool {
        value.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil
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
              brand["physicalVerificationBlocking"] as? Bool == false,
              (brand["deferredFollowUps"] as? [String]) == ["physical_s10_5"],
              brand["physicalResumePolicy"] as? String == physicalResumePolicy,
              brand["physicalDeferralPolicyID"] as? String == physicalDeferralPolicyID,
              brand["storeStatus"] as? String == "planned",
              brand["evidenceLockStatus"] as? String == "template",
              ["NOT_RUN", "PASS"].contains(brand["finalF25Status"] as? String ?? ""),
              brand["releaseReady"] as? Bool == false,
              let pendingGates = brand["pendingGates"] as? [String],
              !pendingGates.isEmpty,
              !pendingGates.contains("physical_s10_5"),
              pendingGates.contains("required_checkpoint_receipts"),
              !pendingGates.contains("all_six_checkpoint_receipts"),
              brand["evidencePaths"] as? [String: Any] != nil,
              let finalSmoke = smoke["finalRCSmoke"] as? [String: Any],
              let candidate = finalSmoke["brandedCandidate"] as? [String: Any],
              candidate["card"] as? String == "S10.6",
              candidate["selector"] as? String == "FieldEvidenceAppUITests/S10_6BrandReleaseUITests",
              candidate["sourceProductHead"] as? String == productHead,
              candidate["evidenceStatus"] as? String == brand["finalF25Status"] as? String,
              candidate["physicalVerificationStatus"] as? String == "DEFERRED",
              candidate["physicalVerificationBlocking"] as? Bool == false,
              candidate["physicalResumePolicy"] as? String == physicalResumePolicy,
              candidate["physicalDeferralPolicyID"] as? String == physicalDeferralPolicyID,
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
              screenshotManifest["physical_verification_blocking"] as? Bool == false,
              (screenshotManifest["deferred_follow_ups"] as? [String]) == ["physical_s10_5"],
              screenshotManifest["physical_resume_policy"] as? String == physicalResumePolicy,
              privacyReview["release_ready"] as? Bool == false,
              let physical = privacyReview["physical_verification"] as? [String: Any],
              physical["status"] as? String == "DEFERRED",
              physical["s10_5_receipt"] is NSNull,
              physical["blocks_release_ready"] as? Bool == false,
              physical["resume_policy"] as? String == physicalResumePolicy,
              physical["deferral_policy_id"] as? String == physicalDeferralPolicyID,
              let deferred = privacyReview["deferred_follow_ups"] as? [[String: Any]],
              deferred.count == 1,
              deferred[0]["gate"] as? String == "physical_s10_5_evidence",
              deferred[0]["status"] as? String == "DEFERRED",
              deferred[0]["blocking"] as? Bool == false,
              deferred[0]["resume_policy"] as? String == physicalResumePolicy,
              deferred[0]["policy_id"] as? String == physicalDeferralPolicyID,
              let gaps = privacyReview["store_readiness_gaps"] as? [[String: Any]],
              !gaps.contains(where: { $0["gate"] as? String == "physical_s10_5_evidence" })
        else { return false }
        return true
    }

    // Necessary legal evidence only. Full release readiness remains outside this test helper.
    private func hasDatedLegalEvidence(_ screenshotManifest: [String: Any]) -> Bool {
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
              isDate(datedEvidence["date"] as? String),
              datedEvidence["scope"] as? String == "trademark_name_five_claims_and_urls"
        else { return false }
        return true
    }

    // Validates a claimed physical result; DEFERRED is allowed to remain nonblocking elsewhere.
    private func hasSupportedPhysicalEvidence(_ privacyReview: [String: Any]) -> Bool {
        guard let physical = privacyReview["physical_verification"] as? [String: Any],
              physical["status"] as? String == "PASS",
              let receipt = physical["s10_5_receipt"] as? [String: Any],
              let receiptEvidenceID = receipt["evidence_id"] as? String,
              !receiptEvidenceID.isEmpty
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
