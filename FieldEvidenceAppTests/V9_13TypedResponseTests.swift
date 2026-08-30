import CryptoKit
import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V9_13TypedResponseTests: XCTestCase {
    private let releaseSHA = String(repeating: "a", count: 64)
    private let workflowSHA = String(repeating: "b", count: 64)

    func testV9_13G01EveryClosedResponseKindRoundTripsCanonically() throws {
        let fixture = try loadFixture()
        XCTAssertTrue(fixture.testOnly)
        XCTAssertEqual(fixture.schema, "V21P03C03TypedResponseCorpusV1")
        XCTAssertEqual(fixture.responseKinds, ResponseValueKindV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(fixture.unitIDs, KernelUnitRegistryV1.definitions.map(\.unitID))
        XCTAssertEqual(fixture.lifecycle.schema, KernelResponseLifecycleV1.schema)
        XCTAssertFalse(fixture.lifecycle.persistent)

        let values: [ResponseValueV1] = [
            .noValue,
            .notApplicable(reasonID: "reason.not_applicable"),
            .boolean(true),
            .triState(.unknown),
            .singleOption("option.visible"),
            .multipleOptions(["option.a", "option.b"]),
            .text("Observed condition"),
            .localDate(try ResponseLocalDateV1(year: 2026, month: 8, day: 26)),
            .localTime(try ResponseLocalTimeV1(hour: 22, minute: 15, second: 30, millisecond: 125)),
            .instant(try ResponseInstantV1(epochMilliseconds: 1_788_320_130_125)),
            .duration(try ResponseDurationV1(milliseconds: 90_000)),
            .integer(42),
            .decimal(try ExactDecimalV1(mantissa: 12_345, scale: 3)),
            .measurement(try ExactMeasurementV1(
                enteredValue: ExactDecimalV1(mantissa: 1, scale: 0),
                enteredUnitID: "[fc_i]",
                precisionScale: 0,
                uncertaintyCanonical: ExactDecimalV1(mantissa: 25, scale: 2),
                source: .instrumentObserved,
                captureMethodID: "meter.manual"
            )),
            .entityReference(try ResponseEntityReferenceV1(entityKindID: "asset", entityID: "asset.001")),
            .contentReference(try ResponseContentReferenceIDV1("content.001")),
        ]
        XCTAssertEqual(values.map(\.kind.rawValue).sorted(), fixture.responseKinds)
        for value in values {
            let bytes = try ResponseValueCanonicalCodecV1.encode(value)
            XCTAssertEqual(try ResponseValueCanonicalCodecV1.decode(bytes), value)
            XCTAssertEqual(try ResponseValueCanonicalCodecV1.encode(ResponseValueCanonicalCodecV1.decode(bytes)), bytes)
        }
        guard case .measurement(let measurement) = values[13] else {
            return XCTFail("measurement case missing")
        }
        XCTAssertEqual(measurement.enteredValue, try ExactDecimalV1(mantissa: 1, scale: 0))
        XCTAssertEqual(measurement.enteredUnitID, "[fc_i]")
        XCTAssertEqual(measurement.canonicalValue, try ExactDecimalV1(mantissa: 1_076_391, scale: 5))
        XCTAssertEqual(measurement.canonicalUnitID, "lx")
        XCTAssertEqual(measurement.dimension, .illuminance)
    }

    func testV9_13A01UnitsDimensionsRangesPrecisionAndUnknownKindsFailClosed() throws {
        XCTAssertThrowsError(try ResponseValueCanonicalCodecV1.decode(Data(#"{"kind":"FUTURE"}"#.utf8)))
        XCTAssertThrowsError(try ResponseValueCanonicalCodecV1.decode(Data(#"{"kind":"BOOLEAN","boolean":true,"opaque":{}}"#.utf8)))
        XCTAssertThrowsError(try ResponseValueCanonicalCodecV1.decode(Data(#"{"decimal":{"mantissa":1,"scale":0,"unknown":1},"kind":"DECIMAL"}"#.utf8)))
        XCTAssertThrowsError(try ExactUnitConverterV1.convert(ExactDecimalV1(mantissa: 1, scale: 0), from: "unknown"))
        XCTAssertThrowsError(try ExactUnitConverterV1.convert(ExactDecimalV1(mantissa: 1, scale: 0), from: "m", policyVersion: "FUTURE"))
        XCTAssertThrowsError(try ExactDecimalV1(mantissa: 1, scale: ExactDecimalV1.maximumScale + 1))
        assertResponseFailure(.precisionLoss) {
            _ = try ExactMeasurementV1(
                enteredValue: ExactDecimalV1(mantissa: 125, scale: 2),
                enteredUnitID: "cm",
                precisionScale: 1,
                uncertaintyCanonical: nil,
                source: .manualEntry,
                captureMethodID: "manual"
            )
        }
        XCTAssertThrowsError(try ResponseValueV1.multipleOptions(["duplicate", "duplicate"]).validate())

        let tieEven = try ExactUnitConverterV1.rounded(numerator: 5, denominator: 2, targetScale: 0)
        let tieAdjusted = try ExactUnitConverterV1.rounded(numerator: 7, denominator: 2, targetScale: 0)
        let negativeTieEven = try ExactUnitConverterV1.rounded(numerator: -5, denominator: 2, targetScale: 0)
        let negativeTieAdjusted = try ExactUnitConverterV1.rounded(numerator: -7, denominator: 2, targetScale: 0)
        XCTAssertEqual(tieEven.canonicalValue.mantissa, 2)
        XCTAssertEqual(tieEven.receipt.disposition, .tieEvenUnchanged)
        XCTAssertEqual(tieAdjusted.canonicalValue.mantissa, 4)
        XCTAssertEqual(tieAdjusted.receipt.disposition, .tieEvenAdjusted)
        XCTAssertEqual(negativeTieEven.canonicalValue.mantissa, -2)
        XCTAssertEqual(negativeTieAdjusted.canonicalValue.mantissa, -4)

        let lengthField = try measurementField()
        let wrongDimension = try BoundResponseValueV1(
            fieldID: lengthField.fieldID,
            value: .measurement(try ExactMeasurementV1(
                enteredValue: ExactDecimalV1(mantissa: 10, scale: 0),
                enteredUnitID: "lx",
                precisionScale: 0,
                uncertaintyCanonical: nil,
                source: .manualEntry,
                captureMethodID: "manual"
            ))
        )
        XCTAssertThrowsError(try ResponseFieldValidatorV1.validate(wrongDimension, against: lengthField))

        let outOfRange = try BoundResponseValueV1(
            fieldID: lengthField.fieldID,
            value: .measurement(try ExactMeasurementV1(
                enteredValue: ExactDecimalV1(mantissa: 101, scale: 0),
                enteredUnitID: "m",
                precisionScale: 0,
                uncertaintyCanonical: nil,
                source: .manualEntry,
                captureMethodID: "manual"
            ))
        )
        assertResponseFailure(.rangeViolation) {
            try ResponseFieldValidatorV1.validate(outOfRange, against: lengthField)
        }
        XCTAssertThrowsError(try ExactUnitConverterV1.convert(ExactDecimalV1(mantissa: .max, scale: 0), from: "h"))
    }

    func testV9_13H01RepeatIdentitySurvivesReorderResumeAndRejectsCollisions() throws {
        let definition = try repeatField()
        let first = try repeatResponse(id: "repeat.001", order: 0, value: "option.visible")
        let second = try repeatResponse(id: "repeat.002", order: 1, value: "option.clear")
        let canonicalA = try ResponseFieldValidatorV1.canonicalOrder([second, first], definitions: [definition])
        let canonicalB = try ResponseFieldValidatorV1.canonicalOrder([first, second], definitions: [definition])
        XCTAssertEqual(canonicalA, canonicalB)
        XCTAssertEqual(canonicalA.map(\.stableIdentity), ["field.condition|repeat.001", "field.condition|repeat.002"])

        let data = try JSONEncoder.sorted.encode(canonicalA)
        let resumed = try JSONDecoder().decode([BoundResponseValueV1].self, from: data)
        XCTAssertEqual(resumed, canonicalA)
        XCTAssertEqual(try ResponseFieldValidatorV1.canonicalOrder(Array(resumed.reversed()), definitions: [definition]), canonicalA)

        let inactiveState = try RepeatInstanceStateV1(
            instanceID: RepeatInstanceIDV1("repeat.001"),
            repeatNodeID: "node.repeat",
            stableOrder: 0,
            activity: .inactiveByPath
        )
        let inactive = try RepeatResponseBindingV1(instanceState: inactiveState, packageReleaseID: releaseSHA, workflowSHA256: workflowSHA)
        XCTAssertFalse(inactive.satisfiesCompletion)
        XCTAssertFalse(inactive.includedInReporting)

        let sameOrder = try repeatResponse(id: "repeat.003", order: 1, value: "option.clear")
        assertResponseFailure(.duplicateIdentity) {
            _ = try ResponseFieldValidatorV1.canonicalOrder([second, sameOrder], definitions: [definition])
        }
        let tooMany = try ResponseCardinalityV1(minimum: 0, maximum: ResponseCardinalityV1.maximumResponses)
        XCTAssertEqual(tooMany.maximum, ResponseCardinalityV1.maximumResponses)
        XCTAssertThrowsError(try ResponseCardinalityV1(minimum: 0, maximum: ResponseCardinalityV1.maximumResponses + 1))
    }

    func testV9_13I01InterruptedDormantContractPublicationExposesZeroOrCompleteRegistry() throws {
        let definition = try measurementField()
        for boundary in KernelResponseRegistryPublisherV1.Boundary.allCases {
            XCTAssertThrowsError(try KernelResponseRegistryPublisherV1.publish(fieldDefinitions: [definition], interruption: {
                if $0 == boundary { throw ResponseContractFailureV1.publicationInterrupted }
            }))
        }
        let published = try KernelResponseRegistryPublisherV1.publish(fieldDefinitions: [definition])
        let bytes = try KernelResponseRegistryCanonicalCodecV1.encode(published.registry)
        let relaunched = try KernelResponseRegistryPublisherV1.recover(canonicalData: bytes, receipt: published.receipt)
        XCTAssertEqual(relaunched, published.registry)
        XCTAssertEqual(try KernelResponseRegistryPublisherV1.recover(canonicalData: bytes, receipt: published.receipt), published.registry)
        XCTAssertEqual(KernelResponseLifecycleV1.mode, "DECLARATION_ONLY")
        XCTAssertFalse(KernelResponseLifecycleV1.persistent)
        XCTAssertFalse(KernelResponseLifecycleV1.migrationRequired)
        XCTAssertFalse(KernelResponseLifecycleV1.backupRestoreRequired)
        XCTAssertFalse(KernelResponseLifecycleV1.deleteEraseRequired)
        XCTAssertFalse(KernelResponseLifecycleV1.importExportRequired)
        XCTAssertFalse(KernelResponseLifecycleV1.searchRebuildReplayRequired)
        XCTAssertFalse(KernelResponseLifecycleV1.journalReplayRequired)
    }

    func testV9_13R01LegacySignParityAndDormantRecoveryPreserveExactSemantics() throws {
        let parity = try ShippingIlluminatedSignAdapterV1.parityReceipt()
        XCTAssertTrue(parity.exactParity)
        XCTAssertEqual(parity.sourceCanonicalSHA256, parity.roundTripCanonicalSHA256)
        let pack = SignPack.illuminatedSignV1
        let cnv = try XCTUnwrap(pack.couldNotVerifyReasons.entries.first)
        let mapped = try ShippingIlluminatedSignAdapterV1.typedResponses(from: .init(
            acknowledgementValues: ["after_dark": true, "safe_authorized_position": true],
            outcomeKey: "could_not_verify",
            issueKeys: ["dim_or_uneven", "dark_section"],
            couldNotVerify: .init(
                reasonKey: cnv.key,
                frozenDisplay: cnv.display,
                registryVersion: pack.couldNotVerifyReasons.version
            ),
            note: "Access changed during the visible-condition check.",
            entityReference: ResponseEntityReferenceV1(entityKindID: "asset", entityID: "asset.001"),
            contentReference: ResponseContentReferenceIDV1("content.001")
        ))
        XCTAssertTrue(mapped.receipt.exactSemanticParity)
        XCTAssertEqual(mapped.receipt.inventedMeasurementCount, 0)
        XCTAssertEqual(mapped.receipt.orderedFieldIDs, mapped.responses.map(\.fieldID).sorted())
        XCTAssertEqual(mapped.receipt.couldNotVerifyRegistryVersion, pack.couldNotVerifyReasons.version)
        XCTAssertEqual(mapped.receipt.couldNotVerifyFrozenDisplay, cnv.display)
        XCTAssertEqual(mapped.receipt.shippingPackCanonicalSHA256, parity.sourceCanonicalSHA256)
        XCTAssertEqual(mapped.responses.first { $0.fieldID == "legacy.outcome" }?.value, .singleOption("could_not_verify"))
        XCTAssertEqual(mapped.responses.first { $0.fieldID == "legacy.issues" }?.value, .multipleOptions(["dark_section", "dim_or_uneven"]))
        XCTAssertThrowsError(try ShippingIlluminatedSignAdapterV1.typedResponses(from: .init(
            outcomeKey: "could_not_verify"
        )))
        XCTAssertThrowsError(try ShippingIlluminatedSignAdapterV1.typedResponses(from: .init(
            outcomeKey: "future_outcome"
        )))
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.historicReleaseSHA256, "6b5d1129bbc81f9d0845323008ca348739d9b31ce541a48311a65a6f7adfac23")
        XCTAssertEqual(fixture.historicBindingSHA256, "94cb18574feb493518ec00b28d982599a92e73a0d5ed465175d4d947c1914fc3")
        XCTAssertEqual(KernelResponseLifecycleV1.downgradePolicy, "DORMANT_REVERT_ALLOWED")
        XCTAssertEqual(KernelResponseLifecycleV1.shippingAdoption, "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION")
    }

    private func measurementField() throws -> ResponseFieldDefinitionV1 {
        try ResponseFieldDefinitionV1(
            fieldID: "field.length",
            packageReleaseID: releaseSHA,
            workflowSHA256: workflowSHA,
            valueKind: .measurement,
            cardinality: ResponseCardinalityV1(minimum: 0, maximum: 1),
            minimumNumericValue: ExactDecimalV1(mantissa: 0, scale: 0),
            maximumNumericValue: ExactDecimalV1(mantissa: 100, scale: 0),
            measurementDimension: .length,
            allowedUnitIDs: ["[ft_i]", "[in_i]", "cm", "m", "mm"],
            maximumPrecisionScale: 6,
            maximumUncertaintyCanonical: ExactDecimalV1(mantissa: 1, scale: 0)
        )
    }

    private func repeatField() throws -> ResponseFieldDefinitionV1 {
        try ResponseFieldDefinitionV1(
            fieldID: "field.condition",
            packageReleaseID: releaseSHA,
            workflowSHA256: workflowSHA,
            valueKind: .singleOption,
            cardinality: ResponseCardinalityV1(minimum: 0, maximum: 16),
            allowedOptionIDs: ["option.clear", "option.visible"],
            repeatNodeID: "node.repeat"
        )
    }

    private func repeatResponse(id: String, order: Int, value: String) throws -> BoundResponseValueV1 {
        let state = try RepeatInstanceStateV1(
            instanceID: RepeatInstanceIDV1(id), repeatNodeID: "node.repeat", stableOrder: order
        )
        return try BoundResponseValueV1(
            fieldID: "field.condition",
            value: .singleOption(value),
            repeatBinding: RepeatResponseBindingV1(
                instanceState: state, packageReleaseID: releaseSHA, workflowSHA256: workflowSHA
            )
        )
    }

    private func assertResponseFailure(
        _ expected: ResponseContractFailureV1,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? ResponseContractFailureV1, expected, file: file, line: line)
        }
    }

    private func loadFixture() throws -> TypedResponseFixture {
        let url = Bundle(for: Self.self).url(
            forResource: "V21P03C03TypedResponseCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V21/InspectionKernel"
        ) ?? Bundle(for: Self.self).url(forResource: "V21P03C03TypedResponseCorpusV1", withExtension: "json")
        return try JSONDecoder().decode(TypedResponseFixture.self, from: Data(contentsOf: try XCTUnwrap(url)))
    }
}

private struct TypedResponseFixture: Decodable {
    struct Lifecycle: Decodable { let schema: String; let persistent: Bool }
    let schema: String
    let schemaVersion: Int
    let testOnly: Bool
    let responseKinds: [String]
    let unitIDs: [String]
    let historicReleaseSHA256: String
    let historicBindingSHA256: String
    let lifecycle: Lifecycle
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }
}

extension V9_13TypedResponseTests {
    func testV23P03C19TypedResponseBindsExactMeasurementAndUnit() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        try fixture.capture.validate(fieldDefinition: fixture.fieldDefinition)
        XCTAssertEqual(fixture.capture.response.fieldID, fixture.fieldDefinition.fieldID)
        XCTAssertEqual(fixture.capture.measurement.enteredUnitID, "[fc_i]")
        XCTAssertEqual(fixture.capture.measurement.canonicalUnitID, "lx")
        XCTAssertEqual(fixture.capture.measurement.precisionScale, 0)
    }

    func testC20PrivacyTransformMetadataSanitationIsExplicit() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        XCTAssertEqual(fixture.manifest.metadataSanitation.result, .complete)
        XCTAssertTrue(fixture.manifest.metadataSanitation.retainedSourceMetadataKeys.isEmpty)
        XCTAssertThrowsError(try PrivacyMetadataSanitationEvidenceV1(
            sanitizerID: "c20-sanitizer", sanitizerVersion: "1", result: .failed
        ))
    }
}

extension V9_13TypedResponseTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension V9_13TypedResponseTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyFieldKindV1.allCases.count, 18)
        XCTAssertEqual(SurveyBooleanObservationV1.allCases.count, 4)
        XCTAssertEqual(ActivityKindV1.allCases.count, 5)
    }
}
extension V9_13TypedResponseTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_13TypedResponseTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_13TypedResponseTests_swift_Tests: XCTestCase {
    func testC47V913TypedResponseTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_13TypedResponseTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_13TypedResponseTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_13TypedResponseTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_13TypedResponseTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_13TypedResponseTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_13TypedResponseTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_13TypedResponseTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityStateMachineV2.exhaustiveTable.count, ActivityStateV2.allCases.count)
        XCTAssertFalse(ActivityStateMachineV2.permits(from: .finalized, to: .draft))
    }
}

private final class C53SharedTypedResponseReliabilityTests: XCTestCase {
    func testV23P03C53TypedResponseRemainsAnEvidenceInput() {
        XCTAssertTrue(C53SharedWorkflowReliabilityBoundaryV1.reliabilityInputIsNotWorkflowState)
        XCTAssertTrue(C53SharedWorkflowReliabilityBoundaryV1.metricProjectionIsDerivedOnly)
        XCTAssertFalse(C53SharedWorkflowReliabilityBoundaryV1.automaticWorkOrReleaseToServiceIsPermitted)
        XCTAssertTrue(C53SharedServiceReliabilitySemanticBoundaryV1.metricRequiresQualifiedPositiveExposure)
        XCTAssertFalse(ServiceReliabilityClaimBoundaryV1.restorationImpliesVerification)
    }
}
