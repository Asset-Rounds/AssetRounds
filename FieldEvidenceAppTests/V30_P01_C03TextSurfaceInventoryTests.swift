import CryptoKit
import Foundation
import XCTest

final class V30_P01_C03TextSurfaceInventoryTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    private let folder = "docs/design/v30/inventory/"

    private func artifact(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent(folder + name + ".json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func inventory() throws -> [String: Any] {
        try artifact("V30TextBearingSurfaceInventoryV1")
    }

    private func files(_ value: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(value["files"] as? [[String: Any]])
    }

    private func items(_ path: String, in value: [String: Any]) throws -> [[String: Any]] {
        let source = try XCTUnwrap(try files(value).first { $0["path"] as? String == path })
        return try XCTUnwrap(source["items"] as? [[String: Any]])
    }

    func testAcceptanceRequiresResolvedOwnershipAndPreservesProvisionalBoundary() throws {
        let value = try inventory()
        let schema = try artifact("V30TextSurfaceDispositionSchemaV1")
        XCTAssertEqual(value["cardID"] as? String, "V30-P01-C03")
        XCTAssertEqual(value["sourceHead"] as? String, "2fbc17c98c1d4ee0e81d577f395e86240a2873f5")
        XCTAssertEqual(value["sourceTree"] as? String, "2b8bb37b64b7cc6426794a3ec7149c382cc5f29f")
        XCTAssertEqual(value["dispositionSchemaPayloadDigest"] as? String, schema["payloadDigest"] as? String)
        XCTAssertEqual(value["status"] as? String, "DRAFT_REQUIRES_SEMANTIC_REVIEW")
        XCTAssertEqual(value["unresolvedOwnershipCount"] as? Int, 2511)
        XCTAssertEqual(value["finalCredit"] as? Bool, false)
        // This artifact records Windows-static evidence; executing these tests
        // later does not retroactively grant the artifact native acceptance.
        XCTAssertEqual(value["nativeEvidence"] as? String, "NOT_EXECUTED_NO_NATIVE_CREDIT")
        XCTAssertEqual(try files(value).count, 2348)
    }

    func testEverySourceOccurrenceHasUniqueIdentityAndCompatibleDisposition() throws {
        let value = try inventory()
        let schema = try artifact("V30TextSurfaceDispositionSchemaV1")
        let allowed = try XCTUnwrap(schema["allowedClassDispositions"] as? [String: [String]])
        let roles = try XCTUnwrap(schema["recordRolesByKind"] as? [String: String])
        var paths = Set<String>()
        var identities = Set<String>()
        for source in try files(value) {
            let path = try XCTUnwrap(source["path"] as? String)
            XCTAssertTrue(paths.insert(path).inserted)
            XCTAssertFalse(path.hasPrefix("/"))
            XCTAssertFalse(path.split(separator: "/").contains(".."))
            XCTAssertFalse(try XCTUnwrap(source["owner"] as? String).isEmpty)
            XCTAssertFalse(try XCTUnwrap(source["coverageRoute"] as? String).isEmpty)
            for item in try XCTUnwrap(source["items"] as? [[String: Any]]) {
                let kind = try XCTUnwrap(item["kind"] as? String)
                let locator = try XCTUnwrap(item["locator"] as? String)
                let identity = try XCTUnwrap(item["id"] as? String)
                let binding = Data((path + "\0" + kind + "\0" + locator).utf8)
                let expected = SHA256.hash(data: binding).map { String(format: "%02x", $0) }.joined()
                XCTAssertEqual(identity, String(expected.prefix(24)))
                XCTAssertTrue(identities.insert(identity).inserted)
                XCTAssertEqual(item["recordRole"] as? String, roles[kind])
                XCTAssertFalse(try XCTUnwrap(item["owner"] as? String).isEmpty)
                XCTAssertFalse(try XCTUnwrap(item["ownershipEvidence"] as? String).isEmpty)
                let disposition = try XCTUnwrap(item["disposition"] as? String)
                if disposition == "SOURCE_BOUND_VARIANTS_RESOLVED" {
                    XCTAssertNil(item["classification"] as? String)
                    let variants = try XCTUnwrap(item["sourceBoundVariants"] as? [String])
                    XCTAssertGreaterThanOrEqual(variants.count, 2)
                    XCTAssertEqual(Set(variants).count, variants.count)
                    let siblings = try XCTUnwrap(source["items"] as? [[String: Any]])
                    for variant in variants {
                        let producer = try XCTUnwrap(siblings.first { $0["id"] as? String == variant })
                        let classification = try XCTUnwrap(producer["classification"] as? String)
                        let producerDisposition = try XCTUnwrap(producer["disposition"] as? String)
                        XCTAssertTrue(allowed[classification]?.contains(producerDisposition) == true)
                    }
                } else {
                    let classification = try XCTUnwrap(item["classification"] as? String)
                    XCTAssertTrue(allowed[classification]?.contains(disposition) == true)
                }
                XCTAssertNotEqual(disposition, "SEMANTIC_REVIEW_REQUIRED")
            }
        }
    }

    func testCatalogArgumentRolesDoNotTranslateKeysOrTranslatorInstructions() throws {
        let rows = try items("FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift", in: inventory())
        let roleRows = rows.filter { $0["producerCall"] != nil }
        XCTAssertFalse(roleRows.isEmpty)
        for row in roleRows {
            let call = try XCTUnwrap(row["producerCall"] as? [String: Any])
            let role = try XCTUnwrap(call["argumentRole"] as? String)
            if ["meaningID", "key", "localized", "arguments", "plurals"].contains(role) {
                XCTAssertEqual(row["disposition"] as? String, "PRESERVE_MACHINE_VALUE")
            }
            if ["comment", "translatorComment"].contains(role) {
                XCTAssertEqual(row["classification"] as? String, "DEVELOPER_DEBUG_TEXT")
                XCTAssertEqual(row["disposition"] as? String, "DEVELOPER_ONLY")
            }
        }
        let attachmentDefaults = rows.filter {
            $0["catalogKey"] as? String == "feedback.mail.attachment_count" &&
            ($0["producerCall"] as? [String: Any])?["argumentRole"] as? String == "defaultValue"
        }
        XCTAssertFalse(attachmentDefaults.isEmpty)
        XCTAssertTrue(attachmentDefaults.allSatisfy { $0["classification"] as? String == "ACCESSIBILITY_TEXT" })
    }

    func testReturnedRecoverySentencesRemainLocalizable() throws {
        let rows = try items("FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", in: inventory())
        let recovery = rows.filter { $0["preview"] as? String == "\"Physical access is unavailable.\"" }
        XCTAssertFalse(recovery.isEmpty)
        for row in recovery {
            XCTAssertEqual(row["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
            XCTAssertEqual(row["disposition"] as? String, "LOCALIZE_STABLE_KEY")
            XCTAssertEqual(row["recordRole"] as? String, "SOURCE_LITERAL")
        }
    }

    func testPermissionCopyIsSeparateFromDocumentTypeIdentifiers() throws {
        let rows = try items("FieldEvidenceApp/Info.plist", in: inventory())
        let permission = try XCTUnwrap(rows.first { $0["locator"] as? String == "/NSSpeechRecognitionUsageDescription" })
        XCTAssertEqual(permission["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
        let identifier = try XCTUnwrap(rows.first { $0["locator"] as? String == "/UTExportedTypeDeclarations/0/UTTypeIdentifier" })
        XCTAssertEqual(identifier["classification"] as? String, "MACHINE_IDENTIFIER")
        XCTAssertEqual(identifier["disposition"] as? String, "PRESERVE_MACHINE_VALUE")
    }

    func testFrozenDisplayWordingIsPreservedSeparatelyFromNewReportChrome() throws {
        let rows = try items("FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift", in: inventory())
        let display = rows.filter { $0["model"] as? String == "DisplaySnapshotV1" }
        XCTAssertEqual(display.count, 5)
        for row in display {
            XCTAssertEqual(row["classification"] as? String, "REPORT_EXPORT_CHROME")
            XCTAssertEqual(row["disposition"] as? String, "PRESERVE_VERBATIM")
            XCTAssertEqual(row["preserveCanonicalSource"] as? Bool, true)
            XCTAssertEqual(row["provenanceRole"] as? String, "FROZEN_REPORT_SNAPSHOT")
        }
        let rawOutcome = try XCTUnwrap(rows.first {
            $0["model"] as? String == "ReportSnapshotV1" && $0["symbol"] as? String == "outcome"
        })
        XCTAssertEqual(rawOutcome["classification"] as? String, "MACHINE_IDENTIFIER")
        let note = try XCTUnwrap(rows.first {
            $0["model"] as? String == "ReportSnapshotV1" && $0["symbol"] as? String == "note"
        })
        XCTAssertEqual(note["classification"] as? String, "USER_AUTHORED_EVIDENCE")
        XCTAssertEqual(note["disposition"] as? String, "PRESERVE_VERBATIM")
    }

    func testHistoricalMetadataDoesNotAuthorizeAnotherLanguageOrRelease() throws {
        let rows = try items("docs/product/discovery/DiscoveryTruthCatalogV1.json", in: inventory())
        let frenchDraft = rows.filter { $0["sourceLocale"] as? String == "fr-FR" }
        XCTAssertEqual(frenchDraft.count, 5)
        for row in frenchDraft {
            XCTAssertEqual(row["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
            XCTAssertEqual(row["disposition"] as? String, "SEPARATE_AUTHORITY_REQUIRED")
            XCTAssertEqual(row["languageCohortExpansionAuthorized"] as? Bool, false)
            XCTAssertEqual(row["shippingEligibility"] as? String, "HISTORICAL_DRAFT_NO_V30_RELEASE_CREDIT")
        }
    }

    func testEditableWorkNotesHaveSeparateOwnershipFromTheirPrompts() throws {
        let rows = try items("FieldEvidenceApp/Features/Issues/RecordWorkView.swift", in: inventory())
        let bindings = rows.filter { $0["kind"] as? String == "TEXT_INPUT_BINDING" }
        XCTAssertEqual(Set(bindings.compactMap { $0["preview"] as? String }), ["$description", "$note"])
        for binding in bindings {
            XCTAssertEqual(binding["classification"] as? String, "USER_AUTHORED_EVIDENCE")
            XCTAssertEqual(binding["disposition"] as? String, "PRESERVE_VERBATIM")
            XCTAssertEqual(binding["recordRole"] as? String, "EDITABLE_TEXT_VALUE_BINDING")
            let parentID = try XCTUnwrap(binding["parentPresentationID"] as? String)
            let prompt = try XCTUnwrap(rows.first { $0["id"] as? String == parentID })
            XCTAssertEqual(prompt["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
            XCTAssertEqual(prompt["disposition"] as? String, "LOCALIZE_STABLE_KEY")
        }
    }

    func testBackupPayloadOwnershipDoesNotFollowItsMachineEnvelope() throws {
        let rows = try items("FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift", in: inventory())
        let authored = rows.filter { $0["classification"] as? String == "USER_AUTHORED_EVIDENCE" }
        XCTAssertEqual(authored.count, 5)
        XCTAssertTrue(authored.allSatisfy { $0["disposition"] as? String == "PRESERVE_VERBATIM" })
        let captured = rows.filter { $0["provenanceRole"] as? String == "PERSISTED_BACKUP_DISPLAY_SNAPSHOT" }
        XCTAssertEqual(captured.count, 4)
        for row in captured {
            XCTAssertEqual(row["preserveCanonicalSource"] as? Bool, true)
            XCTAssertEqual(row["disposition"] as? String, "SEPARATE_AUTHORITY_REQUIRED")
            XCTAssertNotEqual(row["classification"] as? String, "MACHINE_IDENTIFIER")
        }
    }

    func testPDFOperatorOwnershipDoesNotPropagateIntoRenderedText() throws {
        let rows = try items("FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift", in: inventory())
        let operatorLiteral = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "SWIFT_STRING" && $0["line"] as? Int == 1829
        })
        XCTAssertEqual(operatorLiteral["classification"] as? String, "MACHINE_IDENTIFIER")
        let insertedText = try XCTUnwrap(rows.first {
            $0["parentLiteralID"] as? String == operatorLiteral["id"] as? String &&
            $0["preview"] as? String == "escaped"
        })
        XCTAssertNotEqual(insertedText["classification"] as? String, "MACHINE_IDENTIFIER")
        let headings = rows.filter {
            $0["kind"] as? String == "SWIFT_STRING" && $0["line"] as? Int == 1669
        }
        XCTAssertEqual(headings.count, 1)
        XCTAssertEqual(headings.first?["classification"] as? String, "REPORT_EXPORT_CHROME")
    }

    func testSearchWordsAreNotDisguisedAsLanguageNeutralIdentifiers() throws {
        let rows = try items("FieldEvidenceApp/Domain/Search/SearchContractsV1.swift", in: inventory())
        let terms = rows.filter { $0["preview"] as? String == "\"my day\"" }
        XCTAssertEqual(terms.count, 2)
        for row in terms {
            XCTAssertEqual(row["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
            XCTAssertEqual(row["disposition"] as? String, "SEPARATE_AUTHORITY_REQUIRED")
            XCTAssertEqual(row["preserveCanonicalSource"] as? Bool, true)
        }
        let query = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "DYNAMIC_TEXT_DECLARATION" && $0["line"] as? Int == 727
        })
        XCTAssertEqual(query["classification"] as? String, "USER_AUTHORED_EVIDENCE")
        XCTAssertEqual(query["disposition"] as? String, "PRESERVE_VERBATIM")
    }

    func testWorklightSeparatesNewHeadingsFromCapturedDisplayAndAuthoredValues() throws {
        let rows = try items("FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift", in: inventory())
        let heading = try XCTUnwrap(rows.first { $0["preview"] as? String == "\"Identity and time\"" })
        XCTAssertEqual(heading["classification"] as? String, "REPORT_EXPORT_CHROME")
        XCTAssertEqual(heading["disposition"] as? String, "LOCALIZE_STABLE_KEY")
        let purpose = rows.filter {
            $0["kind"] as? String == "STRING_INTERPOLATION_VALUE" &&
            $0["preview"] as? String == "evidence.purposeDisplay"
        }
        XCTAssertEqual(purpose.count, 2)
        for row in purpose {
            XCTAssertEqual(row["classification"] as? String, "REPORT_EXPORT_CHROME")
            XCTAssertEqual(row["disposition"] as? String, "PRESERVE_VERBATIM")
            XCTAssertEqual(row["provenanceRole"] as? String, "FROZEN_REPORT_SNAPSHOT")
        }
        let site = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "STRING_INTERPOLATION_VALUE" &&
            $0["preview"] as? String == "snapshot.site.label"
        })
        XCTAssertEqual(site["classification"] as? String, "USER_AUTHORED_EVIDENCE")
        XCTAssertEqual(site["disposition"] as? String, "PRESERVE_VERBATIM")
    }

    func testVoiceRecoveryCopyDoesNotOwnTranscriptsOrCallerMessages() throws {
        let rows = try items("FieldEvidenceApp/Features/VoiceCapture/VoicePushToTalkCaptureView.swift", in: inventory())
        let recovery = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "SWIFT_STRING" && $0["line"] as? Int == 1276
        })
        XCTAssertEqual(recovery["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
        let transcript = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" && $0["line"] as? Int == 662
        })
        XCTAssertEqual(transcript["classification"] as? String, "USER_AUTHORED_EVIDENCE")
        XCTAssertEqual(transcript["disposition"] as? String, "PRESERVE_VERBATIM")
        let suppliedFieldMessage = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "DYNAMIC_TEXT_DECLARATION" && $0["line"] as? Int == 80
        })
        XCTAssertNotEqual(suppliedFieldMessage["classification"] as? String, "MACHINE_IDENTIFIER")
        let heading = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" && $0["line"] as? Int == 524
        })
        XCTAssertEqual(heading["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
    }

    func testOpenJSONLabelsRemainDistinctFromSemanticRolesAndGenericValues() throws {
        let rows = try items("FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift", in: inventory())
        let label = try XCTUnwrap(rows.first { $0["preview"] as? String == "\"Activity kind\"" })
        XCTAssertEqual(label["classification"] as? String, "REPORT_EXPORT_CHROME")
        let role = try XCTUnwrap(rows.first {
            $0["line"] as? Int == 3431 && $0["preview"] as? String == "\"fact\""
        })
        XCTAssertEqual(role["classification"] as? String, "MACHINE_IDENTIFIER")
        let genericValue = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "DYNAMIC_TEXT_DECLARATION" && $0["line"] as? Int == 158
        })
        XCTAssertNotEqual(genericValue["classification"] as? String, "MACHINE_IDENTIFIER")
    }

    func testDiscoveryProjectionWordsPreserveTheirExistingHashBoundary() throws {
        let rows = try items("FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift", in: inventory())
        let display = try XCTUnwrap(rows.first { $0["preview"] as? String == "\"Day lighting inventory\"" })
        XCTAssertEqual(display["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
        XCTAssertEqual(display["disposition"] as? String, "SEPARATE_AUTHORITY_REQUIRED")
        XCTAssertEqual(display["preserveCanonicalSource"] as? Bool, true)
        let tokens = try XCTUnwrap(rows.first { $0["locator"] as? String == "declaration:75717" })
        XCTAssertNotEqual(tokens["classification"] as? String, "MACHINE_IDENTIFIER")
    }

    func testActivityLocalMessagesDoNotOwnSuppliedReasons() throws {
        for (file, expectedCount) in [("PunchReviewWorkflowView.swift", 14), ("InstallationWorkflowView.swift", 18)] {
            let rows = try items("FieldEvidenceApp/Features/Activities/\(file)", in: inventory())
            let helpers = rows.filter {
                $0["kind"] as? String == "TEXT_PRESENTATION_CALL" &&
                ["sectionHeading", "commandButton", "stateLabel", "capabilityRow"].contains($0["symbol"] as? String ?? "")
            }
            XCTAssertEqual(helpers.count, expectedCount)
            XCTAssertTrue(helpers.allSatisfy { $0["classification"] as? String == "APP_OWNED_USER_FACING_COPY" })
            let reason = try XCTUnwrap(rows.first {
                $0["kind"] as? String == "STRING_INTERPOLATION_VALUE" && $0["preview"] as? String == "blocker.reason"
            })
            XCTAssertNotEqual(reason["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
            let status = try XCTUnwrap(rows.first {
                $0["kind"] as? String == "DYNAMIC_TEXT_DECLARATION" && $0["symbol"] as? String == "operationMessage"
            })
            XCTAssertEqual(status["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
            let commandID = try XCTUnwrap(rows.first {
                $0["kind"] as? String == "STRING_INTERPOLATION_VALUE" && $0["preview"] as? String == "commandIdentifier(command)"
            })
            XCTAssertEqual(commandID["classification"] as? String, "MACHINE_IDENTIFIER")
            if file == "InstallationWorkflowView.swift" {
                let derivedState = try XCTUnwrap(helpers.first { $0["symbol"] as? String == "stateLabel" })
                XCTAssertEqual(derivedState["provenanceRole"] as? String, "DERIVED_ENUM_DISPLAY")
                XCTAssertEqual(derivedState["preserveCanonicalSource"] as? Bool, true)
            }
        }
    }

    func testReportHistoryKeepsSavedDisplaySeparateFromCurrentLabels() throws {
        let rows = try items("FieldEvidenceApp/Features/Reports/ReportsRootView.swift", in: inventory())
        let stage = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "STRING_INTERPOLATION_VALUE" && $0["preview"] as? String == "visit.stage"
        })
        XCTAssertEqual(stage["classification"] as? String, "REPORT_EXPORT_CHROME")
        XCTAssertEqual(stage["disposition"] as? String, "PRESERVE_VERBATIM")
        XCTAssertEqual(stage["provenanceRole"] as? String, "FROZEN_REPORT_SNAPSHOT")
        let stageLabel = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "SWIFT_STRING" && $0["line"] as? Int == 470
        })
        XCTAssertEqual(stageLabel["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
        let mixedFact = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" && $0["symbol"] as? String == "ReportVisitFact" && $0["line"] as? Int == 470
        })
        XCTAssertNotEqual(mixedFact["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
        let savedName = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" && $0["line"] as? Int == 458
        })
        XCTAssertEqual(savedName["classification"] as? String, "USER_AUTHORED_EVIDENCE")
        XCTAssertEqual(savedName["disposition"] as? String, "PRESERVE_VERBATIM")
        let recoveryRows = try items("FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift", in: inventory())
        let workComparison = try XCTUnwrap(recoveryRows.first {
            $0["locator"] as? String == "chars:66471:66486"
        })
        XCTAssertEqual(workComparison["classification"] as? String, "REPORT_EXPORT_CHROME")
        XCTAssertEqual(workComparison["disposition"] as? String, "SEPARATE_AUTHORITY_REQUIRED")
        XCTAssertEqual(workComparison["preserveCanonicalSource"] as? Bool, true)
    }

    func testCurationPreservesReviewedCaptionsInsideLocalizableLabels() throws {
        let rows = try items("FieldEvidenceApp/Features/CheckRunner/EvidenceCurationView.swift", in: inventory())
        let helpers = rows.filter {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" &&
            ["sectionHeading", "markupButton", "WorklightStatusBadge"].contains($0["symbol"] as? String ?? "")
        }
        XCTAssertEqual(helpers.count, 8)
        XCTAssertTrue(helpers.allSatisfy { $0["classification"] as? String == "APP_OWNED_USER_FACING_COPY" })
        let captions = rows.filter {
            $0["kind"] as? String == "STRING_INTERPOLATION_VALUE" &&
            $0["preview"] as? String == "item.caption.text"
        }
        XCTAssertEqual(captions.count, 3)
        for caption in captions {
            XCTAssertEqual(caption["classification"] as? String, "USER_AUTHORED_EVIDENCE")
            XCTAssertEqual(caption["disposition"] as? String, "PRESERVE_VERBATIM")
            XCTAssertEqual(caption["preserveCanonicalSource"] as? Bool, true)
        }
        let spokenTemplate = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "SWIFT_STRING" && $0["line"] as? Int == 531
        })
        XCTAssertEqual(spokenTemplate["classification"] as? String, "ACCESSIBILITY_TEXT")
        XCTAssertEqual(spokenTemplate["disposition"] as? String, "LOCALIZE_STABLE_KEY")
        let controlID = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "SWIFT_STRING" && $0["line"] as? Int == 524
        })
        XCTAssertEqual(controlID["classification"] as? String, "MACHINE_IDENTIFIER")
        let mixedMarkup = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "DYNAMIC_TEXT_DECLARATION" && $0["line"] as? Int == 534
        })
        XCTAssertNotEqual(mixedMarkup["classification"] as? String, "MACHINE_IDENTIFIER")
        XCTAssertNotEqual(mixedMarkup["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
    }

    func testRecurrenceHelpersBindTheirLabelsWithoutOwningMixedValues() throws {
        let rows = try items("FieldEvidenceApp/Features/Scheduling/AdvancedRecurrenceWorkflowView.swift", in: inventory())
        let helpers = rows.filter {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" &&
            ["sectionHeading", "summaryRow", "commandButton"].contains($0["symbol"] as? String ?? "")
        }
        XCTAssertEqual(helpers.count, 21)
        for row in helpers {
            XCTAssertEqual(row["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
            let sourceID = try XCTUnwrap(row["sourceItemID"] as? String)
            XCTAssertTrue(rows.contains { $0["id"] as? String == sourceID && $0["kind"] as? String == "SWIFT_STRING" })
        }
        let identity = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "STRING_INTERPOLATION_VALUE" &&
            $0["preview"] as? String == "commandIdentifier(command)"
        })
        XCTAssertEqual(identity["classification"] as? String, "MACHINE_IDENTIFIER")
        let mixedValue = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" && $0["line"] as? Int == 339
        })
        XCTAssertNotEqual(mixedValue["classification"] as? String, "MACHINE_IDENTIFIER")
    }

    func testFinalizationDisplayComparisonIsSeparateFromRawOutcomeAndEditedNote() throws {
        let rows = try items("FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift", in: inventory())
        let comparison = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "SWIFT_STRING" && $0["line"] as? Int == 2505
        })
        XCTAssertEqual(comparison["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
        XCTAssertEqual(comparison["disposition"] as? String, "SEPARATE_AUTHORITY_REQUIRED")
        XCTAssertEqual(comparison["preserveCanonicalSource"] as? Bool, true)
        let outcomeKey = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "SWIFT_STRING" && $0["line"] as? Int == 2501
        })
        XCTAssertEqual(outcomeKey["classification"] as? String, "MACHINE_IDENTIFIER")
        let note = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "DYNAMIC_TEXT_DECLARATION" && $0["line"] as? Int == 29
        })
        XCTAssertEqual(note["classification"] as? String, "USER_AUTHORED_EVIDENCE")
        XCTAssertEqual(note["disposition"] as? String, "PRESERVE_VERBATIM")
        let newHistoryLabel = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "SWIFT_STRING" &&
            $0["line"] as? Int == 2578 && $0["preview"] as? String == "\"Work\""
        })
        XCTAssertEqual(newHistoryLabel["classification"] as? String, "REPORT_EXPORT_CHROME")
        XCTAssertEqual(newHistoryLabel["disposition"] as? String, "LOCALIZE_STABLE_KEY")
    }

    func testAccessibleMaterialSentenceDoesNotOwnItsAuthoredDescription() throws {
        let rows = try items("FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift", in: inventory())
        let sentence = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "SWIFT_STRING" &&
            ($0["preview"] as? String)?.hasPrefix("\"Material:") == true
        })
        XCTAssertEqual(sentence["classification"] as? String, "ACCESSIBILITY_TEXT")
        XCTAssertEqual(sentence["disposition"] as? String, "LOCALIZE_STABLE_KEY")
        let description = try XCTUnwrap(rows.first {
            $0["parentLiteralID"] as? String == sentence["id"] as? String &&
            $0["preview"] as? String == "$0.description"
        })
        XCTAssertEqual(description["classification"] as? String, "USER_AUTHORED_EVIDENCE")
        XCTAssertEqual(description["disposition"] as? String, "PRESERVE_VERBATIM")
        let claims = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "DYNAMIC_TEXT_DECLARATION" &&
            $0["line"] as? Int == 568
        })
        XCTAssertEqual(claims["classification"] as? String, "MACHINE_IDENTIFIER")
        XCTAssertEqual(claims["disposition"] as? String, "PRESERVE_MACHINE_VALUE")
    }

    func testShopBrandingRemainsAuthoredProfileContent() throws {
        let rows = try items("FieldEvidenceApp/Domain/Reporting/ShopReportProfileContractsV1.swift", in: inventory())
        let branding = rows.filter {
            $0["kind"] as? String == "DYNAMIC_TEXT_DECLARATION" &&
            ["shopDisplayName", "orderedBrandLines"].contains($0["symbol"] as? String ?? "")
        }
        XCTAssertEqual(branding.count, 2)
        for row in branding {
            XCTAssertEqual(row["classification"] as? String, "ADMIN_AUTHORED_TEMPLATE")
            XCTAssertEqual(row["disposition"] as? String, "PRESERVE_VERBATIM")
            XCTAssertEqual(row["preserveCanonicalSource"] as? Bool, true)
            XCTAssertEqual(row["provenanceRole"] as? String, "AUTHOR_SUPPLIED_REPORT_PROFILE")
        }
    }

    func testFinalizationPreservesCapturedCopyAndAuthoredWorkSeparately() throws {
        let rows = try items("FieldEvidenceApp/Domain/Workflow/FinalizationContracts.swift", in: inventory())
        let captured = rows.filter {
            $0["kind"] as? String == "DYNAMIC_TEXT_DECLARATION" &&
            [95, 99, 109, 125].contains($0["line"] as? Int ?? 0)
        }
        XCTAssertEqual(captured.count, 4)
        for row in captured {
            let professional = [95, 99].contains(row["line"] as? Int ?? 0)
            XCTAssertEqual(row["classification"] as? String,
                           professional ? "LEGAL_LICENSED_JURISDICTION" : "APP_OWNED_USER_FACING_COPY")
            XCTAssertEqual(row["disposition"] as? String, "SEPARATE_AUTHORITY_REQUIRED")
            XCTAssertEqual(row["preserveCanonicalSource"] as? Bool, true)
            XCTAssertEqual(row["provenanceRole"] as? String, "CAPTURED_FINALIZATION_PAYLOAD")
        }
        let authored = rows.filter {
            $0["kind"] as? String == "DYNAMIC_TEXT_DECLARATION" &&
            [112, 113].contains($0["line"] as? Int ?? 0)
        }
        XCTAssertEqual(authored.count, 2)
        for row in authored {
            XCTAssertEqual(row["classification"] as? String, "USER_AUTHORED_EVIDENCE")
            XCTAssertEqual(row["disposition"] as? String, "PRESERVE_VERBATIM")
        }
    }

    func testMyDayDerivedDisplayPreservesRawStateAndNumericValues() throws {
        let rows = try items("FieldEvidenceApp/Features/MyDay/MyDayWorkflowView.swift", in: inventory())
        let derived = rows.filter {
            $0["provenanceRole"] as? String == "DERIVED_ENUM_DISPLAY"
        }
        XCTAssertEqual(derived.count, 4)
        for display in derived {
            XCTAssertEqual(display["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
            XCTAssertEqual(display["preserveCanonicalSource"] as? Bool, true)
        }
        let exceptionCount = try XCTUnwrap(rows.first {
            $0["locator"] as? String == "chars:10470:10507"
        })
        XCTAssertEqual(exceptionCount["classification"] as? String, "MACHINE_IDENTIFIER")
        let reference = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "STRING_INTERPOLATION_VALUE" &&
            $0["preview"] as? String == "referenceLabel(reference)"
        })
        XCTAssertEqual(reference["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
        let helpers = rows.filter {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" &&
            ["sectionHeading", "valueRow"].contains($0["symbol"] as? String ?? "")
        }
        XCTAssertEqual(helpers.count, 9)
    }

    func testOutcomeReviewPreservesNotesAcknowledgementsAndDisplayComparisons() throws {
        let rows = try items("FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift", in: inventory())
        let notes = rows.filter { $0["kind"] as? String == "TEXT_INPUT_BINDING" }
        XCTAssertEqual(notes.count, 2)
        for note in notes {
            XCTAssertEqual(note["classification"] as? String, "USER_AUTHORED_EVIDENCE")
            XCTAssertEqual(note["disposition"] as? String, "PRESERVE_VERBATIM")
        }
        let acknowledgements = rows.filter {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" &&
            [295, 296].contains($0["line"] as? Int ?? 0)
        }
        XCTAssertEqual(acknowledgements.count, 2)
        for acknowledgement in acknowledgements {
            XCTAssertEqual(acknowledgement["classification"] as? String, "LEGAL_LICENSED_JURISDICTION")
            XCTAssertEqual(acknowledgement["preserveCanonicalSource"] as? Bool, true)
        }
        let purposeComparisons = rows.filter {
            $0["kind"] as? String == "SWIFT_STRING" &&
            [280, 281, 286, 287].contains($0["line"] as? Int ?? 0)
        }
        XCTAssertEqual(purposeComparisons.count, 4)
        for comparison in purposeComparisons {
            XCTAssertEqual(comparison["disposition"] as? String, "SEPARATE_AUTHORITY_REQUIRED")
            XCTAssertEqual(comparison["preserveCanonicalSource"] as? Bool, true)
        }
        let helperCalls = rows.filter {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" &&
            ["choiceButton", "reviewRow", "reviewEvidence", "WorklightStatusBadge"].contains($0["symbol"] as? String ?? "")
        }
        XCTAssertEqual(helperCalls.count, 18)
    }

    func testRecoveryCatalogAccessibilityAndFormattedCountsStaySeparate() throws {
        let rows = try items("FieldEvidenceApp/Features/Recovery/RecoveryCenterView.swift", in: inventory())
        let actionRows = rows.filter {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" &&
            $0["symbol"] as? String == "actionRow"
        }
        XCTAssertEqual(actionRows.count, 3)
        XCTAssertTrue(actionRows.allSatisfy {
            $0["classification"] as? String == "APP_OWNED_USER_FACING_COPY"
        })
        let status = rows.filter { $0["line"] as? Int == 161 }
        XCTAssertEqual(status.count, 4)
        XCTAssertTrue(status.allSatisfy {
            $0["classification"] as? String == "ACCESSIBILITY_TEXT"
        })
        let counts = rows.filter {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" &&
            [364, 371].contains($0["line"] as? Int ?? 0)
        }
        XCTAssertEqual(counts.count, 2)
        for count in counts {
            XCTAssertEqual(count["classification"] as? String, "SYSTEM_PROVIDED_DISPLAY")
            XCTAssertEqual(count["disposition"] as? String, "PRESERVE_SYSTEM_DISPLAY")
        }
    }

    func testAdapterLocalLabelDoesNotOwnMixedProviderValue() throws {
        let rows = try items("FieldEvidenceApp/Features/Integrations/IncumbentFileAdapterWorkflowView.swift", in: inventory())
        let label = try XCTUnwrap(rows.first {
            $0["locator"] as? String == "chars:6296:6311"
        })
        XCTAssertEqual(label["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
        let providerRow = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" &&
            $0["symbol"] as? String == "valueRow" && $0["line"] as? Int == 133
        })
        XCTAssertNotEqual(providerRow["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
        XCTAssertNil(providerRow["sourceItemID"])
        let helperCalls = rows.filter {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" &&
            ["sectionHeading", "commandButton", "valueRow"].contains($0["symbol"] as? String ?? "")
        }
        XCTAssertEqual(helperCalls.count, 22)
        let sentence = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "SWIFT_STRING" && $0["line"] as? Int == 382
        })
        XCTAssertEqual(sentence["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
        let rawState = try XCTUnwrap(rows.first {
            $0["parentLiteralID"] as? String == sentence["id"] as? String &&
            $0["preview"] as? String == "session.state.rawValue"
        })
        XCTAssertEqual(rawState["classification"] as? String, "MACHINE_IDENTIFIER")
        XCTAssertEqual(rawState["disposition"] as? String, "PRESERVE_MACHINE_VALUE")
    }

    func testMixedHelperReferencesOneCompleteSetOfSourceArguments() throws {
        let rows = try items("FieldEvidenceApp/Features/ReviewExchange/RecipientReviewWorkflowView.swift", in: inventory())
        let arguments = rows.filter { $0["kind"] as? String == "TEXT_HELPER_VALUE_ARGUMENT" }
        XCTAssertEqual(arguments.count, 4)
        let valueIDs = try arguments.map { try XCTUnwrap($0["id"] as? String) }
        for locator in ["function-parameter:15332", "call:15527:15538"] {
            let parent = try XCTUnwrap(rows.first { $0["locator"] as? String == locator })
            XCTAssertEqual(parent["disposition"] as? String, "SOURCE_BOUND_VARIANTS_RESOLVED")
            XCTAssertNil(parent["classification"] as? String)
            XCTAssertEqual(parent["sourceBoundVariants"] as? [String], valueIDs)
            XCTAssertEqual(parent["sourceBoundRuleID"] as? String, "RECIPIENT_PRIVATE_STATE_ROW_FLOW_V1")
        }
        let request = try XCTUnwrap(rows.first { $0["locator"] as? String == "call:5692:5755" })
        let label = try XCTUnwrap(rows.first { $0["locator"] as? String == "chars:5701:5710" })
        let labelID = try XCTUnwrap(label["id"] as? String)
        XCTAssertEqual(request["sourceBoundVariants"] as? [String], [labelID, valueIDs[0]])
        XCTAssertEqual(arguments[0]["classification"] as? String, "MACHINE_IDENTIFIER")
        XCTAssertEqual(arguments[0]["disposition"] as? String, "PRESERVE_MACHINE_VALUE")
        XCTAssertEqual(arguments[1]["preserveCanonicalSource"] as? Bool, true)
        let lifecycle = try XCTUnwrap(rows.first { $0["locator"] as? String == "function-return:15834" })
        XCTAssertEqual(arguments[1]["producerItemIDs"] as? [String], [try XCTUnwrap(lifecycle["id"] as? String)])
        for argument in arguments.dropFirst(2) {
            XCTAssertEqual(argument["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
            XCTAssertEqual((argument["producerItemIDs"] as? [String])?.count, 2)
        }
    }

    func testRecipientReviewKeepsPublicIdentitySeparateFromLifecycleDisplay() throws {
        let rows = try items("FieldEvidenceApp/Features/ReviewExchange/RecipientReviewWorkflowView.swift", in: inventory())
        let helpers = rows.filter {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" &&
            ["sectionHeading", "commandButton", "stateRow"].contains($0["symbol"] as? String ?? "")
        }
        XCTAssertEqual(helpers.count, 19)
        let request = try XCTUnwrap(helpers.first { $0["line"] as? Int == 130 })
        XCTAssertNotEqual(request["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
        XCTAssertNil(request["sourceItemID"])
        let session = try XCTUnwrap(helpers.first { $0["line"] as? Int == 131 })
        XCTAssertEqual(session["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
        XCTAssertEqual(session["preserveCanonicalSource"] as? Bool, true)
        let lifecycle = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "FUNCTION_TEXT_RETURN_DECLARATION" &&
            $0["functionSymbol"] as? String == "lifecycleText"
        })
        XCTAssertEqual(lifecycle["provenanceRole"] as? String, "DERIVED_ENUM_DISPLAY")
        XCTAssertEqual(lifecycle["preserveCanonicalSource"] as? Bool, true)
        let commandID = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "FUNCTION_TEXT_RETURN_DECLARATION" &&
            $0["functionSymbol"] as? String == "commandIdentifier"
        })
        XCTAssertEqual(commandID["classification"] as? String, "MACHINE_IDENTIFIER")
        let decisionCopy = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "SWIFT_STRING" && $0["line"] as? Int == 208
        })
        XCTAssertEqual(decisionCopy["protectedTokens"] as? [String], ["ACCEPT_AND_APPLY"])
    }

    func testManualResourcePluralCopyDoesNotOwnSuppliedMaterialValues() throws {
        let rows = try items("FieldEvidenceApp/Features/WorkResources/ManualWorkResourceWorkflowView.swift", in: inventory())
        let suffix = try XCTUnwrap(rows.first { $0["locator"] as? String == "interpolation:13149:13181" })
        XCTAssertEqual(suffix["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
        let minutes = try XCTUnwrap(rows.first { $0["locator"] as? String == "interpolation:13123:13139" })
        XCTAssertEqual(minutes["classification"] as? String, "MACHINE_IDENTIFIER")
        let decimal = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "FUNCTION_TEXT_RETURN_DECLARATION" &&
            $0["functionSymbol"] as? String == "exactDecimal"
        })
        XCTAssertEqual(decimal["disposition"] as? String, "PRESERVE_MACHINE_VALUE")
        for locator in ["call:6450:6472", "interpolation:6969:6990", "call:4903:4972"] {
            let supplied = try XCTUnwrap(rows.first { $0["locator"] as? String == locator })
            XCTAssertNotEqual(supplied["classification"] as? String, "APP_OWNED_USER_FACING_COPY")
            XCTAssertNil(supplied["sourceItemID"])
        }
        let helpers = rows.filter {
            $0["kind"] as? String == "TEXT_PRESENTATION_CALL" &&
            ["sectionHeading", "commandButton", "valueRow", "materials"].contains($0["symbol"] as? String ?? "")
        }
        XCTAssertEqual(helpers.count, 14)
    }

    func testFunctionTextCarriersAreSeparateFromLiteralsAndStorageFields() throws {
        let value = try inventory()
        let contactRows = try items("FieldEvidenceApp/Application/Contacts/OperationalContactCoordinatorV1.swift", in: value)
        let csvCarriers = contactRows.filter { $0["functionSymbol"] as? String == "csvFields" }
        XCTAssertEqual(csvCarriers.count, 2)
        let input = try XCTUnwrap(csvCarriers.first {
            $0["kind"] as? String == "FUNCTION_TEXT_PARAMETER_DECLARATION"
        })
        XCTAssertEqual(input["symbol"] as? String, "line")
        XCTAssertEqual(input["parameterIndex"] as? Int, 0)
        XCTAssertEqual(input["externalLabel"] as? String, "_")
        XCTAssertEqual(input["line"] as? Int, 481)
        let output = try XCTUnwrap(csvCarriers.first {
            $0["kind"] as? String == "FUNCTION_TEXT_RETURN_DECLARATION"
        })
        XCTAssertEqual(output["preview"] as? String, "[String]")
        let voiceRows = try items("FieldEvidenceApp/Application/VoiceStructuring/VoiceStructuringServiceV1.swift", in: value)
        let normalization = voiceRows.filter { $0["functionSymbol"] as? String == "normalizedPhrase" }
        XCTAssertEqual(normalization.count, 3)
        XCTAssertEqual(Set(normalization.compactMap { $0["line"] as? Int }), Set([438, 439, 440]))
        for carrier in csvCarriers + normalization {
            XCTAssertEqual(carrier["recordRole"] as? String, "TEXT_VALUE_PRODUCER_DECLARATION")
            XCTAssertFalse(try XCTUnwrap(carrier["ownershipBoundary"] as? String).isEmpty)
            XCTAssertNil(carrier["sourceItemID"])
            XCTAssertNil(carrier["parentLiteralID"])
        }
    }

    func testInitializerTextInputsHaveIndependentSourceRecords() throws {
        let rows = try items("FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift", in: inventory())
        let initializerInputs = rows.filter { $0["callableKind"] as? String == "INITIALIZER" }
        for symbol in ["workspaceID", "contentID", "mediaType", "createdAt"] {
            let matches = initializerInputs.filter { $0["symbol"] as? String == symbol }
            XCTAssertEqual(matches.count, 1)
            let input = try XCTUnwrap(matches.first)
            XCTAssertEqual(input["kind"] as? String, "FUNCTION_TEXT_PARAMETER_DECLARATION")
            XCTAssertEqual(input["functionSymbol"] as? String, "init")
            XCTAssertEqual(input["preview"] as? String, "String")
            XCTAssertEqual(input["externalLabel"] as? String, symbol)
            XCTAssertNotNil(input["parameterIndex"] as? Int)
            XCTAssertNil(input["sourceItemID"])
            XCTAssertNil(input["parentLiteralID"])
            XCTAssertFalse(try XCTUnwrap(input["ownershipBoundary"] as? String).isEmpty)
        }
        XCTAssertFalse(initializerInputs.contains { $0["kind"] as? String == "FUNCTION_TEXT_RETURN_DECLARATION" })
    }

    func testSubscriptTextParameterHasItsOwnSourceRecord() throws {
        let rows = try items("FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift", in: inventory())
        let inputs = rows.filter { $0["callableKind"] as? String == "SUBSCRIPT" }
        XCTAssertEqual(inputs.count, 1)
        let input = try XCTUnwrap(inputs.first)
        XCTAssertEqual(input["kind"] as? String, "FUNCTION_TEXT_PARAMETER_DECLARATION")
        XCTAssertEqual(input["functionSymbol"] as? String, "subscript")
        XCTAssertEqual(input["symbol"] as? String, "path")
        XCTAssertEqual(input["parameterIndex"] as? Int, 0)
        XCTAssertEqual(input["line"] as? Int, 368)
        XCTAssertEqual(input["preview"] as? String, "String")
        XCTAssertNil(input["sourceItemID"])
        XCTAssertNil(input["parentLiteralID"])
    }

    func testClosureTypealiasInputsHaveIndependentSourceRecords() throws {
        let value = try inventory()
        let expected: [(String, String, [Int])] = [
            ("FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift", "ContentReferenceResolver", [0]),
            ("FieldEvidenceApp/Infrastructure/Commerce/StoreKitProductLoader.swift", "ProductsProvider", [0]),
            ("FieldEvidenceApp/Infrastructure/Media/TemporalEvidenceLifecycleAdapterV1.swift", "TemporalEvidencePromotedContentVerificationV1", [1, 2]),
            ("FieldEvidenceApp/Infrastructure/Media/TemporalEvidenceLifecycleAdapterV1.swift", "TemporalEvidencePromotedContentRemovalV1", [1, 2])
        ]
        for (path, alias, indices) in expected {
            let inputs = try items(path, in: value).filter {
                $0["kind"] as? String == "TYPEALIAS_CLOSURE_TEXT_PARAMETER_DECLARATION"
                    && $0["typealiasSymbol"] as? String == alias
            }
            XCTAssertEqual(inputs.compactMap { $0["parameterIndex"] as? Int }, indices)
            for input in inputs {
                XCTAssertEqual(input["recordRole"] as? String, "TEXT_VALUE_PRODUCER_DECLARATION")
                XCTAssertFalse(try XCTUnwrap(input["ownershipBoundary"] as? String).isEmpty)
                XCTAssertNotNil(input["line"] as? Int)
                XCTAssertNotNil(input["column"] as? Int)
                XCTAssertNil(input["sourceItemID"])
                XCTAssertNil(input["parentLiteralID"])
            }
        }
        let tupleRows = try items("FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift", in: value)
        XCTAssertFalse(tupleRows.contains {
            $0["kind"] as? String == "TYPEALIAS_CLOSURE_TEXT_PARAMETER_DECLARATION"
                && $0["typealiasSymbol"] as? String == "DraftNode"
        })
    }

    func testTupleTypealiasTextElementsHaveSeparateSourceRecords() throws {
        let value = try inventory()
        let expected: [(String, String, [Int], [String])] = [
            ("FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift", "DraftNode",
             [0, 1, 2, 3, 4], ["section", "role", "label", "value", "referenceID"]),
            ("FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift", "RecordOverrides",
             [2, 3, 5, 6, 7, 8, 9], ["state", "draftStepKey", "outcomeKey", "couldNotVerifyKey", "couldNotVerifyDisplaySnapshot", "couldNotVerifyRegistryVersion", "note"])
        ]
        for (path, alias, indices, labels) in expected {
            let elements = try items(path, in: value).filter {
                $0["kind"] as? String == "TYPEALIAS_TUPLE_TEXT_ELEMENT_DECLARATION"
                    && $0["typealiasSymbol"] as? String == alias
            }
            XCTAssertEqual(elements.compactMap { $0["elementIndex"] as? Int }, indices)
            XCTAssertEqual(elements.compactMap { $0["elementLabel"] as? String }, labels)
            for element in elements {
                XCTAssertEqual(element["recordRole"] as? String, "TEXT_VALUE_PRODUCER_DECLARATION")
                XCTAssertFalse(try XCTUnwrap(element["ownershipBoundary"] as? String).isEmpty)
                XCTAssertNotNil(element["line"] as? Int)
                XCTAssertNotNil(element["column"] as? Int)
                XCTAssertNil(element["sourceItemID"])
                XCTAssertNil(element["parentLiteralID"])
            }
        }
    }

    func testInlineClosureSlotsRetainTheirOwnParentContext() throws {
        let value = try inventory()
        let reportRows = try items("FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift", in: value)
        let expected: [(String, Int, Int, Int)] = [("append", 1, 5, 0), ("visibleID", 2, 2, 1), ("visibleDigest", 3, 2, 1)]
        for (symbol, outerIndex, inputCount, returnCount) in expected {
            let rows = reportRows.filter {
                $0["parentFunctionSymbol"] as? String == "appendAuthorityCriterion"
                    && $0["parentParameterSymbol"] as? String == symbol
            }
            let inputs = rows.filter { $0["kind"] as? String == "INLINE_CLOSURE_TEXT_PARAMETER_DECLARATION" }
            let returns = rows.filter { $0["kind"] as? String == "INLINE_CLOSURE_TEXT_RETURN_DECLARATION" }
            XCTAssertEqual(inputs.count, inputCount)
            XCTAssertEqual(returns.count, returnCount)
            XCTAssertEqual(inputs.compactMap { $0["closureParameterIndex"] as? Int }, Array(0..<inputCount))
            for row in rows {
                XCTAssertEqual(row["closureParentKind"] as? String, "FUNCTION_PARAMETER")
                XCTAssertEqual(row["parentCallableKind"] as? String, "FUNCTION")
                XCTAssertEqual(row["parentParameterIndex"] as? Int, outerIndex)
                XCTAssertNil(row["parentStorageSymbol"])
                XCTAssertFalse(try XCTUnwrap(row["ownershipBoundary"] as? String).isEmpty)
                XCTAssertNil(row["sourceItemID"])
                XCTAssertNil(row["parentLiteralID"])
            }
            for row in returns { XCTAssertNil(row["closureParameterIndex"]) }
        }
        let queryRows = try items("FieldEvidenceApp/Application/SystemDiscovery/PrivateSystemDiscoveryCoordinatorV1.swift", in: value)
        let storage = queryRows.filter { $0["parentStorageSymbol"] as? String == "resolveOpaqueQuery" }
        XCTAssertEqual(storage.count, 2)
        XCTAssertEqual(Set(storage.compactMap { $0["kind"] as? String }),
                       Set(["INLINE_CLOSURE_TEXT_PARAMETER_DECLARATION", "INLINE_CLOSURE_TEXT_RETURN_DECLARATION"]))
        for row in storage {
            XCTAssertEqual(row["closureParentKind"] as? String, "STORAGE_DECLARATION")
            XCTAssertNil(row["parentFunctionSymbol"])
            XCTAssertNil(row["parentParameterIndex"])
        }
    }

    func testFunctionTupleResultsHaveIndependentTextElements() throws {
        let rows = try items("FieldEvidenceApp/Domain/Workflow/SurveySessionContractsV1.swift", in: inventory())
        let result = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "FUNCTION_TUPLE_TEXT_ELEMENT_DECLARATION"
                && $0["functionSymbol"] as? String == "project"
                && $0["elementLabel"] as? String == "ruleIDs"
        })
        XCTAssertEqual(result["callableKind"] as? String, "FUNCTION")
        XCTAssertEqual(result["elementIndex"] as? Int, 1)
        XCTAssertEqual(result["preview"] as? String, "[String]")
        XCTAssertEqual(result["line"] as? Int, 178)
        XCTAssertNil(result["parameterIndex"])
        XCTAssertNil(result["typealiasSymbol"])
        XCTAssertNil(result["sourceItemID"])
        XCTAssertFalse(try XCTUnwrap(result["ownershipBoundary"] as? String).isEmpty)
    }

    func testCallbackTupleResultsRetainTheirParentAndElementIndices() throws {
        let rows = try items("FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift", in: inventory()).filter {
            $0["kind"] as? String == "INLINE_CLOSURE_TUPLE_TEXT_ELEMENT_DECLARATION"
                && $0["parentFunctionSymbol"] as? String == "ordered"
                && $0["parentParameterSymbol"] as? String == "key"
        }
        XCTAssertEqual(rows.compactMap { $0["elementIndex"] as? Int }, [0, 1])
        for row in rows {
            XCTAssertEqual(row["closureParentKind"] as? String, "FUNCTION_PARAMETER")
            XCTAssertEqual(row["parentCallableKind"] as? String, "FUNCTION")
            XCTAssertEqual(row["parentParameterIndex"] as? Int, 1)
            XCTAssertEqual(row["preview"] as? String, "String")
            XCTAssertEqual(row["line"] as? Int, 2605)
            XCTAssertNil(row["closureParameterIndex"])
            XCTAssertNil(row["parentStorageSymbol"])
            XCTAssertNil(row["sourceItemID"])
            XCTAssertFalse(try XCTUnwrap(row["ownershipBoundary"] as? String).isEmpty)
        }
    }

    func testIlluminatedPlaybookEnglishReturnRetainsAllClosedSourceVariants() throws {
        let rows = try items("FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", in: inventory())
        let result = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "FUNCTION_TEXT_RETURN_DECLARATION"
                && $0["functionSymbol"] as? String == "english"
                && $0["line"] as? Int == 6353
        })
        XCTAssertNil(result["classification"])
        XCTAssertEqual(result["disposition"] as? String, "SOURCE_BOUND_VARIANTS_RESOLVED")
        XCTAssertEqual(result["sourceBoundRuleID"] as? String,
                       "ILLUMINATED_PLAYBOOK_CLOSED_RETURN_FLOW_V1")
        XCTAssertEqual((result["sourceBoundVariants"] as? [String])?.count, 47)
        XCTAssertNil(result["sourceItemID"])
        XCTAssertNil(result["preserveCanonicalSource"])
        XCTAssertFalse(try XCTUnwrap(result["ownershipBoundary"] as? String).isEmpty)
    }

    func testPartsMaterialTextAndStockCodesKeepTheirSeparateInputRoles() throws {
        let rows = try items("FieldEvidenceApp/Features/PartsStock/PartsStockWorkflowView.swift", in: inventory())
        let material = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "TEXT_INPUT_BINDING" && $0["preview"] as? String == "$useMaterialText"
        })
        XCTAssertEqual(material["classification"] as? String, "USER_AUTHORED_EVIDENCE")
        XCTAssertEqual(material["disposition"] as? String, "PRESERVE_VERBATIM")
        let code = try XCTUnwrap(rows.first {
            $0["kind"] as? String == "TEXT_INPUT_BINDING" && $0["preview"] as? String == "$manualLookupText"
        })
        XCTAssertEqual(code["classification"] as? String, "MACHINE_IDENTIFIER")
        XCTAssertEqual(code["disposition"] as? String, "PRESERVE_MACHINE_VALUE")
    }
}
