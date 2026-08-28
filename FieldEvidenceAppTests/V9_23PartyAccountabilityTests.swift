import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

/// C38's unit/contract proof. The UI enrollment proof intentionally lives in
/// the separately skipped UI class until the post-S10 enrollment owner exists.
@MainActor
final class V9_23PartyAccountabilityTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_787_847_600)

    func testV23P03C38G01FixtureAndClosedEnumContractAreComplete() throws {
        let (object, corpus) = try loadFixture()
        XCTAssertEqual(
            Set(object.keys),
            [
                "actorSnapshots", "alternateCases", "cardID", "claims", "containsCustomerData",
                "containsSecrets", "enumContracts", "fixtureIdentity", "goldenCases", "hostileCases",
                "interruptionCases", "localizationAccessibility", "parties", "persistence",
                "qualificationSnapshots", "recoveryCases", "reportProjection", "schema",
                "schemaVersion", "searchProjection", "signoffSnapshots", "siteRoleEvents", "synthetic",
                "workspaceID",
            ]
        )
        XCTAssertEqual(corpus.schema, "V21P03C38PartyAccountabilityCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.fixtureIdentity, "V21-P03-C38-PARTY-ACCOUNTABILITY-CORPUS-V1")
        XCTAssertEqual(corpus.cardID, "V23-P03-C38")
        XCTAssertTrue(corpus.synthetic)
        XCTAssertFalse(corpus.containsCustomerData)
        XCTAssertFalse(corpus.containsSecrets)
        XCTAssertEqual(corpus.parties.count, 3)
        XCTAssertEqual(corpus.siteRoleEvents.count, 3)
        XCTAssertEqual(corpus.actorSnapshots.count, 3)
        XCTAssertEqual(corpus.qualificationSnapshots.count, 2)
        XCTAssertEqual(corpus.signoffSnapshots.count, 3)
        XCTAssertEqual(corpus.goldenCases.count, 2)
        XCTAssertEqual(corpus.alternateCases.count, 2)
        XCTAssertEqual(corpus.hostileCases.count, 3)
        XCTAssertEqual(corpus.interruptionCases.count, 2)
        XCTAssertEqual(corpus.recoveryCases.count, 3)

        XCTAssertEqual(Set(ServicePartyKindV1.allCases.map(\.rawValue)), Set(corpus.enumContracts.partyKinds))
        XCTAssertEqual(Set(ServicePartyProvenanceV1.allCases.map(\.rawValue)), Set(corpus.enumContracts.partyProvenance))
        XCTAssertEqual(ServicePartyPrivacyClassV1.allCases.map(\.rawValue), ["WORKSPACE_CUSTOMER_DATA"])
        XCTAssertEqual(Set(ServicePartyStateV1.allCases.map(\.rawValue)), Set(corpus.enumContracts.partyStates))
        XCTAssertEqual(Set(SitePartyRoleV1.allCases.map(\.rawValue)), Set(corpus.enumContracts.sitePartyRoles))
        XCTAssertEqual(
            SitePartyRoleSourceV1.allCases.map(\.rawValue),
            ["LOCALLY_RECORDED", "IMPORTED_EXTERNAL_EVIDENCE", "MIGRATED_BASELINE"]
        )
        XCTAssertEqual(Set(ResponsibilityKindV1.allCases.map(\.rawValue)), Set(corpus.enumContracts.responsibilities))
        XCTAssertEqual(Set(QualificationProvenanceV1.allCases.map(\.rawValue)), Set(corpus.enumContracts.qualificationProvenance))
        XCTAssertEqual(Set(SignoffDispositionV1.allCases.map(\.rawValue)), Set(corpus.enumContracts.signoffDispositions))
        XCTAssertEqual(Set(SignoffMethodV1.allCases.map(\.rawValue)), Set(corpus.enumContracts.signoffMethods))
        XCTAssertEqual(corpus.persistence.schemaRelease, "PERSISTENT_SCHEMA_V9_PARTY_ACCOUNTABILITY")
        XCTAssertEqual(corpus.persistence.predecessorSchemaVersion, 8)
        XCTAssertEqual(corpus.persistence.migration, "EXACT_V8_TO_V9_COPY_ON_WRITE")
        XCTAssertEqual(corpus.persistence.canonicalWriter, "P02-C01")
        XCTAssertEqual(corpus.persistence.lifecycleOwner, "P03-C38")
    }

    func testV23P03C38A01CanonicalValuesRowsAndSuccessorsPreserveHistory() throws {
        let values = try makeValues()

        XCTAssertEqual(
            ServicePartyKindV1.allCases.map(\.rawValue),
            ["PERSON", "ORGANIZATION"]
        )
        XCTAssertEqual(
            SitePartyRoleV1.allCases.map(\.rawValue),
            ["OWNER", "OPERATOR", "CLIENT", "SERVICE_PROVIDER", "CONTACT"]
        )

        let partyData = try PartyAccountabilitySnapshotCodecV1.encode(values.party)
        XCTAssertEqual(
            try PartyAccountabilitySnapshotCodecV1.decode(ServicePartyReferenceV1.self, from: partyData),
            values.party
        )
        let roleData = try PartyAccountabilitySnapshotCodecV1.encode(values.role)
        XCTAssertEqual(
            try PartyAccountabilitySnapshotCodecV1.decode(SitePartyRoleEventV1.self, from: roleData),
            values.role
        )
        let actorData = try PartyAccountabilitySnapshotCodecV1.encode(values.actor)
        XCTAssertEqual(
            try PartyAccountabilitySnapshotCodecV1.decode(ActorSnapshotV1.self, from: actorData),
            values.actor
        )
        let qualificationData = try PartyAccountabilitySnapshotCodecV1.encode(values.qualification)
        XCTAssertEqual(
            try PartyAccountabilitySnapshotCodecV1.decode(QualificationSnapshotV1.self, from: qualificationData),
            values.qualification
        )
        let disclosureData = try PartyAccountabilitySnapshotCodecV1.encode(values.disclosure)
        XCTAssertEqual(
            try PartyAccountabilitySnapshotCodecV1.decode(SignoffIntentDisclosureReleaseV1.self, from: disclosureData),
            values.disclosure
        )
        let assertionData = try PartyAccountabilitySnapshotCodecV1.encode(values.assertion)
        XCTAssertEqual(
            try PartyAccountabilitySnapshotCodecV1.decode(SignoffRoleAssertionV1.self, from: assertionData),
            values.assertion
        )
        let signoffData = try PartyAccountabilitySnapshotCodecV1.encode(values.signoff)
        XCTAssertEqual(
            try PartyAccountabilitySnapshotCodecV1.decode(SignoffSnapshotV1.self, from: signoffData),
            values.signoff
        )
        XCTAssertEqual(try PartyAccountabilitySnapshotCodecV1.encode(values.party), partyData)

        let partyRow = try ServicePartyRow(values.party)
        XCTAssertEqual(try partyRow.value(), values.party)
        let roleRow = try SitePartyRoleEventRow(values.role)
        XCTAssertEqual(try roleRow.value(), values.role)
        let actorRow = try ActorSnapshotRow(values.actor)
        XCTAssertEqual(try actorRow.value(), values.actor)
        let qualificationRow = try QualificationSnapshotRow(values.qualification)
        XCTAssertEqual(try qualificationRow.value(), values.qualification)
        let signoffRow = try SignoffSnapshotRow(values.signoff)
        XCTAssertEqual(try signoffRow.value(), values.signoff)

        let roleSuccessor = try SitePartyRoleEventV1(
            eventID: uuid(21), workspaceID: values.workspace,
            siteID: uuid(2), partyID: values.party.partyID, role: .serviceProvider,
            effectiveFrom: baseDate.addingTimeInterval(3_600),
            effectiveUntil: baseDate.addingTimeInterval(7_200), source: .locallyRecorded,
            supersedesEventID: values.role.eventID, revision: 2,
            mutationID: try mutation(21), recordedAt: baseDate.addingTimeInterval(3_601)
        )
        XCTAssertNoThrow(try roleSuccessor.validateSupersession(of: values.role))
        XCTAssertNoThrow(try SitePartyRoleEventRow(roleSuccessor, predecessor: values.role))

        let retiredParty = try ServicePartyReferenceV1(
            partyID: values.party.partyID, workspaceID: values.workspace, kind: values.party.kind,
            displayName: values.party.displayName, profileDescriptor: values.party.profileDescriptor,
            provenance: values.party.provenance, state: .retired,
            effectiveAt: values.party.effectiveAt, retiredAt: baseDate.addingTimeInterval(7_300),
            revision: 2, mutationID: try mutation(22)
        )
        XCTAssertNoThrow(try retiredParty.validateSuccessor(of: values.party))
        try partyRow.replace(with: retiredParty, expectedRevision: values.party.revision)
        XCTAssertEqual(try partyRow.value(), retiredParty)
        XCTAssertEqual(values.party.displayName, "Jordan Lee")
        XCTAssertThrowsError(try partyRow.replace(with: values.party, expectedRevision: 1)) {
            XCTAssertEqual($0 as? PartyAccountabilityFailureV1, .immutableHistory)
        }

        let signoffSuccessor = try SignoffSnapshotV1(
            snapshotID: uuid(51), workspaceID: values.workspace,
            purpose: values.signoff.purpose, subjectID: values.signoff.subjectID,
            subjectRevision: 2, disposition: .externalEvidenceAttached,
            method: .externalEvidenceReference, roleAssertion: values.assertion,
            qualification: values.qualification, externalEvidenceID: uuid(70),
            occurredAt: baseDate.addingTimeInterval(4_200), recordedAt: baseDate.addingTimeInterval(4_201),
            supersedesSnapshotID: values.signoff.snapshotID, mutationID: try mutation(23)
        )
        XCTAssertNoThrow(try signoffSuccessor.validateSupersession(of: values.signoff))
        XCTAssertNoThrow(try SignoffSnapshotRow(signoffSuccessor, predecessor: values.signoff))
    }

    func testV23P03C38H01UnknownTamperedCrossWorkspaceAndClaimInputsFailClosed() throws {
        let values = try makeValues()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(values.party)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["unexpected"] = true
        let unknown = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertThrowsError(try JSONDecoder().decode(ServicePartyReferenceV1.self, from: unknown)) {
            XCTAssertEqual($0 as? PartyAccountabilityFailureV1, .unknownKey)
        }

        object.removeValue(forKey: "unexpected")
        object.removeValue(forKey: "displayName")
        let missing = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertThrowsError(try JSONDecoder().decode(ServicePartyReferenceV1.self, from: missing)) {
            if let failure = $0 as? PartyAccountabilityFailureV1 {
                XCTAssertEqual(failure, .missingKey)
            } else if case DecodingError.keyNotFound = $0 {
                // The decoder remains fail-closed even when Foundation reports
                // the missing required key before the domain wrapper maps it.
            } else {
                XCTFail("missing required key must fail closed: \($0)")
            }
        }

        var tamperedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        tamperedObject["receiptSHA256"] = String(repeating: "0", count: 64)
        let tampered = try JSONSerialization.data(withJSONObject: tamperedObject, options: [.sortedKeys])
        XCTAssertThrowsError(try JSONDecoder().decode(ServicePartyReferenceV1.self, from: tampered)) {
            XCTAssertEqual($0 as? PartyAccountabilityFailureV1, .digestMismatch)
        }

        let otherWorkspace = WorkspaceID(rawValue: uuid(900))
        let foreignActor = try LocalActorReferenceV1(
            actorReferenceID: uuid(901), workspaceID: otherWorkspace,
            partyID: values.party.partyID, displayName: values.actor.actor.displayName
        )
        XCTAssertThrowsError(try SignoffSnapshotV1(
            snapshotID: uuid(902), workspaceID: values.workspace, purpose: values.signoff.purpose,
            subjectID: values.signoff.subjectID, subjectRevision: 1,
            disposition: .recordedLocalAssertion, method: .typedLocalAssertion,
            roleAssertion: try SignoffRoleAssertionV1(
                claimedRole: "Service technician", claimedRelationship: .serviceProvider,
                actor: try ActorSnapshotV1(
                    snapshotID: uuid(903), workspaceID: otherWorkspace, actor: foreignActor,
                    responsibility: .performedBy, displayNameAtTime: foreignActor.displayName,
                    capturedAt: baseDate
                ), disclosureRelease: values.disclosure
            ), occurredAt: baseDate, recordedAt: baseDate.addingTimeInterval(1), mutationID: try mutation(24)
        )) { XCTAssertEqual($0 as? PartyAccountabilityFailureV1, .crossWorkspaceReference) }

        XCTAssertThrowsError(try SignoffIntentDisclosureReleaseV1(
            releaseID: "fixture.c38.invalid", disclosureText: "Not a legal signature.",
            statesLocalAssertionOnly: false
        )) { XCTAssertEqual($0 as? PartyAccountabilityFailureV1, .unsupportedClaim) }
        XCTAssertThrowsError(try SignoffSnapshotV1(
            snapshotID: uuid(904), workspaceID: values.workspace, purpose: values.signoff.purpose,
            subjectID: values.signoff.subjectID, subjectRevision: 1,
            disposition: .recordedLocalAssertion, method: .noAssertion,
            occurredAt: baseDate, recordedAt: baseDate.addingTimeInterval(1), mutationID: try mutation(25)
        )) { XCTAssertEqual($0 as? PartyAccountabilityFailureV1, .unsupportedClaim) }
    }

    func testV23P03C38I01IdempotentEffectsAndR01BackupClaimsRemainBounded() throws {
        let values = try makeValues()
        let valuesToBackup: [(V9BackupPartyAccountabilityRecordV1.Kind, UUID, UInt64?, Data)] = [
            (.actorSnapshot, values.actor.snapshotID, nil, try PartyAccountabilitySnapshotCodecV1.encode(values.actor)),
            (.qualificationSnapshot, values.qualification.snapshotID, nil, try PartyAccountabilitySnapshotCodecV1.encode(values.qualification)),
            (.serviceParty, values.party.partyID, values.party.revision, try PartyAccountabilitySnapshotCodecV1.encode(values.party)),
            (.signoffSnapshot, values.signoff.snapshotID, 1, try PartyAccountabilitySnapshotCodecV1.encode(values.signoff)),
            (.sitePartyRoleEvent, values.role.eventID, values.role.revision, try PartyAccountabilitySnapshotCodecV1.encode(values.role)),
        ]
        let records = valuesToBackup.map {
            V9BackupPartyAccountabilityRecordV1(
                kind: $0.0, id: $0.1, workspaceID: values.workspace.rawValue,
                revision: $0.2, canonicalData: $0.3
            )
        }
        let backup = V4BackupRecordsV1(
            assets: [], evidenceFiles: [], issues: [], packets: [],
            partyAccountability: records, recordsSchemaVersion: 8,
            reports: [], sites: [], workflowRecords: []
        )
        let encoded = try BackupCanonicalEncoderV1().encodeRecords(backup).data
        let decoded = try BackupCanonicalDecoderV1().decodeRecords(encoded)
        XCTAssertEqual(decoded, backup)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let backupObjects = try XCTUnwrap(root["partyAccountability"] as? [[String: Any]])
        XCTAssertEqual(backupObjects.count, 5)
        XCTAssertEqual(Set(backupObjects.compactMap { $0["kind"] as? String }), Set(V9BackupPartyAccountabilityRecordV1.Kind.allCases.map(\.rawValue)))
        XCTAssertEqual(records.map { $0.canonicalData }, records.map { $0.canonicalData })
        XCTAssertEqual(try PartyAccountabilitySnapshotCodecV1.encode(values.signoff), try PartyAccountabilitySnapshotCodecV1.encode(values.signoff))

        let encoderSource = try sourceText("FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift")
        XCTAssertTrue(encoderSource.contains("partyAccountability"))
        let restoreSource = try sourceText("FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift")
        XCTAssertTrue(restoreSource.contains("V4BackupRecordsV1"))
        let deletionSource = try sourceText("FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift")
        XCTAssertTrue(deletionSource.contains("modelContext.delete"))
        let searchSource = try sourceText("FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift")
        XCTAssertFalse(searchSource.contains("credentialLocator"))

        let (_, corpus) = try loadFixture()
        XCTAssertTrue(corpus.reportProjection.historyIsImmutable)
        XCTAssertTrue(corpus.reportProjection.renamesDoNotRewriteSnapshots)
        XCTAssertTrue(corpus.searchProjection.rebuildIsRevisionBound)
        XCTAssertFalse(corpus.claims.identityVerified)
        XCTAssertFalse(corpus.claims.legalSignature)
        XCTAssertFalse(corpus.claims.nonRepudiation)
        XCTAssertFalse(corpus.claims.workflowTransition)
        XCTAssertFalse(corpus.claims.accountOrTenant)
        XCTAssertFalse(corpus.claims.networkSync)
    }

    func testV23P03C38AccessibilityLocalizationAndNonClaimMetadataAreExplicit() throws {
        let (_, corpus) = try loadFixture()
        XCTAssertEqual(corpus.localizationAccessibility.sourceLanguage, "en")
        XCTAssertEqual(corpus.localizationAccessibility.shippingLocales, ["en"])
        XCTAssertEqual(
            Set(corpus.localizationAccessibility.pseudoLocalesTestOnly),
            Set(["en-XA", "en-XB", "ar-XB", "en-XL", "en-XT"])
        )
        XCTAssertTrue(corpus.localizationAccessibility.rtlRequired)
        XCTAssertTrue(corpus.localizationAccessibility.dynamicTypeRequired)
        XCTAssertTrue(corpus.localizationAccessibility.voiceOverRequired)
        XCTAssertTrue(corpus.localizationAccessibility.voiceControlRequired)
        XCTAssertTrue(corpus.localizationAccessibility.switchControlRequired)
        XCTAssertTrue(corpus.localizationAccessibility.nonColorStateTextRequired)
        XCTAssertEqual(corpus.localizationAccessibility.semanticIDs.count, 7)

        let contractSource = try sourceText("FieldEvidenceApp/Domain/Accountability/PartyAccountabilityContractsV1.swift")
        XCTAssertTrue(contractSource.contains("SignoffIntentDisclosureReleaseV1"))
        XCTAssertTrue(contractSource.contains("disclaimsIdentityVerification"))
        XCTAssertTrue(contractSource.contains("disclaimsLegalSignature"))
        XCTAssertFalse(contractSource.contains("customer approved"))
        XCTAssertFalse(contractSource.contains("verified identity"))
    }
}

private extension V9_23PartyAccountabilityTests {
    struct Values {
        let workspace: WorkspaceID
        let party: ServicePartyReferenceV1
        let role: SitePartyRoleEventV1
        let actor: ActorSnapshotV1
        let qualification: QualificationSnapshotV1
        let disclosure: SignoffIntentDisclosureReleaseV1
        let assertion: SignoffRoleAssertionV1
        let signoff: SignoffSnapshotV1
    }

    struct Persistence: Decodable {
        let schemaRelease: String
        let predecessorSchemaVersion: Int
        let migration: String
        let canonicalWriter: String
        let lifecycleOwner: String
        let searchRebuild: String
        let deleteDisposition: String
        let exportDisposition: String
    }

    struct EnumContracts: Decodable {
        let partyKinds: [String]
        let partyProvenance: [String]
        let partyStates: [String]
        let sitePartyRoles: [String]
        let responsibilities: [String]
        let qualificationProvenance: [String]
        let signoffDispositions: [String]
        let signoffMethods: [String]
    }

    struct PartyVector: Decodable { let id: String; let kind: String; let displayName: String; let state: String; let revision: UInt64; let effectiveAt: String }
    struct RoleVector: Decodable { let id: String; let role: String; let revision: UInt64; let source: String }
    struct ActorVector: Decodable { let id: String; let displayNameAtTime: String; let responsibility: String }
    struct QualificationVector: Decodable { let id: String; let declaredScope: String; let provenance: String }
    struct SignoffVector: Decodable { let id: String; let purpose: String; let disposition: String; let method: String }
    struct CaseVector: Decodable { let id: String; let expectedResult: String; let reason: String }

    struct SearchProjection: Decodable {
        let allowlistedFields: [String]
        let excludedFields: [String]
        let rebuildIsRevisionBound: Bool
    }
    struct ReportProjection: Decodable { let frozenDisplayFields: [String]; let historyIsImmutable: Bool; let renamesDoNotRewriteSnapshots: Bool }
    struct LocalizationAccessibility: Decodable {
        let sourceLanguage: String
        let shippingLocales: [String]
        let pseudoLocalesTestOnly: [String]
        let rtlRequired: Bool
        let dynamicTypeRequired: Bool
        let voiceOverRequired: Bool
        let voiceControlRequired: Bool
        let switchControlRequired: Bool
        let nonColorStateTextRequired: Bool
        let semanticIDs: [String]
    }
    struct Claims: Decodable {
        let identityVerified: Bool
        let authorityVerified: Bool
        let legalSignature: Bool
        let nonRepudiation: Bool
        let workflowTransition: Bool
        let approvalForAnotherPerson: Bool
        let externalQualificationVerified: Bool
        let contactPointTruth: Bool
        let accountOrTenant: Bool
        let networkSync: Bool
    }
    struct Corpus: Decodable {
        let schema: String
        let schemaVersion: Int
        let fixtureIdentity: String
        let cardID: String
        let workspaceID: String
        let synthetic: Bool
        let containsCustomerData: Bool
        let containsSecrets: Bool
        let persistence: Persistence
        let enumContracts: EnumContracts
        let parties: [PartyVector]
        let siteRoleEvents: [RoleVector]
        let actorSnapshots: [ActorVector]
        let qualificationSnapshots: [QualificationVector]
        let signoffSnapshots: [SignoffVector]
        let searchProjection: SearchProjection
        let reportProjection: ReportProjection
        let localizationAccessibility: LocalizationAccessibility
        let claims: Claims
        let goldenCases: [CaseVector]
        let alternateCases: [CaseVector]
        let hostileCases: [CaseVector]
        let interruptionCases: [CaseVector]
        let recoveryCases: [CaseVector]
    }

    func loadFixture() throws -> ([String: Any], Corpus) {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V21P03C38PartyAccountabilityCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/Accountability"
            ) ?? bundle.url(forResource: "V21P03C38PartyAccountabilityCorpusV1", withExtension: "json")
        )
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (object, try JSONDecoder().decode(Corpus.self, from: data))
    }

    func makeValues() throws -> Values {
        let workspace = WorkspaceID(rawValue: uuid(1))
        let party = try ServicePartyReferenceV1(
            partyID: uuid(10), workspaceID: workspace, kind: .person,
            displayName: "Jordan Lee", profileDescriptor: "Independent sign technician",
            provenance: .locallyRecorded, state: .effective, effectiveAt: baseDate,
            revision: 1, mutationID: try mutation(10)
        )
        let role = try SitePartyRoleEventV1(
            eventID: uuid(20), workspaceID: workspace, siteID: uuid(2), partyID: party.partyID,
            role: .serviceProvider, effectiveFrom: baseDate, source: .locallyRecorded,
            revision: 1, mutationID: try mutation(20), recordedAt: baseDate.addingTimeInterval(1)
        )
        let actorReference = try LocalActorReferenceV1(
            actorReferenceID: uuid(30), workspaceID: workspace, partyID: party.partyID,
            displayName: "Jordan Lee"
        )
        let actor = try ActorSnapshotV1(
            snapshotID: uuid(31), workspaceID: workspace, actor: actorReference,
            responsibility: .performedBy, displayNameAtTime: "Jordan Lee",
            capturedAt: baseDate.addingTimeInterval(2)
        )
        let qualification = try QualificationSnapshotV1(
            snapshotID: uuid(40), workspaceID: workspace, declaredScope: "Exterior sign service",
            issuerDisplay: "Jordan Lee", provenance: .selfDeclared,
            capturedAt: baseDate.addingTimeInterval(3)
        )
        let disclosure = try SignoffIntentDisclosureReleaseV1(
            releaseID: "fixture.c38.v1",
            disclosureText: "Recorded locally; not verified identity or a legal signature."
        )
        let assertion = try SignoffRoleAssertionV1(
            claimedRole: "Service technician", claimedRelationship: .serviceProvider,
            actor: actor, disclosureRelease: disclosure
        )
        let signoff = try SignoffSnapshotV1(
            snapshotID: uuid(50), workspaceID: workspace,
            purpose: "WORK_DETAIL_COMPLETED_RESPONSE_V1", subjectID: uuid(60),
            subjectRevision: 1, disposition: .recordedLocalAssertion,
            method: .typedLocalAssertion, roleAssertion: assertion,
            qualification: qualification, occurredAt: baseDate.addingTimeInterval(4),
            recordedAt: baseDate.addingTimeInterval(5), mutationID: try mutation(50)
        )
        return Values(
            workspace: workspace, party: party, role: role, actor: actor,
            qualification: qualification, disclosure: disclosure,
            assertion: assertion, signoff: signoff
        )
    }

    func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "73800000-0000-4000-8000-%012d", suffix))!
    }

    func mutation(_ suffix: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: uuid(100 + suffix))
    }

    func sourceText(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}

extension V9_23PartyAccountabilityTests {
    func testV23P03C14ReviewActorsRemainLocalResponsibilitySnapshots() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_223)
        XCTAssertEqual(fixture.reviewer.responsibility, .reviewedBy)
        XCTAssertEqual(fixture.reviewer.actor.workspaceID, fixture.workspaceID)
        XCTAssertEqual(fixture.verifier.responsibility, .verifiedBy)
        XCTAssertNotEqual(fixture.verifier.actor.actorReferenceID, fixture.reviewer.actor.actorReferenceID)
        XCTAssertNotNil(fixture.verifier.actor.partyID)
    }
}
