import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Foundation contracts only. These tests do not represent a translator,
/// in-context reviewer, rendered screenshot, or shipping locale acceptance.
final class V30_P04_C01TranslationWorkflowTests: XCTestCase {
    func testConceptIdentitySeparatesActionsNounsAndUnprovenOutcomes() throws {
        let termbase = try document("V30TermbaseV1.json")
        let entries = try XCTUnwrap(termbase["entries"] as? [[String: Any]])
        let ids = try entries.map { try XCTUnwrap($0["conceptID"] as? String) }
        XCTAssertEqual(Set(ids).count, entries.count)
        for pair in [("core.backup", "noun"), ("core.back_up", "verb"),
                     ("core.recheck", "noun"), ("core.recheck_action", "verb")] {
            XCTAssertEqual(entries.first { $0["conceptID"] as? String == pair.0 }?["partOfSpeech"] as? String, pair.1)
        }
        let localSave = try XCTUnwrap(entries.first { $0["conceptID"] as? String == "state.saved" })
        XCTAssertEqual(localSave["forbiddenAlternatives"] as? [String], ["delivered"])
        XCTAssertFalse(LocalizedSyncStatePresentationV1.remoteSyncUnavailable.permitsSuccessAnnouncement)
        XCTAssertFalse(try XCTUnwrap(termbase["shippingTranslationApproval"] as? Bool))
        for entry in entries {
            XCTAssertTrue(try XCTUnwrap(entry["localeTerms"] as? [String: Any]).isEmpty)
        }
    }

    @MainActor
    func testDestructiveTokenIsExactWhileItsInstructionIsLocalized() throws {
        let rules = try XCTUnwrap(document("V30TermbaseV1.json")["doNotTranslate"] as? [[String: Any]])
        let erase = try XCTUnwrap(rules.first { $0["id"] as? String == "dnt.erase" })
        XCTAssertEqual(erase["value"] as? String, EraseAllService.requiredConfirmation)
        XCTAssertEqual(erase["rule"] as? String, "exactToken")
        let catalog = CriticalSurfaceLocalizationRegistryV1(languageLocale: Locale(identifier: "en"))
        XCTAssertTrue(catalog.eraseInstructions(token: EraseAllService.requiredConfirmation).contains("ERASE"))
    }

    func testFutureNamespacesRetainResearchOrderAndGrantNoActivation() throws {
        let termbase = try document("V30TermbaseV1.json")
        let namespaces = try XCTUnwrap(termbase["futureNamespaces"] as? [[String: Any]])
        let research = try json(at: "docs/design/v30/research/V30KeywordEvidenceBindingV1.json")
        let sequence = try XCTUnwrap(research["proposedVerticalSequence"] as? [String: Any])
        let labels = try XCTUnwrap(sequence["orderedLabels"] as? [String])
        XCTAssertEqual(namespaces.compactMap { $0["researchLabel"] as? String }, Array(labels.dropFirst()))
        for namespace in namespaces {
            XCTAssertEqual(namespace["status"] as? String, "RESERVED_RESEARCH_ONLY")
            XCTAssertEqual(namespace["productActivation"] as? Bool, false)
            XCTAssertTrue(try XCTUnwrap(namespace["terms"] as? [String]).isEmpty)
        }
    }

    func testReviewWorkflowPreservesSameCandidateCorrectionLawAndPrivacy() throws {
        let workflow = try document("V30SecureLinguisticReviewWorkflowV1.json")
        XCTAssertEqual(workflow["networkTranslationRequired"] as? Bool, false)
        XCTAssertEqual(workflow["shippingAcceptance"] as? Bool, false)
        let export = try XCTUnwrap(workflow["export"] as? [String: Any])
        XCTAssertEqual(export["automaticUpload"] as? Bool, false)
        let denied = try XCTUnwrap(export["deny"] as? [String])
        XCTAssertTrue(Set(["real customer data", "real photos", "real reports", "contacts", "accounts"]).isSubset(of: Set(denied)))
        let correction = try XCTUnwrap(workflow["correction"] as? [String: Any])
        XCTAssertEqual(correction["correctionCredit"] as? Bool, false)
        XCTAssertEqual(correction["terminalOutcomes"] as? [String], ["ACCEPTED_NO_CORRECTION", "CORRECTION_REQUIRED"])
        XCTAssertEqual(correction["localeCorrectionRepeats"] as? [String], ["causal locale lane", "V30-P04-C07", "V30-P05-C04", "V30-P05-C05", "V30-P05-C06", "V30-P06-C01", "V30-P06-C02"])
    }

    func testPacketCohortAndCandidateTupleMatchFrozenAuthority() throws {
        let schema = try document("V30TranslationReviewPacketSchemaV1.json")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let locale = try XCTUnwrap(properties["locale"] as? [String: Any])
        let authority = try json(at: "docs/design/v30/authority/V30LocaleRegistryV1.json")
        XCTAssertEqual(locale["enum"] as? [String], authority["completeBinaryLocalizationIDs"] as? [String])
        let candidate = try XCTUnwrap(properties["candidateTuple"] as? [String: Any])
        let shapes = try XCTUnwrap(candidate["anyOf"] as? [[String: Any]])
        let tupleFields = try XCTUnwrap(shapes.first?["required"] as? [String])
        let workflow = try document("V30SecureLinguisticReviewWorkflowV1.json")
        XCTAssertEqual(tupleFields, workflow["candidateTupleFields"] as? [String])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
    }

    private func document(_ name: String) throws -> [String: Any] {
        try json(at: "docs/design/v30/translation/" + name)
    }

    private func json(at path: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(path))) as? [String: Any])
    }
}
