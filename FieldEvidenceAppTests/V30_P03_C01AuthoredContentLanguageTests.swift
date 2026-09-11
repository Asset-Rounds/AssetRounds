import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp
@MainActor
final class V30P03C01AuthoredContentLanguageTests: XCTestCase {
    func testFixturePreservesExactUnicodeSourceBytesAndAllSevenLayers() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.sources.map(\.id), [
            "nfc-worker-cjk-arabic", "nfd-family-hangul-arabic", "template-source",
        ])
        for item in fixture.sources {
            XCTAssertEqual(item.text.utf8.count, item.utf8ByteCount, item.id)
            XCTAssertEqual(AuthoredContentLanguageValidationV1.sha256(Data(item.text.utf8)), item.sha256, item.id)
        }
        XCTAssertNotEqual(Array(fixture.sources[0].text.utf8), Array(fixture.sources[1].text.utf8))
        XCTAssertEqual(Set(AuthoredContentLayerV1.allCases), [
            .appUI, .adminTemplate, .instruction, .inspectorCustomerEvidence,
            .derivedTranslation, .reportChrome, .licensedJurisdictionContent,
        ])
    }
    func testUnknownAndUnshippedAuthoredLanguageRemainIndependentOfAppLanguage() throws {
        let unknown = try source(language: .unknown)
        let french = try source(language: .known("fr"))
        XCTAssertEqual(unknown.language, .unknown)
        XCTAssertEqual(french.language, .known("fr"))
        XCTAssertTrue(AppLanguageTagV1.supportedRawValues.isDisjoint(with: ["fr"]))
        XCTAssertNoThrow(try unknown.validate())
        XCTAssertNoThrow(try french.validate())
    }
    func testLayerSpecificOwnerAndLicensedDeclarationsFailClosed() throws {
        let owner = try ownerVersion()
        let licensed = try licensedAuthority()
        XCTAssertNoThrow(try source(layer: .adminTemplate, owner: owner).validate())
        XCTAssertNoThrow(try source(layer: .instruction, owner: owner).validate())
        XCTAssertNoThrow(try source(layer: .licensedJurisdictionContent, owner: owner, licensed: licensed).validate())
        XCTAssertThrowsError(try source(layer: .adminTemplate).validate())
        XCTAssertThrowsError(try source(layer: .licensedJurisdictionContent, owner: owner).validate())
        XCTAssertThrowsError(try AuthoredContentOwnerVersionV1(ownerID: "bad space", version: "1", releaseSHA256: digest("r")))
        XCTAssertThrowsError(try LicensedContentLanguageAuthorityV1(licenseID: "", sourceID: "source", jurisdiction: try .init(countryCode: "US"), reviewerID: "reviewer", version: "1"))
    }
    func testCandidateBecomesEditedWhenSourceRevisionDigestOrOwnerReleaseChanges() throws {
        let bytes = Data("source bytes".utf8)
        let original = try source(bytes: bytes, layer: .instruction, owner: try ownerVersion())
        let provenance = try translation(source: original)
        let coordinator = AuthoredContentLanguageCoordinatorV1()
        let candidate = try coordinator.candidate(for: provenance, currentSource: original, sourceBytes: bytes)
        XCTAssertEqual(try coordinator.assess(candidate, currentSource: original, sourceBytes: bytes).state, .sourceBindingCurrent)
        for changed in [
            try source(bytes: Data("edited".utf8), layer: .instruction, owner: try ownerVersion()),
            try source(bytes: bytes, revision: 2, layer: .instruction, owner: try ownerVersion()),
            try source(bytes: bytes, layer: .instruction, owner: try ownerVersion(version: "2")),
        ] {
            XCTAssertEqual(try coordinator.assess(candidate, currentSource: changed, sourceBytes: changed.sourceSHA256 == original.sourceSHA256 ? bytes : Data("edited".utf8)).state, .sourceEdited)
        }
    }
    func testPrivacyDigestAdditionRemovalAndChangeInvalidateEvenWhenBytesMatch() throws {
        let bytes = Data("unchanged source".utf8)
        let baseline = try source(bytes: bytes, redaction: nil)
        let coordinator = AuthoredContentLanguageCoordinatorV1()
        let active = try coordinator.candidate(for: translation(source: baseline), currentSource: baseline, sourceBytes: bytes)
        for digestValue in [digest("manifest-a"), digest("manifest-b")] {
            let changed = try source(bytes: bytes, redaction: digestValue)
            XCTAssertEqual(try coordinator.assess(active, currentSource: changed, sourceBytes: bytes).state, .sourceRedacted)
        }
        let redacted = try source(bytes: bytes, redaction: digest("manifest-a"))
        let redactedCandidate = try coordinator.candidate(for: translation(source: redacted), currentSource: redacted, sourceBytes: bytes)
        XCTAssertEqual(try coordinator.assess(redactedCandidate, currentSource: baseline, sourceBytes: bytes).state, .sourceRedacted)
    }
    func testSourceBytesMismatchAndMalformedCodableValuesFailClosed() throws {
        let source = try source(bytes: Data("exact".utf8))
        XCTAssertThrowsError(try source.validate(sourceBytes: Data("changed".utf8))) {
            XCTAssertEqual($0 as? AuthoredContentLanguageFailureV1, .sourceBytesMismatch)
        }
        var forged = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any]
        )
        forged["sourceID"] = "bad source"
        let decoded = try JSONDecoder().decode(
            AuthoredContentLanguageSourceV1.self,
            from: JSONSerialization.data(withJSONObject: forged, options: [.sortedKeys])
        )
        XCTAssertThrowsError(try decoded.validate())
    }
    func testOnlyAuthoredLayersMayDescribeDerivedTranslations() throws {
        let owner = try ownerVersion()
        let licensed = try licensedAuthority()
        let disallowed = [
            try source(layer: .appUI),
            try source(layer: .reportChrome),
            try source(layer: .licensedJurisdictionContent, owner: owner, licensed: licensed),
        ]
        for item in disallowed {
            XCTAssertThrowsError(try translation(source: item)) { error in
                XCTAssertEqual(error as? AuthoredContentLanguageFailureV1, .invalidTranslation)
            }
        }
    }
    func testMalformedKnownLanguageAndWrongIdentityCannotBecomeCurrent() throws {
        let bytes = Data("identity bytes".utf8)
        let original = try source(bytes: bytes)
        let coordinator = AuthoredContentLanguageCoordinatorV1()
        let candidate = try coordinator.candidate(
            for: translation(source: original), currentSource: original, sourceBytes: bytes
        )
        let wrongWorkspace = try source(
            bytes: bytes,
            workspaceID: WorkspaceID(rawValue: UUID(uuidString: "42000000-0000-0000-0000-000000000002")!)
        )
        let wrongSourceID = try source(bytes: bytes, sourceID: "source.c22.changed")
        XCTAssertEqual(
            try coordinator.assess(candidate, currentSource: wrongWorkspace, sourceBytes: bytes).state,
            .sourceEdited
        )
        XCTAssertEqual(
            try coordinator.assess(candidate, currentSource: wrongSourceID, sourceBytes: bytes).state,
            .sourceEdited
        )
        var forged = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]
        )
        forged = replacing(forged, exactString: "es", with: "not_a_tag") as! [String: Any]
        let decoded = try JSONDecoder().decode(
            AuthoredContentLanguageSourceV1.self,
            from: JSONSerialization.data(withJSONObject: forged, options: [.sortedKeys])
        )
        XCTAssertThrowsError(try decoded.validate()) { error in
            XCTAssertEqual(error as? AuthoredContentLanguageFailureV1, .invalidLanguage)
        }
    }
    func testNFCAndNFDEquivalentTextRemainDistinctExactSourceBytes() throws {
        let nfc = "Caf\u{00E9}"
        let nfd = "Cafe\u{301}"
        XCTAssertEqual(nfc.precomposedStringWithCanonicalMapping, nfd.precomposedStringWithCanonicalMapping)
        let nfcBytes = Data(nfc.utf8)
        let nfdBytes = Data(nfd.utf8)
        XCTAssertNotEqual(nfcBytes, nfdBytes)
        let original = try source(bytes: nfcBytes)
        let coordinator = AuthoredContentLanguageCoordinatorV1()
        let candidate = try coordinator.candidate(
            for: translation(source: original), currentSource: original, sourceBytes: nfcBytes
        )
        let nfdSource = try source(bytes: nfdBytes)
        XCTAssertEqual(
            try coordinator.assess(candidate, currentSource: nfdSource, sourceBytes: nfdBytes).state,
            .sourceEdited
        )
    }
    func testCandidateAssessmentNeverPermitsTranslationDisplay() throws {
        let bytes = Data("exact".utf8)
        let source = try source(bytes: bytes)
        let coordinator = AuthoredContentLanguageCoordinatorV1()
        let candidate = try coordinator.candidate(for: translation(source: source), currentSource: source, sourceBytes: bytes)
        let assessment = try coordinator.assess(candidate, currentSource: source, sourceBytes: bytes)
        XCTAssertEqual(assessment.layer, .derivedTranslation)
        XCTAssertTrue(assessment.preservesSource)
        XCTAssertFalse(assessment.mayDisplayTranslation)
    }
    func testUnavailableInvalidatedAndSessionExpiredCandidatesCannotRevive() throws {
        let bytes = Data("source".utf8)
        let value = try source(bytes: bytes)
        let provenance = try translation(source: value)
        let first = AuthoredContentLanguageCoordinatorV1()
        let candidate = try first.candidate(for: provenance, currentSource: value, sourceBytes: bytes)
        XCTAssertEqual(try first.assess(candidate, currentSource: nil, sourceBytes: nil).state, .sourceUnavailable)
        first.invalidateAfterWriterApplication()
        XCTAssertEqual(try first.assess(candidate, currentSource: value, sourceBytes: bytes).state, .writerInvalidated)
        let laterSession = AuthoredContentLanguageCoordinatorV1()
        XCTAssertEqual(try laterSession.assess(candidate, currentSource: value, sourceBytes: bytes).state, .sessionExpired)
        XCTAssertFalse(try laterSession.assess(candidate, currentSource: value, sourceBytes: bytes).mayDisplayTranslation)
    }
    func testWriterFailuresRetainCandidatesAndSuccessfulCanonicalWritesInvalidateThem() throws {
        let workspace = WorkspaceID(rawValue: id(1))
        let schema = Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
        let container = try ModelContainer(
            for: schema, migrationPlan: nil,
            configurations: [ModelConfiguration(
                "V30-P03-C01-Writer", schema: schema,
                isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none
            )]
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        let adapter = WorkspaceWriterAdapterV1(modelContext: context)
        let sourceBytes = Data("authoritative source \u{00E9}".utf8)
        let authored = try source(bytes: sourceBytes, workspaceID: workspace)
        let coordinator = AuthoredContentLanguageCoordinatorV1.shared
        let retainedAfterFailure = try coordinator.candidate(
            for: translation(source: authored), currentSource: authored, sourceBytes: sourceBytes
        )
        XCTAssertThrowsError(try adapter.apply(
            .updateSiteTimeZone(.init(siteID: id(2), timeZoneID: "UTC", confirmedAt: instant)),
            occurredAt: instant, temporaryRelativePath: "c22/missing-site"
        ))
        XCTAssertEqual(
            try coordinator.assess(retainedAfterFailure, currentSource: authored, sourceBytes: sourceBytes).state,
            .sourceBindingCurrent
        )

        let actor = try privacyActor(workspace: workspace)
        context.insert(Site(id: id(3), label: "C22 site", timeZoneID: "UTC", createdAt: instant))
        context.insert(try ActorSnapshotRow(actor))
        try context.save()
        _ = try adapter.apply(
            .updateSiteTimeZone(.init(siteID: id(3), timeZoneID: "America/Los_Angeles", confirmedAt: instant)),
            occurredAt: instant, temporaryRelativePath: "c22/site-time-zone"
        )
        XCTAssertEqual(
            try coordinator.assess(retainedAfterFailure, currentSource: authored, sourceBytes: sourceBytes).state,
            .writerInvalidated
        )
        try context.save()

        let privacy = try privacyPublication(workspace: workspace, actor: actor)
        let retainedAfterSiteWrite = try coordinator.candidate(
            for: translation(source: authored), currentSource: authored, sourceBytes: sourceBytes
        )
        _ = try adapter.apply(
            .applyPrivacyTransform(.policy(privacy.policy)),
            occurredAt: instant, temporaryRelativePath: "c22/privacy-policy"
        )
        XCTAssertEqual(
            try coordinator.assess(retainedAfterSiteWrite, currentSource: authored, sourceBytes: sourceBytes).state,
            .writerInvalidated
        )
        try context.save()
        let policyRows = try context.fetch(FetchDescriptor<PrivacyTransformPolicyRow>())
        XCTAssertEqual(policyRows.count, 1)
        XCTAssertEqual(try XCTUnwrap(policyRows.first).value(), privacy.policy)

        let retainedAfterPolicy = try coordinator.candidate(
            for: translation(source: authored), currentSource: authored, sourceBytes: sourceBytes
        )
        _ = try adapter.apply(
            .applyPrivacyTransform(.publish(policy: privacy.policy, regions: [privacy.region], manifest: privacy.manifest)),
            occurredAt: instant, temporaryRelativePath: "c22/privacy-publish"
        )
        XCTAssertEqual(
            try coordinator.assess(retainedAfterPolicy, currentSource: authored, sourceBytes: sourceBytes).state,
            .writerInvalidated
        )
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PrivacyRegionRow>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PrivacyTransformManifestRow>()), 1)
        let actorRows = try context.fetch(FetchDescriptor<ActorSnapshotRow>())
        XCTAssertEqual(actorRows.count, 1)
        XCTAssertEqual(try XCTUnwrap(actorRows.first).value(), actor)
        XCTAssertEqual(sourceBytes, Data("authoritative source \u{00E9}".utf8))
    }

    private var instant: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "c2200000-0000-4000-8000-%012x", value))!
    }

    private func privacyActor(workspace: WorkspaceID) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(20), workspaceID: workspace, displayName: "C22 privacy author"
        )
        return try ActorSnapshotV1(
            snapshotID: id(21), workspaceID: workspace, actor: reference,
            responsibility: .performedBy, displayNameAtTime: "C22 privacy author", capturedAt: instant
        )
    }

    private func privacyPublication(
        workspace: WorkspaceID, actor: ActorSnapshotV1
    ) throws -> (policy: PrivacyTransformPolicyV1, region: PrivacyRegionV1, manifest: PrivacyTransformManifestV1) {
        let mutationID = try MutationIDV1(rawValue: id(30))
        let policy = try PrivacyTransformPolicyV1(
            policyID: id(31), workspaceID: workspace, purpose: "C22 customer redaction",
            audience: .customerReport, allowedTransformKinds: [.blur], allowedReasons: [.person],
            effectiveAt: instant, mutationID: mutationID
        )
        let originalBytes = Data("C22 original privacy source".utf8)
        let derivativeBytes = Data("C22 redacted privacy derivative".utf8)
        let workspaceText = workspace.rawValue.uuidString.lowercased()
        let originalObserved = try ContentIntegrityV1.observe(
            workspaceID: workspaceText, contentID: "c22-original", data: originalBytes, mediaType: "image/jpeg"
        )
        let derivativeObserved = try ContentIntegrityV1.observe(
            workspaceID: workspaceText, contentID: "c22-derivative", data: derivativeBytes, mediaType: "image/jpeg"
        )
        let original = try ContentReferenceV1(
            workspaceID: workspaceText, contentID: "c22-original", byteLength: Int64(originalBytes.count),
            mediaType: "image/jpeg", digests: originalObserved.digests, byteRole: .immutableOriginal,
            createdAt: "2027-01-15T08:00:00.000Z"
        )
        let derivative = try ContentReferenceV1(
            workspaceID: workspaceText, contentID: "c22-derivative", byteLength: Int64(derivativeBytes.count),
            mediaType: "image/jpeg", digests: derivativeObserved.digests, byteRole: .derivative,
            createdAt: "2027-01-15T08:00:00.000Z"
        )
        let sourceSHA256 = try XCTUnwrap(originalObserved.digests.digest(for: .sha256)?.hexadecimalValue)
        let derivativeSHA256 = try XCTUnwrap(derivativeObserved.digests.digest(for: .sha256)?.hexadecimalValue)
        let region = try PrivacyRegionV1(
            regionID: id(32), workspaceID: workspace, sourceContentID: original.contentID,
            sourceRevision: 1, sourceSHA256: sourceSHA256, coordinateSpace: .normalizedImage,
            orientation: .up, sourceBounds: try PrivacyIntegerRectV1(x: 10, y: 10, width: 100, height: 100),
            transformKind: .blur, reason: .person, author: actor, order: 0, authoredAt: instant,
            mutationID: mutationID
        )
        let manifest = try PrivacyTransformManifestV1(
            manifestID: id(33), workspaceID: workspace, original: original, sourceRevision: 1,
            sourceSHA256: sourceSHA256, derivative: derivative, derivativeSHA256: derivativeSHA256,
            policy: policy, orderedRegions: [region], rendererID: "c22.redaction", rendererVersion: "1",
            metadataSanitation: try PrivacyMetadataSanitationEvidenceV1(
                sanitizerID: "c22.sanitizer", sanitizerVersion: "1", result: .complete
            ), renderedAt: instant, mutationID: mutationID
        )
        return (policy, region, manifest)
    }

    private func replacing(_ value: Any, exactString: String, with replacement: String) -> Any {
        if let string = value as? String { return string == exactString ? replacement : string }
        if let values = value as? [Any] {
            return values.map { replacing($0, exactString: exactString, with: replacement) }
        }
        if let values = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: values.map { key, value in
                (key, replacing(value, exactString: exactString, with: replacement))
            })
        }
        return value
    }

    private func source(bytes: Data = Data("source".utf8), revision: UInt64 = 1, layer: AuthoredContentLayerV1 = .inspectorCustomerEvidence, language: AuthoredContentLanguageV1 = .known("es"), workspaceID: WorkspaceID = WorkspaceID(rawValue: UUID(uuidString: "42000000-0000-0000-0000-000000000001")!), sourceID: String = "source.c22", owner: AuthoredContentOwnerVersionV1? = nil, licensed: LicensedContentLanguageAuthorityV1? = nil, redaction: String? = nil) throws -> AuthoredContentLanguageSourceV1 {
        try .init(workspaceID: workspaceID, sourceID: sourceID, revision: revision, sourceSHA256: AuthoredContentLanguageValidationV1.sha256(bytes), layer: layer, language: language, ownerVersion: owner, licensedAuthority: licensed, redactionSHA256: redaction)
    }
    private func ownerVersion(version: String = "1") throws -> AuthoredContentOwnerVersionV1 { try .init(ownerID: "owner.c22", version: version, releaseSHA256: digest("release-\(version)")) }
    private func licensedAuthority() throws -> LicensedContentLanguageAuthorityV1 { try .init(licenseID: "license.c22", sourceID: "source.c22", jurisdiction: try .init(countryCode: "US", subdivisionCode: "CA"), reviewerID: "reviewer.c22", version: "1") }
    private func translation(source: AuthoredContentLanguageSourceV1) throws -> DerivedContentTranslationProvenanceV1 { try .init(artifactID: "translation.c22", artifactSHA256: digest("translation"), source: source, targetLanguage: .known("fr"), producerID: "producer.c22", producerVersion: "1") }
    private func digest(_ value: String) -> String { AuthoredContentLanguageValidationV1.sha256(Data(value.utf8)) }
    private func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/AuthoredContent/authored-content-language-cases-v1.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
}
private struct Fixture: Decodable { let schemaVersion: Int; let sources: [FixtureSource] }
private struct FixtureSource: Decodable { let id: String; let text: String; let utf8ByteCount: Int; let sha256: String; let language: String }
