import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_38AccessibleDocumentTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private enum C24AccessibleDocumentTestFailure: Error, Equatable {
    case interrupted
}

private enum C24AccessibleDocumentTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c2400000-0000-4000-8000-%012x", slot))!
    }

    static func workspace(_ slot: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    static func digest(_ byte: Character = "a") -> String {
        String(repeating: byte, count: 64)
    }

    static func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    static func actor(
        workspaceID: WorkspaceID = workspace(),
        slot: Int = 300,
        responsibility: ResponsibilityKindV1 = .reviewedBy
    ) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(slot),
            workspaceID: workspaceID,
            displayName: "C24 local reviewer"
        )
        return try ActorSnapshotV1(
            snapshotID: id(slot + 1),
            workspaceID: workspaceID,
            actor: reference,
            responsibility: responsibility,
            displayNameAtTime: reference.displayName,
            capturedAt: fixedDate
        )
    }

    static func publication(locale: String = "en-US") throws -> AccessibleDocumentPublicationBindingV1 {
        try AccessibleDocumentPublicationBindingV1(
            snapshotSHA256: digest("a"),
            manifestID: "c24.manifest",
            manifestVersion: 1,
            manifestSHA256: digest("b"),
            localeIdentifier: locale,
            profileID: "c24.profile",
            profileRelease: 1,
            profileSHA256: digest("c"),
            brandProfileID: "c24.brand",
            brandProfileRelease: 1,
            brandProfileSHA256: digest("d")
        )
    }

    static func node(
        nodeID: String,
        role: AccessibleDocumentRoleV1,
        parentNodeID: String?,
        order: Int,
        headingLevel: Int? = nil,
        tableHeaderScope: AccessibleTableHeaderScopeV1? = nil,
        tableHeaderNodeIDs: [String] = [],
        localizedText: String? = nil,
        alternateText: String? = nil,
        alternateTextProvenance: AccessibleAlternateTextProvenanceV1? = nil,
        decorative: Bool = false,
        evidenceLinks: [AccessibleEvidenceLinkV1] = [],
        sensitivity: AccessibleDocumentSensitivityV1 = .customerSafe
    ) throws -> AccessibleDocumentNodeV1 {
        try AccessibleDocumentNodeV1(
            nodeID: nodeID,
            role: role,
            parentNodeID: parentNodeID,
            order: order,
            headingLevel: headingLevel,
            tableHeaderScope: tableHeaderScope,
            tableHeaderNodeIDs: tableHeaderNodeIDs,
            localizedText: localizedText,
            alternateText: alternateText,
            alternateTextProvenance: alternateTextProvenance,
            decorative: decorative,
            evidenceLinks: evidenceLinks,
            sensitivity: sensitivity
        )
    }

    static func tree(
        locale: String = "en-US",
        audience: ReportAudienceV1 = .internalUse,
        internalNode: Bool = false,
        evidenceMediaType: String = "application/json",
        pdfUAClaimed: Bool = false,
        wcagClaimed: Bool = false,
        legalCertificationClaimed: Bool = false,
        s10BrandReconciled: Bool = false
    ) throws -> AccessibleDocumentSemanticTreeV1 {
        let evidence = try AccessibleEvidenceLinkV1(
            evidenceID: "c24.evidence.001",
            evidenceSHA256: digest("e"),
            mediaType: evidenceMediaType
        )
        let longText = String(repeating: "Long accessible paragraph ", count: 60)
        let headingText = locale == "ar-XB" ? "عنوان التقرير" : "Report heading"
        let nodes = [
            try node(
                nodeID: "document",
                role: .document,
                parentNodeID: nil,
                order: 0,
                localizedText: locale == "ar-XB" ? "تقرير الحقل" : "Field report"
            ),
            try node(
                nodeID: "heading",
                role: .heading,
                parentNodeID: "document",
                order: 0,
                headingLevel: 1,
                localizedText: headingText
            ),
            try node(
                nodeID: "section",
                role: .section,
                parentNodeID: "document",
                order: 1,
                localizedText: locale == "ar-XB" ? "قسم النتائج" : "Findings"
            ),
            try node(
                nodeID: "paragraph",
                role: .paragraph,
                parentNodeID: "section",
                order: 0,
                localizedText: longText,
                evidenceLinks: [evidence]
            ),
            try node(
                nodeID: "table",
                role: .table,
                parentNodeID: "section",
                order: 1,
                localizedText: "Observed items"
            ),
            try node(
                nodeID: "row",
                role: .tableRow,
                parentNodeID: "table",
                order: 0
            ),
            try node(
                nodeID: "header",
                role: .tableHeader,
                parentNodeID: "row",
                order: 0,
                tableHeaderScope: .column,
                localizedText: "Item"
            ),
            try node(
                nodeID: "cell",
                role: .tableCell,
                parentNodeID: "row",
                order: 1,
                tableHeaderNodeIDs: ["header"],
                localizedText: "Recorded value"
            ),
            try node(
                nodeID: "figure",
                role: .figure,
                parentNodeID: "section",
                order: 2,
                localizedText: "Source figure",
                alternateText: "Source caption",
                alternateTextProvenance: .sourceCaption,
                sensitivity: internalNode ? .internalOnly : .customerSafe
            ),
            try node(
                nodeID: "decorative",
                role: .figure,
                parentNodeID: "section",
                order: 3,
                decorative: true
            ),
            try node(
                nodeID: "missingAlt",
                role: .figure,
                parentNodeID: "section",
                order: 4,
                alternateTextProvenance: .notProvided
            )
        ]
        return try AccessibleDocumentSemanticTreeV1(
            treeID: id(100),
            workspaceID: workspace(),
            audience: audience,
            publication: try publication(locale: locale),
            nodes: nodes,
            projectionVersion: "c24.semantic.v1",
            pdfUAClaimed: pdfUAClaimed,
            wcagClaimed: wcagClaimed,
            legalCertificationClaimed: legalCertificationClaimed,
            s10BrandReconciled: s10BrandReconciled
        )
    }

    static func replacing(
        nodeID: String,
        in nodes: [AccessibleDocumentNodeV1],
        with replacement: AccessibleDocumentNodeV1
    ) -> [AccessibleDocumentNodeV1] {
        nodes.map { $0.nodeID == nodeID ? replacement : $0 }
    }

    static func output(
        tree: AccessibleDocumentSemanticTreeV1
    ) throws -> AccessibleDocumentRenderOutputV1 {
        try AccessibleDocumentRenderOutputV1(
            bytes: Data("C24 deterministic render \(tree.treeSHA256)".utf8),
            mediaType: "application/pdf",
            rendererID: "existing-report-renderer",
            rendererVersion: "1"
        )
    }

    static func receipt(
        tree: AccessibleDocumentSemanticTreeV1,
        output: AccessibleDocumentRenderOutputV1,
        receiptID: UUID = id(200),
        scope: AccessibleDocumentAssessmentScopeV1 = .currentOutput,
        state: AccessibleDocumentAssessmentStateV1 = .internalPass,
        externalProof: [AccessibleEvidenceLinkV1] = [],
        limitations: [String] = ["C24 local deterministic assessment"],
        assessedAt: Date = fixedDate.addingTimeInterval(4),
        supersedesReceiptID: UUID? = nil,
        revision: UInt64 = 1,
        mutationSlot: Int = 201
    ) throws -> AccessibleDocumentAssessmentReceiptV1 {
        try AccessibleDocumentAssessmentReceiptV1(
            receiptID: receiptID,
            workspaceID: tree.workspaceID,
            tree: tree,
            outputSHA256: output.sha256,
            outputByteCount: Int64(output.bytes.count),
            outputMediaType: output.mediaType,
            rendererID: output.rendererID,
            rendererVersion: output.rendererVersion,
            assessmentToolID: "c24.assessor",
            assessmentToolVersion: "1",
            assessor: try actor(workspaceID: tree.workspaceID),
            scope: scope,
            state: state,
            externalProof: externalProof,
            limitations: limitations,
            assessedAt: assessedAt,
            supersedesReceiptID: supersedesReceiptID,
            revision: revision,
            mutationID: try mutation(mutationSlot)
        )
    }

    static func request(
        workspaceID: WorkspaceID,
        receiptID: UUID = id(200),
        state: AccessibleDocumentAssessmentStateV1 = .internalPass,
        supersedesReceiptID: UUID? = nil,
        revision: UInt64 = 1,
        mutationSlot: Int = 201
    ) throws -> AccessibleDocumentAssessmentRequestV1 {
        AccessibleDocumentAssessmentRequestV1(
            receiptID: receiptID,
            workspaceID: workspaceID,
            assessor: try actor(workspaceID: workspaceID),
            state: state,
            externalProof: [],
            limitations: ["C24 local deterministic assessment"],
            assessmentToolID: "c24.assessor",
            assessmentToolVersion: "1",
            assessedAt: fixedDate.addingTimeInterval(4),
            supersedesReceiptID: supersedesReceiptID,
            revision: revision,
            mutationID: try mutation(mutationSlot)
        )
    }

    static func lifecycleAdapter(
        tree: AccessibleDocumentSemanticTreeV1,
        output: AccessibleDocumentRenderOutputV1,
        counters: C24LifecycleCounters,
        failPoint: AccessibleDocumentInterruptionPointV1? = nil
    ) -> AccessibleDocumentLifecycleAdapterV1 {
        AccessibleDocumentLifecycleAdapterV1(
            operations: AccessibleDocumentLifecycleOperationsV1(
                derive: {
                    await counters.incrementDerive()
                    return tree
                },
                render: { _ in
                    await counters.incrementRender()
                    return output
                },
                accepted: { _, _ in
                    await counters.incrementAccepted()
                    return nil
                },
                append: { assessment, _ in
                    await counters.incrementAppend()
                    return assessment
                },
                interrupt: { point in
                    guard failPoint?.rawValue == point.rawValue else { return }
                    throw C24AccessibleDocumentTestFailure.interrupted
                }
            )
        )
    }

    static func decodedCorpus() throws -> C24AccessibleDocumentCorpus {
        let bundle = Bundle(for: V9_38AccessibleDocumentTests.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V22P03C24AccessibleDocumentCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V22/AccessibleDocuments"
            ) ?? bundle.url(
                forResource: "V22P03C24AccessibleDocumentCorpusV1",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(
            C24AccessibleDocumentCorpus.self,
            from: Data(contentsOf: url)
        )
    }
}

private struct C24AccessibleDocumentCorpus: Decodable {
    struct Selector: Decodable {
        let id: String
        let selector: String
        let focus: String
    }

    let schema: String
    let schemaVersion: Int
    let corpusID: String
    let cardID: String
    let records: Int
    let recordsSchemaVersion: Int
    let persistentSchemaVersion: Int
    let persistentModelCount: Int
    let evidenceIDs: [String]
    let evidenceSelectors: [Selector]
    let roles: [String]
    let sensitivities: [String]
    let alternateTextProvenances: [String]
    let tableHeaderScopes: [String]
    let assessmentStates: [String]
    let assessmentScopes: [String]
    let interruptionBoundaries: [String]
    let hostileCases: [String]
    let lifecycleConsumers: [String]
    let privacyExclusions: [String]
    let forbiddenClaims: [String]
    let derivedTreeOnly: Bool
    let externalCopyAvailabilityClaimed: Bool
    let runtimeFetchingAllowed: Bool
    let noVisualCertificationClaim: Bool
    let noSecondWriter: Bool
    let noSecondStore: Bool
}

private struct C24LifecycleCounterSnapshot: Sendable {
    let derive: Int
    let render: Int
    let accepted: Int
    let append: Int
}

private actor C24LifecycleCounters {
    private var deriveCount = 0
    private var renderCount = 0
    private var acceptedCount = 0
    private var appendCount = 0

    func incrementDerive() { deriveCount += 1 }
    func incrementRender() { renderCount += 1 }
    func incrementAccepted() { acceptedCount += 1 }
    func incrementAppend() { appendCount += 1 }

    func snapshot() -> C24LifecycleCounterSnapshot {
        C24LifecycleCounterSnapshot(
            derive: deriveCount,
            render: renderCount,
            accepted: acceptedCount,
            append: appendCount
        )
    }
}

private func c24AssertThrowsErrorAsync<T>(
    _ expression: @escaping () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        // The caller asserts the resulting state separately.
    }
}

final class V9_38AccessibleDocumentTests: XCTestCase {
    func testV23P03C24G01StableAccessibleDocumentTreeAndPublicationBinding() throws {
        let corpus = try C24AccessibleDocumentTestSupport.decodedCorpus()
        XCTAssertEqual(corpus.schema, "V22P03C24AccessibleDocumentCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C24")
        XCTAssertEqual(corpus.records, 22)
        XCTAssertEqual(corpus.recordsSchemaVersion, 22)
        XCTAssertEqual(corpus.persistentSchemaVersion, 23)
        XCTAssertEqual(corpus.persistentModelCount, 85)
        XCTAssertEqual(PersistentSchemaV23.versionIdentifier, Schema.Version(23, 0, 0))
        XCTAssertEqual(PersistentSchemaV23.models.count, corpus.persistentModelCount)
        XCTAssertEqual(PersistentSchemaV23.models.count, PersistentSchemaV22.models.count + 1)
        XCTAssertEqual(PersistentSchemaMigrationPlanV22.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV22.stages.count, 1)
        XCTAssertEqual(corpus.evidenceIDs, ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(corpus.evidenceSelectors.map(\.selector), corpus.evidenceIDs)
        XCTAssertEqual(corpus.roles, AccessibleDocumentRoleV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.sensitivities, AccessibleDocumentSensitivityV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.alternateTextProvenances, AccessibleAlternateTextProvenanceV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.tableHeaderScopes, AccessibleTableHeaderScopeV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.assessmentStates, AccessibleDocumentAssessmentStateV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.assessmentScopes, AccessibleDocumentAssessmentScopeV1.allCases.map(\.rawValue))
        XCTAssertTrue(corpus.derivedTreeOnly)
        XCTAssertFalse(corpus.externalCopyAvailabilityClaimed)
        XCTAssertFalse(corpus.runtimeFetchingAllowed)
        XCTAssertTrue(corpus.noVisualCertificationClaim)
        XCTAssertTrue(corpus.noSecondWriter)
        XCTAssertTrue(corpus.noSecondStore)
        XCTAssertEqual(corpus.interruptionBoundaries.count, 3)
        XCTAssertTrue(corpus.hostileCases.contains("duplicate-node-id"))
        XCTAssertTrue(corpus.hostileCases.contains("unsupported-brand-reconciliation"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("derived-tree rebuild after recovery"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("backup and restore identity"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("local report/search projection"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("localization and RTL presentation"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("governed delete and workspace Erase"))
        XCTAssertTrue(corpus.privacyExclusions.contains("external copy availability"))
        XCTAssertTrue(corpus.forbiddenClaims.contains("PDF/UA certification"))
        XCTAssertTrue(corpus.forbiddenClaims.contains("cloud or network durability"))

        let first = try C24AccessibleDocumentTestSupport.tree()
        let second = try C24AccessibleDocumentTestSupport.tree()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.treeSHA256, second.treeSHA256)
        XCTAssertEqual(first.publication.manifestID, "c24.manifest")
        XCTAssertEqual(first.nodes.map(\.nodeID), second.nodes.map(\.nodeID))

        let encoded = try AccessibleDocumentCanonicalCodecV1.encode(first)
        XCTAssertEqual(
            try AccessibleDocumentCanonicalCodecV1.decode(
                AccessibleDocumentSemanticTreeV1.self,
                from: encoded
            ),
            first
        )

        let firstOutput = try C24AccessibleDocumentTestSupport.output(tree: first)
        let secondOutput = try C24AccessibleDocumentTestSupport.output(tree: second)
        XCTAssertEqual(firstOutput, secondOutput)
        XCTAssertEqual(firstOutput.sha256, KernelCanonicalHashV1.sha256(firstOutput.bytes))
    }

    func testV23P03C24A01HeadingsTablesRTLLongDecorativeAndMissingAltAreExplicit() throws {
        let english = try C24AccessibleDocumentTestSupport.tree(locale: "en-US")
        let rtl = try C24AccessibleDocumentTestSupport.tree(locale: "ar-XB")
        XCTAssertNotEqual(english.treeSHA256, rtl.treeSHA256)
        XCTAssertEqual(english.nodes.map(\.nodeID), rtl.nodes.map(\.nodeID))
        XCTAssertEqual(english.publication.localeIdentifier, "en-US")
        XCTAssertEqual(rtl.publication.localeIdentifier, "ar-XB")

        let heading = try XCTUnwrap(english.nodes.first { $0.role == .heading })
        XCTAssertEqual(heading.headingLevel, 1)
        let table = try XCTUnwrap(english.nodes.first { $0.role == .table })
        XCTAssertEqual(table.parentNodeID, "section")
        let header = try XCTUnwrap(english.nodes.first { $0.role == .tableHeader })
        XCTAssertEqual(header.tableHeaderScope, .column)
        let cell = try XCTUnwrap(english.nodes.first { $0.role == .tableCell })
        XCTAssertEqual(cell.tableHeaderNodeIDs, [header.nodeID])

        let paragraph = try XCTUnwrap(english.nodes.first { $0.role == .paragraph })
        XCTAssertGreaterThan(try XCTUnwrap(paragraph.localizedText).utf8.count, 1_000)
        let figure = try XCTUnwrap(english.nodes.first { $0.nodeID == "figure" })
        XCTAssertEqual(figure.alternateTextProvenance, .sourceCaption)
        XCTAssertFalse(figure.decorative)
        let decorative = try XCTUnwrap(english.nodes.first { $0.nodeID == "decorative" })
        XCTAssertTrue(decorative.decorative)
        XCTAssertNil(decorative.alternateText)
        let missingAlt = try XCTUnwrap(english.nodes.first { $0.nodeID == "missingAlt" })
        XCTAssertNil(missingAlt.alternateText)
        XCTAssertEqual(missingAlt.alternateTextProvenance, .notProvided)

        let firstOutput = try C24AccessibleDocumentTestSupport.output(tree: english)
        let secondOutput = try C24AccessibleDocumentTestSupport.output(tree: english)
        XCTAssertEqual(firstOutput, secondOutput)

        let customerTree = try C24AccessibleDocumentTestSupport.tree(audience: .customerSafe)
        let customerOutput = try C24AccessibleDocumentTestSupport.output(tree: customerTree)
        let exactCustomerSafeLink = try XCTUnwrap(
            customerTree.nodes.first(where: { $0.nodeID == "paragraph" })?.evidenceLinks.first
        )
        XCTAssertEqual(exactCustomerSafeLink.mediaType, "application/json")
        let externallyProved = try C24AccessibleDocumentTestSupport.receipt(
            tree: customerTree,
            output: customerOutput,
            state: .externallyProved,
            externalProof: [exactCustomerSafeLink]
        )
        try externallyProved.validate(tree: customerTree)
        XCTAssertEqual(externallyProved.externalProof, [exactCustomerSafeLink])
    }

    func testV23P03C24H01CycleOrphanOrderHeaderPrivacyAndForgedClaimsFailClosed() throws {
        let base = try C24AccessibleDocumentTestSupport.tree()
        let exactCustomerSafeLink = try XCTUnwrap(
            base.nodes.first(where: { $0.nodeID == "paragraph" })?.evidenceLinks.first
        )

        let orphan = try C24AccessibleDocumentTestSupport.node(
            nodeID: "orphan",
            role: .paragraph,
            parentNodeID: "not-present",
            order: 0,
            localizedText: "Orphan"
        )
        XCTAssertThrowsError(try AccessibleDocumentSemanticTreeV1(
            treeID: C24AccessibleDocumentTestSupport.id(101),
            workspaceID: base.workspaceID,
            audience: base.audience,
            publication: base.publication,
            nodes: base.nodes + [orphan],
            projectionVersion: base.projectionVersion
        ))

        let cycle = try C24AccessibleDocumentTestSupport.node(
            nodeID: "cycle",
            role: .section,
            parentNodeID: "cycle",
            order: 0
        )
        XCTAssertThrowsError(try AccessibleDocumentSemanticTreeV1(
            treeID: C24AccessibleDocumentTestSupport.id(102),
            workspaceID: base.workspaceID,
            audience: base.audience,
            publication: base.publication,
            nodes: base.nodes + [cycle],
            projectionVersion: base.projectionVersion
        ))

        XCTAssertThrowsError(try AccessibleDocumentSemanticTreeV1(
            treeID: C24AccessibleDocumentTestSupport.id(105),
            workspaceID: base.workspaceID,
            audience: base.audience,
            publication: base.publication,
            nodes: base.nodes + [base.nodes[1]],
            projectionVersion: base.projectionVersion
        ))

        XCTAssertThrowsError(try C24AccessibleDocumentTestSupport.node(
            nodeID: "invalid-heading",
            role: .heading,
            parentNodeID: "document",
            order: 2,
            headingLevel: 7,
            localizedText: "Invalid heading"
        ))
        let misplacedHeader = try C24AccessibleDocumentTestSupport.node(
            nodeID: "misplaced-header",
            role: .tableHeader,
            parentNodeID: "paragraph",
            order: 0,
            tableHeaderScope: .column,
            localizedText: "Misplaced header"
        )
        XCTAssertThrowsError(try AccessibleDocumentSemanticTreeV1(
            treeID: C24AccessibleDocumentTestSupport.id(106),
            workspaceID: base.workspaceID,
            audience: base.audience,
            publication: base.publication,
            nodes: base.nodes + [misplacedHeader],
            projectionVersion: base.projectionVersion
        ))

        let badOrder = try C24AccessibleDocumentTestSupport.node(
            nodeID: "paragraph",
            role: .paragraph,
            parentNodeID: "section",
            order: 5,
            localizedText: "Gap"
        )
        XCTAssertThrowsError(try AccessibleDocumentSemanticTreeV1(
            treeID: C24AccessibleDocumentTestSupport.id(103),
            workspaceID: base.workspaceID,
            audience: base.audience,
            publication: base.publication,
            nodes: C24AccessibleDocumentTestSupport.replacing(
                nodeID: "paragraph", in: base.nodes, with: badOrder
            ),
            projectionVersion: base.projectionVersion
        ))

        let badHeaderCell = try C24AccessibleDocumentTestSupport.node(
            nodeID: "cell",
            role: .tableCell,
            parentNodeID: "row",
            order: 1,
            tableHeaderNodeIDs: ["paragraph"],
            localizedText: "Wrong header"
        )
        XCTAssertThrowsError(try AccessibleDocumentSemanticTreeV1(
            treeID: C24AccessibleDocumentTestSupport.id(104),
            workspaceID: base.workspaceID,
            audience: base.audience,
            publication: base.publication,
            nodes: C24AccessibleDocumentTestSupport.replacing(
                nodeID: "cell", in: base.nodes, with: badHeaderCell
            ),
            projectionVersion: base.projectionVersion
        ))

        XCTAssertThrowsError(try C24AccessibleDocumentTestSupport.node(
            nodeID: "invented",
            role: .figure,
            parentNodeID: "section",
            order: 5,
            alternateText: "Invented alt"
        ))

        let missingLink = try AccessibleEvidenceLinkV1(
            evidenceID: "c24.evidence.missing",
            evidenceSHA256: C24AccessibleDocumentTestSupport.digest("e"),
            mediaType: "application/json"
        )
        let baseOutput = try C24AccessibleDocumentTestSupport.output(tree: base)
        XCTAssertThrowsError(try C24AccessibleDocumentTestSupport.receipt(
            tree: base,
            output: baseOutput,
            state: .externallyProved,
            externalProof: [missingLink]
        ))

        let wrongSHA = try AccessibleEvidenceLinkV1(
            evidenceID: "c24.evidence.001",
            evidenceSHA256: C24AccessibleDocumentTestSupport.digest("f"),
            mediaType: "application/json"
        )
        XCTAssertThrowsError(try C24AccessibleDocumentTestSupport.receipt(
            tree: base,
            output: baseOutput,
            state: .externallyProved,
            externalProof: [wrongSHA]
        ))

        let wrongMediaType = try AccessibleEvidenceLinkV1(
            evidenceID: "c24.evidence.001",
            evidenceSHA256: C24AccessibleDocumentTestSupport.digest("e"),
            mediaType: "text/plain"
        )
        XCTAssertThrowsError(try C24AccessibleDocumentTestSupport.receipt(
            tree: base,
            output: baseOutput,
            state: .externallyProved,
            externalProof: [wrongMediaType]
        ))

        let duplicateLinkNode = try C24AccessibleDocumentTestSupport.node(
            nodeID: "section",
            role: .section,
            parentNodeID: "document",
            order: 1,
            localizedText: "Findings",
            evidenceLinks: [exactCustomerSafeLink]
        )
        let duplicateLinkTree = try AccessibleDocumentSemanticTreeV1(
            treeID: C24AccessibleDocumentTestSupport.id(107),
            workspaceID: base.workspaceID,
            audience: base.audience,
            publication: base.publication,
            nodes: C24AccessibleDocumentTestSupport.replacing(
                nodeID: "section", in: base.nodes, with: duplicateLinkNode
            ),
            projectionVersion: base.projectionVersion
        )
        let duplicateLinkOutput = try C24AccessibleDocumentTestSupport.output(tree: duplicateLinkTree)
        XCTAssertThrowsError(try C24AccessibleDocumentTestSupport.receipt(
            tree: duplicateLinkTree,
            output: duplicateLinkOutput,
            state: .externallyProved,
            externalProof: [exactCustomerSafeLink]
        ))
        XCTAssertThrowsError(try C24AccessibleDocumentTestSupport.receipt(
            tree: base,
            output: baseOutput,
            state: .externallyProved,
            externalProof: [exactCustomerSafeLink, exactCustomerSafeLink]
        ))

        let paragraphWithoutLink = try C24AccessibleDocumentTestSupport.node(
            nodeID: "paragraph",
            role: .paragraph,
            parentNodeID: "section",
            order: 0,
            localizedText: String(repeating: "Long accessible paragraph ", count: 60)
        )
        let internalOnlyFigure = try C24AccessibleDocumentTestSupport.node(
            nodeID: "figure",
            role: .figure,
            parentNodeID: "section",
            order: 2,
            localizedText: "Source figure",
            alternateText: "Source caption",
            alternateTextProvenance: .sourceCaption,
            evidenceLinks: [exactCustomerSafeLink],
            sensitivity: .internalOnly
        )
        let internalOnlyLinkTree = try AccessibleDocumentSemanticTreeV1(
            treeID: C24AccessibleDocumentTestSupport.id(108),
            workspaceID: base.workspaceID,
            audience: base.audience,
            publication: base.publication,
            nodes: C24AccessibleDocumentTestSupport.replacing(
                nodeID: "figure",
                in: C24AccessibleDocumentTestSupport.replacing(
                    nodeID: "paragraph", in: base.nodes, with: paragraphWithoutLink
                ),
                with: internalOnlyFigure
            ),
            projectionVersion: base.projectionVersion
        )
        let internalOnlyLinkOutput = try C24AccessibleDocumentTestSupport.output(tree: internalOnlyLinkTree)
        XCTAssertThrowsError(try C24AccessibleDocumentTestSupport.receipt(
            tree: internalOnlyLinkTree,
            output: internalOnlyLinkOutput,
            state: .externallyProved,
            externalProof: [exactCustomerSafeLink]
        ))
        XCTAssertThrowsError(try C24AccessibleDocumentTestSupport.tree(
            audience: .customerSafe,
            internalNode: true
        ))
        let customerSafeInput = AccessibleDocumentTreeBuildInputV1(
            workspaceID: base.workspaceID,
            audience: .customerSafe,
            publication: base.publication,
            nodes: base.nodes,
            projectionVersion: base.projectionVersion
        )
        let projected = try AccessibleDocumentAudienceProjectorV1.project(customerSafeInput)
        XCTAssertEqual(projected.audience, .customerSafe)
        XCTAssertTrue(projected.nodes.allSatisfy { $0.sensitivity == .customerSafe })
        XCTAssertEqual(projected.nodes.map(\.nodeID), base.nodes.map(\.nodeID))
        XCTAssertThrowsError(try C24AccessibleDocumentTestSupport.tree(pdfUAClaimed: true))
        XCTAssertThrowsError(try C24AccessibleDocumentTestSupport.tree(wcagClaimed: true))
        XCTAssertThrowsError(try C24AccessibleDocumentTestSupport.tree(legalCertificationClaimed: true))
        XCTAssertThrowsError(try C24AccessibleDocumentTestSupport.tree(s10BrandReconciled: true))

        var forged = try JSONSerialization.jsonObject(
            with: AccessibleDocumentCanonicalCodecV1.encode(base)
        ) as! [String: Any]
        forged["treeSHA256"] = C24AccessibleDocumentTestSupport.digest("b")
        let forgedData = try JSONSerialization.data(
            withJSONObject: forged,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        XCTAssertThrowsError(try AccessibleDocumentCanonicalCodecV1.decode(
            AccessibleDocumentSemanticTreeV1.self,
            from: forgedData
        ))

        let output = try C24AccessibleDocumentTestSupport.output(tree: base)
        let receipt = try C24AccessibleDocumentTestSupport.receipt(tree: base, output: output)
        XCTAssertThrowsError(try receipt.validateOutput(Data("wrong bytes".utf8)))
        let rtl = try C24AccessibleDocumentTestSupport.tree(locale: "ar-XB")
        XCTAssertThrowsError(try receipt.validate(tree: rtl))
    }

    func testV23P03C24I01EveryRenderAssessmentInterruptionLeavesZeroOrOneState() async throws {
        let tree = try C24AccessibleDocumentTestSupport.tree()
        let output = try C24AccessibleDocumentTestSupport.output(tree: tree)
        let request = try C24AccessibleDocumentTestSupport.request(workspaceID: tree.workspaceID)

        let points: [AccessibleDocumentInterruptionPointV1] = [
            .afterTreeBeforeRender,
            .afterRenderBeforeAssessment,
            .afterAssessmentBeforeReturn
        ]
        for point in points {
            let counters = C24LifecycleCounters()
            let adapter = C24AccessibleDocumentTestSupport.lifecycleAdapter(
                tree: tree,
                output: output,
                counters: counters,
                failPoint: point
            )
            let coordinator = AccessibleDocumentCoordinatorV1(
                treeBuilder: adapter,
                renderer: adapter,
                writer: adapter
            )
            if point.rawValue == AccessibleDocumentInterruptionPointV1.afterAssessmentBeforeReturn.rawValue {
                await c24AssertThrowsErrorAsync {
                    _ = try await coordinator.assess(request)
                }
            } else {
                await c24AssertThrowsErrorAsync {
                    _ = try await coordinator.deriveAndRender()
                }
            }
            let snapshot = await counters.snapshot()
            switch point {
            case .afterTreeBeforeRender:
                XCTAssertEqual(snapshot.derive, 1)
                XCTAssertEqual(snapshot.render, 0)
                XCTAssertEqual(snapshot.append, 0)
            case .afterRenderBeforeAssessment:
                XCTAssertEqual(snapshot.derive, 1)
                XCTAssertEqual(snapshot.render, 1)
                XCTAssertEqual(snapshot.append, 0)
            case .afterAssessmentBeforeReturn:
                XCTAssertEqual(snapshot.derive, 1)
                XCTAssertEqual(snapshot.render, 1)
                XCTAssertEqual(snapshot.append, 1)
            }
        }

        let retryCounters = C24LifecycleCounters()
        let retryAdapter = C24AccessibleDocumentTestSupport.lifecycleAdapter(
            tree: tree,
            output: output,
            counters: retryCounters
        )
        let retryCoordinator = AccessibleDocumentCoordinatorV1(
            treeBuilder: retryAdapter,
            renderer: retryAdapter,
            writer: retryAdapter
        )
        let first = try await retryCoordinator.assess(request)
        let second = try await retryCoordinator.assess(request)
        XCTAssertEqual(first, second)
        let retrySnapshot = await retryCounters.snapshot()
        XCTAssertEqual(retrySnapshot.append, 2)
    }

    func testV23P03C24R01CanonicalRebuildAssessmentSuccessorAndV23Retention() throws {
        let corpus = try C24AccessibleDocumentTestSupport.decodedCorpus()
        XCTAssertTrue(corpus.lifecycleConsumers.contains("backup and restore identity"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("local report/search projection"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("localization and RTL presentation"))
        XCTAssertTrue(corpus.lifecycleConsumers.contains("governed delete and workspace Erase"))
        let tree = try C24AccessibleDocumentTestSupport.tree()
        let rebuildInput = AccessibleDocumentTreeBuildInputV1(
            workspaceID: tree.workspaceID,
            audience: tree.audience,
            publication: tree.publication,
            nodes: tree.nodes,
            projectionVersion: tree.projectionVersion
        )
        let rebuilt = try AccessibleDocumentSemanticTreeResolverV1.rebuild(rebuildInput)
        let rebuiltAgain = try AccessibleDocumentSemanticTreeResolverV1.rebuild(rebuildInput)
        XCTAssertEqual(rebuilt, rebuiltAgain)
        XCTAssertEqual(rebuilt.nodes, tree.nodes)
        XCTAssertEqual(rebuilt.publication, tree.publication)
        XCTAssertNotEqual(rebuilt.treeID, tree.treeID)

        let rebuiltOutput = try C24AccessibleDocumentTestSupport.output(tree: rebuilt)
        let rebuiltReceipt = try C24AccessibleDocumentTestSupport.receipt(
            tree: rebuilt,
            output: rebuiltOutput,
            receiptID: C24AccessibleDocumentTestSupport.id(198),
            mutationSlot: 199
        )
        let resolutionRequest = try AccessibleDocumentSemanticTreeResolutionRequestV1(receipt: rebuiltReceipt)
        try resolutionRequest.validate(rebuilt)
        try rebuiltReceipt.validate(tree: rebuilt)

        let output = try C24AccessibleDocumentTestSupport.output(tree: tree)
        let receipt = try C24AccessibleDocumentTestSupport.receipt(tree: tree, output: output)
        let successor = try C24AccessibleDocumentTestSupport.receipt(
            tree: tree,
            output: output,
            receiptID: C24AccessibleDocumentTestSupport.id(202),
            assessedAt: C24AccessibleDocumentTestSupport.fixedDate.addingTimeInterval(5),
            supersedesReceiptID: receipt.receiptID,
            revision: 2,
            mutationSlot: 203
        )
        try successor.validateSuccessor(of: receipt, tree: tree)
        XCTAssertThrowsError(try receipt.validateSuccessor(of: successor, tree: tree))

        let historic = try C24AccessibleDocumentTestSupport.receipt(
            tree: tree,
            output: output,
            receiptID: C24AccessibleDocumentTestSupport.id(204),
            scope: .historicSource,
            state: .incomplete,
            limitations: [AccessibleDocumentAssessmentReceiptV1.historicSourceLimitation],
            assessedAt: C24AccessibleDocumentTestSupport.fixedDate.addingTimeInterval(6),
            mutationSlot: 205
        )
        try historic.validate(tree: tree)
        XCTAssertEqual(historic.scope, .historicSource)
        XCTAssertEqual(historic.state, .incomplete)
        let reassessed = try C24AccessibleDocumentTestSupport.receipt(
            tree: tree,
            output: output,
            receiptID: C24AccessibleDocumentTestSupport.id(206),
            scope: .currentOutput,
            state: .internalPass,
            assessedAt: C24AccessibleDocumentTestSupport.fixedDate.addingTimeInterval(7),
            supersedesReceiptID: historic.receiptID,
            revision: 2,
            mutationSlot: 207
        )
        try reassessed.validateSuccessor(of: historic, tree: tree)
        XCTAssertEqual(reassessed.scope, .currentOutput)

        let row = try AccessibleDocumentAssessmentReceiptRow(receipt, tree: tree)
        XCTAssertEqual(try row.value(tree: tree), receipt)
        row.receiptSHA256 = C24AccessibleDocumentTestSupport.digest("z")
        XCTAssertThrowsError(try row.value(tree: tree))
        let encoded = try AccessibleDocumentCanonicalCodecV1.encode(receipt)
        XCTAssertEqual(
            try AccessibleDocumentCanonicalCodecV1.decode(
                AccessibleDocumentAssessmentReceiptV1.self,
                from: encoded
            ),
            receipt
        )
        let backupRecord = V23BackupAccessibleDocumentAssessmentRecordV1(
            id: historic.receiptID,
            workspaceID: historic.workspaceID.rawValue,
            revision: historic.revision,
            canonicalData: try AccessibleDocumentCanonicalCodecV1.encode(historic)
        )
        XCTAssertEqual(
            try AccessibleDocumentCanonicalCodecV1.decode(
                AccessibleDocumentAssessmentReceiptV1.self,
                from: backupRecord.canonicalData
            ),
            historic
        )
        XCTAssertEqual(backupRecord.id, historic.receiptID)
        XCTAssertEqual(backupRecord.workspaceID, historic.workspaceID.rawValue)
        try V23AccessibleDocumentImportBoundaryV1.validate(persistent: 23, records: 22)
        XCTAssertThrowsError(try V23AccessibleDocumentImportBoundaryV1.validate(persistent: 22, records: 22))

        XCTAssertEqual(
            AccessibleDocumentRecoveryV1.disposition(hasAcceptedAssessment: true, hasDerivedTree: true),
            "REBUILD_DERIVED_TREE_FROM_SNAPSHOT_AND_ACCEPTED_RECEIPT"
        )
        XCTAssertEqual(
            AccessibleDocumentRecoveryV1.disposition(hasAcceptedAssessment: false, hasDerivedTree: true),
            "DROP_UNACCEPTED_DERIVED_TREE"
        )
        XCTAssertEqual(
            AccessibleDocumentRecoveryV1.disposition(hasAcceptedAssessment: false, hasDerivedTree: false),
            "NO_EFFECT"
        )
        XCTAssertEqual(AccessibleDocumentLifecycleV1.persistentFamilies, ["AccessibleDocumentAssessmentReceiptV1"])
        XCTAssertEqual(AccessibleDocumentLifecycleV1.semanticTreePersistence, "DERIVED_ONLY")
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.wcagClaimed)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.legalCertificationClaimed)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.s10BrandReconciled)
    }
}
extension V9_38AccessibleDocumentTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleV1.persistentFamilies.count, 2)
        XCTAssertEqual(SurveyDefinitionLifecycleV1.quarantinePersistence, "DERIVED_ONLY")
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .inspection).mayClaimReleaseToService)
    }
}
extension V9_38AccessibleDocumentTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

private actor V30GlobalizedAccessibleDocumentProbe: AccessibleDocumentGlobalizedRenderingV1 {
    private var receivedTree: AccessibleDocumentSemanticTreeV1?
    private var receivedRequest: AccessibleDocumentGlobalizedRenderRequestV1?
    private let returnsMismatchedLanguage: Bool

    init(returnsMismatchedLanguage: Bool = false) {
        self.returnsMismatchedLanguage = returnsMismatchedLanguage
    }

    func renderGlobalized(
        tree: AccessibleDocumentSemanticTreeV1,
        request: AccessibleDocumentGlobalizedRenderRequestV1
    ) async throws -> AccessibleDocumentGlobalizedRenderOutputV1 {
        receivedTree = tree
        receivedRequest = request
        let bytes = Data("V30 globalized accessible document".utf8)
        let output = try AccessibleDocumentRenderOutputV1(
            bytes: bytes,
            mediaType: "application/pdf",
            rendererID: GlobalizedDocumentRenderReceiptV1.rendererID,
            rendererVersion: GlobalizedDocumentRenderReceiptV1.rendererVersion
        )
        let receiptLanguage: ReportLanguageSelectionV1
        if returnsMismatchedLanguage {
            receiptLanguage = try ReportLanguageSelectionV1(
                requestedLanguage: try AppLanguageTagV1("es"),
                effectiveLanguage: try AppLanguageTagV1("es"),
                fallback: .exact
            )
        } else {
            receiptLanguage = request.documentRequest.language
        }
        let receipt = GlobalizedDocumentRenderReceiptV1(
            rendererID: GlobalizedDocumentRenderReceiptV1.rendererID,
            rendererVersion: GlobalizedDocumentRenderReceiptV1.rendererVersion,
            sourceSHA256: tree.treeSHA256,
            sourceCreatedAtMilliseconds: Int64((request.sourceCreatedAt.timeIntervalSince1970 * 1_000).rounded()),
            sourceContentSHA256: String(repeating: "f", count: 64),
            paper: LocalePaperLayoutV1(paperSize: request.documentRequest.paperSize, widthPoints: 612, heightPoints: 792),
            language: receiptLanguage,
            formatting: request.documentRequest.formatting,
            orderedSemanticIDs: try tree.depthFirstReadingOrder().map(\.nodeID),
            fonts: [GlobalizedDocumentFontProvenanceV1(postScriptName: "TestFont", versionName: "1", fontFileSHA256: String(repeating: "e", count: 64), os2FsType: 0, fileByteCount: 1, embedding: .outlineSubset)],
            operatingSystemBuild: "test-os-build",
            outputSHA256: output.sha256,
            outputByteCount: Int64(bytes.count),
            nativeFontEmbeddingObserved: true,
            nativeToUnicodeObserved: true,
            nativeColorGlyphImagesObserved: false,
            pendingExternalQualification: true
        )
        return try AccessibleDocumentGlobalizedRenderOutputV1(output: output, documentReceipt: receipt)
    }

    func snapshot() -> (AccessibleDocumentSemanticTreeV1?, AccessibleDocumentGlobalizedRenderRequestV1?) {
        (receivedTree, receivedRequest)
    }
}

private actor V30GlobalizedAssessmentStore {
    private var acceptedReceipt: AccessibleDocumentAssessmentReceiptV1?
    private var appendCount = 0

    func accepted(_ value: AccessibleDocumentAssessmentReceiptV1) -> AccessibleDocumentAssessmentReceiptV1? {
        acceptedReceipt == value ? acceptedReceipt : nil
    }

    func append(_ value: AccessibleDocumentAssessmentReceiptV1) -> AccessibleDocumentAssessmentReceiptV1 {
        appendCount += 1
        acceptedReceipt = value
        return value
    }

    func snapshot() -> Int { appendCount }
}

extension V9_38AccessibleDocumentTests {
    func testV30P03C04GlobalizedLifecycleUsesDepthFirstTreeAndExplicitProvenance() async throws {
        let evidenceBytes = Data("exact source image bytes".utf8)
        let evidence = try AccessibleEvidenceLinkV1(
            evidenceID: "v30.image.evidence",
            evidenceSHA256: KernelCanonicalHashV1.sha256(evidenceBytes),
            mediaType: "image/jpeg"
        )
        let tree = try AccessibleDocumentSemanticTreeV1(
            treeID: C24AccessibleDocumentTestSupport.id(401),
            workspaceID: C24AccessibleDocumentTestSupport.workspace(401),
            audience: .internalUse,
            publication: try C24AccessibleDocumentTestSupport.publication(),
            nodes: [
                try C24AccessibleDocumentTestSupport.node(nodeID: "cell", role: .tableCell, parentNodeID: "row", order: 1, tableHeaderNodeIDs: ["header"], localizedText: "Value"),
                try C24AccessibleDocumentTestSupport.node(nodeID: "document", role: .document, parentNodeID: nil, order: 0, localizedText: "Document"),
                try C24AccessibleDocumentTestSupport.node(nodeID: "figure", role: .figure, parentNodeID: "section", order: 2, localizedText: "Source figure text", alternateText: "Authored image description", alternateTextProvenance: .authoredForSource, evidenceLinks: [evidence]),
                try C24AccessibleDocumentTestSupport.node(nodeID: "header", role: .tableHeader, parentNodeID: "row", order: 0, tableHeaderScope: .column, localizedText: "Name"),
                try C24AccessibleDocumentTestSupport.node(nodeID: "heading", role: .heading, parentNodeID: "document", order: 0, headingLevel: 1, localizedText: "Heading"),
                try C24AccessibleDocumentTestSupport.node(nodeID: "paragraph", role: .paragraph, parentNodeID: "section", order: 0, localizedText: "Comment", evidenceLinks: [evidence]),
                try C24AccessibleDocumentTestSupport.node(nodeID: "row", role: .tableRow, parentNodeID: "table", order: 0),
                try C24AccessibleDocumentTestSupport.node(nodeID: "section", role: .section, parentNodeID: "document", order: 1, localizedText: "Status"),
                try C24AccessibleDocumentTestSupport.node(nodeID: "table", role: .table, parentNodeID: "section", order: 1, localizedText: "Table")
            ],
            projectionVersion: "v30.globalized.accessible.v1"
        )
        let depthFirst = try tree.depthFirstReadingOrder().map(\.nodeID)
        XCTAssertEqual(depthFirst, ["document", "heading", "section", "paragraph", "table", "row", "header", "cell", "figure"])
        XCTAssertNotEqual(depthFirst, tree.nodes.map(\.nodeID))

        let elements = try GlobalizedAccessibleDocumentTreeProjectionV1.elements(
            tree: tree,
            imageDataByEvidenceID: [evidence.evidenceID: evidenceBytes]
        )
        XCTAssertEqual(Array(elements.map(\.semanticID).prefix(4)), ["document", "heading", "section", "paragraph"])
        let evidenceLink = try XCTUnwrap(elements.first { $0.role == .evidenceLink })
        XCTAssertEqual(evidenceLink.parentSemanticID, "paragraph")
        XCTAssertEqual(evidenceLink.evidenceID, evidence.evidenceID)
        XCTAssertEqual(evidenceLink.evidenceSHA256, evidence.evidenceSHA256)
        XCTAssertTrue(evidenceLink.semanticID.hasPrefix("link.") && evidenceLink.semanticID.utf8.count <= 128)
        let header = try XCTUnwrap(elements.first { $0.semanticID == "header" })
        XCTAssertEqual(header.parentSemanticID, "row")
        XCTAssertEqual(header.tableHeaderScope, .column)
        let cell = try XCTUnwrap(elements.first { $0.semanticID == "cell" })
        XCTAssertEqual(cell.tableHeaderSemanticIDs, ["header"])
        let figure = try XCTUnwrap(elements.first { $0.semanticID == "figure" })
        XCTAssertEqual(figure.imageData, evidenceBytes)
        XCTAssertEqual(figure.evidenceSHA256, evidence.evidenceSHA256)
        XCTAssertEqual(figure.alternateText, "Authored image description")
        XCTAssertEqual(figure.alternateTextProvenance, .authoredForSource)
        XCTAssertThrowsError(try GlobalizedAccessibleDocumentTreeProjectionV1.elements(tree: tree, imageDataByEvidenceID: [:]))
        XCTAssertThrowsError(try GlobalizedAccessibleDocumentTreeProjectionV1.elements(tree: tree, imageDataByEvidenceID: [evidence.evidenceID: Data("wrong".utf8)]))

        let secondEvidenceBytes = Data("second exact source image bytes".utf8)
        let secondEvidence = try AccessibleEvidenceLinkV1(
            evidenceID: "v30.image.additional",
            evidenceSHA256: KernelCanonicalHashV1.sha256(secondEvidenceBytes),
            mediaType: "image/jpeg"
        )
        let multiFigure = try C24AccessibleDocumentTestSupport.node(
            nodeID: "figure", role: .figure, parentNodeID: "section", order: 2,
            localizedText: "Source figure text",
            alternateText: "Authored image description",
            alternateTextProvenance: .authoredForSource,
            evidenceLinks: [evidence, secondEvidence]
        )
        let multiEvidenceTree = try AccessibleDocumentSemanticTreeV1(
            treeID: C24AccessibleDocumentTestSupport.id(403),
            workspaceID: tree.workspaceID,
            audience: tree.audience,
            publication: tree.publication,
            nodes: C24AccessibleDocumentTestSupport.replacing(nodeID: "figure", in: tree.nodes, with: multiFigure),
            projectionVersion: tree.projectionVersion
        )
        let multiElements = try GlobalizedAccessibleDocumentTreeProjectionV1.elements(
            tree: multiEvidenceTree,
            imageDataByEvidenceID: [
                evidence.evidenceID: evidenceBytes,
                secondEvidence.evidenceID: secondEvidenceBytes
            ]
        )
        let figureGroup = try XCTUnwrap(multiElements.first { $0.semanticID == "figure" })
        XCTAssertNil(figureGroup.imageData)
        XCTAssertNil(figureGroup.evidenceID)
        XCTAssertEqual(figureGroup.text, "Source figure text")
        XCTAssertEqual(figureGroup.alternateText, "Authored image description")
        XCTAssertEqual(figureGroup.alternateTextProvenance, .authoredForSource)
        XCTAssertEqual(multiElements.compactMap(\.text).filter { $0 == "Source figure text" }, ["Source figure text"])
        XCTAssertEqual(multiElements.compactMap(\.alternateText), ["Authored image description"])
        let imageChildren = multiElements.filter { $0.parentSemanticID == "figure" && $0.role == .figure }
        XCTAssertEqual(imageChildren.count, 2)
        XCTAssertEqual(imageChildren.map(\.evidenceID), multiFigure.evidenceLinks.map(\.evidenceID))
        XCTAssertEqual(imageChildren.compactMap(\.imageData), multiFigure.evidenceLinks.map { link in
            link.evidenceID == evidence.evidenceID ? evidenceBytes : secondEvidenceBytes
        })
        XCTAssertTrue(imageChildren.allSatisfy { $0.alternateText == nil && $0.alternateTextProvenance == .notProvided })
        XCTAssertTrue(imageChildren.allSatisfy { $0.semanticID.hasPrefix("image.") && $0.semanticID.utf8.count <= 256 })
        XCTAssertThrowsError(try GlobalizedAccessibleDocumentTreeProjectionV1.elements(
            tree: multiEvidenceTree,
            imageDataByEvidenceID: [evidence.evidenceID: evidenceBytes]
        ))
        XCTAssertThrowsError(try GlobalizedAccessibleDocumentTreeProjectionV1.elements(
            tree: multiEvidenceTree,
            imageDataByEvidenceID: [evidence.evidenceID: evidenceBytes, secondEvidence.evidenceID: Data("mismatch".utf8)]
        ))

        let decorativeMultiFigure = try C24AccessibleDocumentTestSupport.node(
            nodeID: "figure", role: .figure, parentNodeID: "section", order: 2,
            decorative: true, evidenceLinks: [evidence, secondEvidence]
        )
        let decorativeMultiTree = try AccessibleDocumentSemanticTreeV1(
            treeID: C24AccessibleDocumentTestSupport.id(404), workspaceID: tree.workspaceID,
            audience: tree.audience, publication: tree.publication,
            nodes: C24AccessibleDocumentTestSupport.replacing(nodeID: "figure", in: tree.nodes, with: decorativeMultiFigure),
            projectionVersion: tree.projectionVersion
        )
        let decorativeElements = try GlobalizedAccessibleDocumentTreeProjectionV1.elements(
            tree: decorativeMultiTree,
            imageDataByEvidenceID: [evidence.evidenceID: evidenceBytes, secondEvidence.evidenceID: secondEvidenceBytes]
        )
        let decorativeGroup = try XCTUnwrap(decorativeElements.first { $0.semanticID == "figure" })
        XCTAssertTrue(decorativeGroup.decorative)
        XCTAssertNil(decorativeGroup.alternateTextProvenance)
        let decorativeChildren = decorativeElements.filter { $0.parentSemanticID == "figure" && $0.role == .figure }
        XCTAssertEqual(decorativeChildren.map(\.evidenceID), decorativeMultiFigure.evidenceLinks.map(\.evidenceID))
        XCTAssertTrue(decorativeChildren.allSatisfy { $0.decorative && $0.alternateText == nil && $0.alternateTextProvenance == nil })

        let longNodeID = String(repeating: "n", count: 120)
        let longEvidenceID = String(repeating: "e", count: 120)
        let longEvidence = try AccessibleEvidenceLinkV1(
            evidenceID: longEvidenceID, evidenceSHA256: KernelCanonicalHashV1.sha256(Data("long evidence".utf8)), mediaType: "application/json"
        )
        let longParagraph = try C24AccessibleDocumentTestSupport.node(
            nodeID: longNodeID, role: .paragraph, parentNodeID: "section", order: 0,
            localizedText: "Bounded evidence link", evidenceLinks: [longEvidence]
        )
        let longIdentityTree = try AccessibleDocumentSemanticTreeV1(
            treeID: C24AccessibleDocumentTestSupport.id(405), workspaceID: tree.workspaceID,
            audience: tree.audience, publication: tree.publication,
            nodes: C24AccessibleDocumentTestSupport.replacing(nodeID: "paragraph", in: tree.nodes, with: longParagraph),
            projectionVersion: tree.projectionVersion
        )
        let longIdentityElements = try GlobalizedAccessibleDocumentTreeProjectionV1.elements(
            tree: longIdentityTree, imageDataByEvidenceID: [evidence.evidenceID: evidenceBytes]
        )
        let longEvidenceLink = try XCTUnwrap(longIdentityElements.first { $0.evidenceID == longEvidenceID })
        XCTAssertEqual(longEvidenceLink.parentSemanticID, longNodeID)
        XCTAssertTrue(longEvidenceLink.semanticID.hasPrefix("link.") && longEvidenceLink.semanticID.utf8.count <= 128)

        let request = try AccessibleDocumentGlobalizedRenderRequestV1(
            sourceCreatedAt: C24AccessibleDocumentTestSupport.fixedDate,
            documentRequest: try GlobalizedDocumentRenderRequestV1(
                language: ReportLanguageSelectionV1(requestedLanguage: .english, effectiveLanguage: .english, fallback: .exact),
                formatting: FormattingLocaleProfileV1(localeIdentifier: "en-US", ianaTimeZoneIdentifier: "Etc/UTC", calendar: .gregorian, numberingSystem: .latin, units: .usCustomary),
                paperSize: .usLetter
            ),
            imageDataByEvidenceID: [evidence.evidenceID: evidenceBytes]
        )
        let probe = V30GlobalizedAccessibleDocumentProbe()
        let assessmentStore = V30GlobalizedAssessmentStore()
        let existingOutput = try C24AccessibleDocumentTestSupport.output(tree: tree)
        let adapter = AccessibleDocumentLifecycleAdapterV1(
            operations: AccessibleDocumentLifecycleOperationsV1(
                derive: { tree }, render: { _ in existingOutput },
                accepted: { assessment, _ in await assessmentStore.accepted(assessment) },
                append: { assessment, _ in await assessmentStore.append(assessment) }
            ),
            globalizedRenderer: probe
        )
        let coordinator = AccessibleDocumentCoordinatorV1(treeBuilder: adapter, renderer: adapter, writer: adapter, globalizedRenderer: adapter)
        let (derivedTree, rendered) = try await coordinator.deriveAndRenderGlobalized(request)
        XCTAssertEqual(derivedTree, tree)
        XCTAssertEqual(rendered.documentReceipt.sourceSHA256, tree.treeSHA256)
        XCTAssertEqual(rendered.documentReceipt.language, request.documentRequest.language)
        XCTAssertEqual(rendered.documentReceipt.formatting, request.documentRequest.formatting)
        XCTAssertTrue(rendered.documentReceipt.pendingExternalQualification)
        let (receivedTree, receivedRequest) = await probe.snapshot()
        XCTAssertEqual(receivedTree, tree)
        XCTAssertEqual(receivedRequest?.sourceCreatedAt, request.sourceCreatedAt)
        XCTAssertEqual(receivedRequest?.imageDataByEvidenceID, request.imageDataByEvidenceID)

        let assessmentRequest = try C24AccessibleDocumentTestSupport.request(
            workspaceID: tree.workspaceID,
            receiptID: C24AccessibleDocumentTestSupport.id(402),
            mutationSlot: 402
        )
        let firstAssessment = try await coordinator.assessGlobalized(assessmentRequest, renderRequest: request)
        let replayedAssessment = try await coordinator.assessGlobalized(assessmentRequest, renderRequest: request)
        XCTAssertEqual(firstAssessment, replayedAssessment)
        XCTAssertEqual(firstAssessment.outputSHA256, rendered.output.sha256)
        let appendCount = await assessmentStore.snapshot()
        XCTAssertEqual(appendCount, 1)

        let mismatchedProbe = V30GlobalizedAccessibleDocumentProbe(returnsMismatchedLanguage: true)
        let mismatchedAdapter = AccessibleDocumentLifecycleAdapterV1(
            operations: AccessibleDocumentLifecycleOperationsV1(
                derive: { tree }, render: { _ in existingOutput }, accepted: { _, _ in nil }, append: { assessment, _ in assessment }
            ),
            globalizedRenderer: mismatchedProbe
        )
        let mismatchedCoordinator = AccessibleDocumentCoordinatorV1(
            treeBuilder: mismatchedAdapter,
            renderer: mismatchedAdapter,
            writer: mismatchedAdapter,
            globalizedRenderer: mismatchedAdapter
        )
        await c24AssertThrowsErrorAsync {
            _ = try await mismatchedCoordinator.deriveAndRenderGlobalized(request)
        }
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_38AccessibleDocumentTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_38AccessibleDocumentTests_swift_Tests: XCTestCase {
    func testC47V938AccessibleDocumentTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_38AccessibleDocumentTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_38AccessibleDocumentTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_38AccessibleDocumentTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_38AccessibleDocumentTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_38AccessibleDocumentTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_38AccessibleDocumentTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_38AccessibleDocumentTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertFalse(ActivityContractPersistenceEnrollmentV2.completionClaimsCommissioningComplianceApprovalOrCertification)
        XCTAssertEqual(Set(ActivityContractPersistenceEnrollmentV2.nonpersistentFamilies).count, 3)
    }
}

private final class C48PortableReviewV938AccessibleDocumentTests: XCTestCase {
    func testC48AccessibleDocumentsSpeakOnlyDerivedUnverifiedMetadata() {
        XCTAssertTrue(C48PortableReviewAccessibleDocumentBoundaryV1.spokenProjectionIsDerivedMetadataOnly)
        XCTAssertTrue(C48PortableReviewAccessibleDocumentBoundaryV1.selfAssertedOriginMayBeSpoken)
        XCTAssertFalse(C48PortableReviewAccessibleDocumentBoundaryV1.capabilityBytesSpoken)
        XCTAssertFalse(C48PortableReviewAccessibleDocumentPersistenceBoundaryV1.rawRequestResponseBytesPersisted)
    }
}
private final class C49WorkResourceAccessibleDocumentBoundaryTests: XCTestCase {
    func testAccessibleDocumentsCanDistinguishInternalFromCustomerSafe() { XCTAssertNotEqual(WorkResourceVisibilityPolicyV1.internalOnly, .customerSafe) }
}

private final class C50IncumbentAccessibleDocumentBoundaryTests: XCTestCase {
    func testC50AccessibleDocumentBoundaryIsTypedAndNonPersistent() {
        XCTAssertEqual(C50AccessibleDocumentIncumbentExchangeBoundaryV1.crossContractTypes.count, 4)
        XCTAssertEqual(C50AccessibleDocumentIncumbentPersistenceBoundaryV1.nonPersistentContractTypes.count, 7)
        XCTAssertTrue(C50AccessibleDocumentIncumbentExchangeBoundaryV1.privacyAllowlistIsClosed)
        XCTAssertTrue(C50AccessibleDocumentIncumbentExchangeBoundaryV1.quarantinePrecedesProjection)
        XCTAssertTrue(C50AccessibleDocumentIncumbentExchangeBoundaryV1.sourceAndSessionBytesAreExcluded)
        XCTAssertTrue(C50AccessibleDocumentIncumbentExchangeBoundaryV1.writerAndRendererAreDelegated)
        XCTAssertTrue(C50AccessibleDocumentIncumbentExchangeBoundaryV1.lifecycleIsDerivedOnly)
        XCTAssertTrue(C50AccessibleDocumentIncumbentExchangeBoundaryV1.conformanceClaimsAreNotInferred)
        XCTAssertFalse(C50AccessibleDocumentIncumbentPersistenceBoundaryV1.createsSecondSwiftDataFamily)
        XCTAssertFalse(C50AccessibleDocumentIncumbentPersistenceBoundaryV1.persistsSourceBytes)
        XCTAssertFalse(C50AccessibleDocumentIncumbentPersistenceBoundaryV1.persistsSessionBytes)
        XCTAssertFalse(C50AccessibleDocumentIncumbentPersistenceBoundaryV1.persistsProviderState)
        XCTAssertFalse(C50AccessibleDocumentIncumbentPersistenceBoundaryV1.persistsQuarantinePayload)
        XCTAssertTrue(C50AccessibleDocumentIncumbentCoordinatorBoundaryV1.previewIsZeroWrite)
        XCTAssertTrue(C50AccessibleDocumentIncumbentCoordinatorBoundaryV1.accessibilityCoordinatorIsNotAnImportWriter)
        XCTAssertTrue(C50AccessibleDocumentIncumbentLifecycleBoundaryV1.inputBytesAreLeasedScratch)
        XCTAssertTrue(C50AccessibleDocumentIncumbentLifecycleBoundaryV1.scratchIsExcludedFromBackup)
        XCTAssertTrue(C50AccessibleDocumentIncumbentLifecycleBoundaryV1.scratchIsDeletedAfterOutcome)
        XCTAssertFalse(C50AccessibleDocumentIncumbentLifecycleBoundaryV1.lifecyclePersistsSourceBytes)
        XCTAssertFalse(C50AccessibleDocumentIncumbentLifecycleBoundaryV1.lifecyclePersistsSessionBytes)
        XCTAssertFalse(C50AccessibleDocumentIncumbentLifecycleBoundaryV1.lifecycleCreatesSecondWriter)
        XCTAssertFalse(C50AccessibleDocumentIncumbentLifecycleBoundaryV1.lifecycleCreatesSecondStore)
        XCTAssertFalse(C50AccessibleDocumentIncumbentLifecycleBoundaryV1.lifecycleClaimsProviderAvailability)
        XCTAssertEqual(String(reflecting: C50AccessibleDocumentIncumbentExchangeBoundaryV1.adapterContract), String(reflecting: IncumbentFileAdapterV1.self))
        XCTAssertEqual(String(reflecting: C50AccessibleDocumentIncumbentExchangeBoundaryV1.selectionReceiptContract), String(reflecting: IncumbentSelectionReceiptV1.self))
        XCTAssertEqual(String(reflecting: C50AccessibleDocumentIncumbentExchangeBoundaryV1.quarantineReceiptContract), String(reflecting: IncumbentFileQuarantineReceiptV1.self))
    }
}
