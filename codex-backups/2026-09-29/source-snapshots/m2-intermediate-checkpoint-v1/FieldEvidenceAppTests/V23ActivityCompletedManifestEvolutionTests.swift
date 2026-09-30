import Foundation
import XCTest
@testable import FieldEvidenceApp

/// V1 expectations come from the published manifest, never a regenerated golden.
/// Extended numeric cases enter the real manifest decoder as literal JSON numbers.
@MainActor
final class V23ActivityCompletedManifestEvolutionTests: XCTestCase {
    private let legacyFixtureName = "V23P03C06LegacyContractManifestV1"
    private let extendedTimeEncoding = "PER_FIELD_UTC_RFC3339_MILLISECONDS_Z_OR_FINITE_APPLE_REFERENCE_SECONDS"
    private let extendedStringNormalization = "PER_FIELD_NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED_OR_PRESERVED_SOURCE_UNICODE"

    private func legacyData() throws -> Data {
        let testBundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            testBundle.url(forResource: legacyFixtureName, withExtension: "json",
                           subdirectory: "Fixtures/V23/Activities")
                ?? testBundle.url(forResource: legacyFixtureName, withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 96_442)
        XCTAssertEqual(KernelCanonicalHashV1.sha256(data).uppercased(),
                       "B142747430F74FC3B2D0B403F9E60BCF08D3BA49F5E1249A2790D95EB0A3643C")
        return data
    }

    private func legacyManifest() throws -> ContractManifestV1 {
        try JSONDecoder().decode(ContractManifestV1.self, from: legacyData())
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    // Only the authentic V1 fixture uses this Foundation normalization. UInt64
    // extension tests compare typed values and decimal text without NSNumber.
    private func canonicalJSON(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: object,
                                          options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func manifest(
        fields: [ContractFieldDefinitionV1], schemaVersion: Int = 2,
        codecVersion: Int = 2, minimumReaderVersion: Int = 2,
        maximumReaderVersion: Int = 2
    ) throws -> ContractManifestV1 {
        let object = try ContractObjectDefinitionV1(
            typeID: "completed-profile-v2", version: 1, unknownFieldPolicy: .reject,
            fields: fields.sorted()
        )
        let codec = try ContractCodecRuleV1(codecVersion: codecVersion)
        let compatibility = try ContractCompatibilityRuleV1(
            minimumReaderVersion: minimumReaderVersion,
            maximumReaderVersion: maximumReaderVersion, unknownObjectFields: .reject
        )
        return try ContractManifestV1(
            manifestID: "completed-manifest-evolution-v2", manifestVersion: 1,
            codec: codec, compatibility: compatibility, objects: [object], enums: [],
            reportSectionRegistry: legacyManifest().reportSectionRegistry,
            schemaVersion: schemaVersion
        )
    }

    private func rawManifest(
        fields: [String], schemaVersion: Int = 2, codecVersion: Int = 2,
        minimumReaderVersion: Int = 2, maximumReaderVersion: Int = 2
    ) throws -> Data {
        let registry = try encode(legacyManifest().reportSectionRegistry)
        let registryJSON = try XCTUnwrap(String(data: registry, encoding: .utf8))
        let timeEncoding = codecVersion == 1 ? "UTC_RFC3339_MILLISECONDS_Z" : extendedTimeEncoding
        let stringNormalization = codecVersion == 1
            ? "NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED"
            : extendedStringNormalization
        let fieldJSON = fields.joined(separator: ",")
        let json = """
        {"schemaVersion":\(schemaVersion),"manifestID":"completed-manifest-evolution-v2",
        "manifestVersion":1,"persistentContractSchema":"KERNEL_SNAPSHOT_V1",
        "codec":{"codecVersion":\(codecVersion),
        "canonicalJSON":"UTF8_SORTED_KEYS_NO_INSIGNIFICANT_WHITESPACE",
        "integerEncoding":"BASE10_INTEGER_NO_EXPONENT","timeEncoding":"\(timeEncoding)",
        "nullEncoding":"EXPLICIT_NULL_ONLY_WHEN_REQUIRED_NULLABLE",
        "binaryEncoding":"RFC4648_BASE64_PADDED",
        "stringNormalization":"\(stringNormalization)",
        "formatAssertion":false},
        "compatibility":{"minimumReaderVersion":\(minimumReaderVersion),
        "maximumReaderVersion":\(maximumReaderVersion),"unknownObjectFields":"REJECT",
        "publishedVersionsImmutable":true},
        "objects":[{"typeID":"completed-profile-v2","version":1,
        "unknownFieldPolicy":"REJECT","fields":[\(fieldJSON)]}],"enums":[],
        "reportSectionRegistry":\(registryJSON)}
        """
        return Data(json.utf8)
    }

    private func rawField(kind: String = "UNSIGNED_INTEGER", extra: String = "") -> String {
        """
        {"fieldID":"revision","jsonName":"revision","kind":"\(kind)",
        "required":true,"nullable":false,"ordered":false,"uniqueItems":false\(extra)}
        """
    }

    private func replacingOnce(_ data: Data, _ original: String, with replacement: String) throws -> Data {
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(text.components(separatedBy: original).count, 2, original)
        return Data(text.replacingOccurrences(of: original, with: replacement).utf8)
    }

    func testPublishedV1ManifestRoundTripPreservesCanonicalBytesAndOmitsExtensions() throws {
        let source = try legacyData()
        let value = try JSONDecoder().decode(ContractManifestV1.self, from: source)
        try value.validate()
        XCTAssertEqual(value.manifestID, "v23-p03-c06-contract-manifest-v1")
        XCTAssertEqual(value.objects.count, 29)
        XCTAssertEqual(value.enums.count, 15)
        XCTAssertEqual(value.schemaVersion, 1)
        XCTAssertEqual(ContractManifestV1.schemaVersion, 1)
        XCTAssertEqual(ContractManifestV1.extendedSchemaVersion, 2)
        XCTAssertEqual(value.codec.codecVersion, 1)
        XCTAssertEqual(value.codec.timeEncoding, "UTC_RFC3339_MILLISECONDS_Z")
        XCTAssertEqual(value.codec.stringNormalization, "NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED")
        XCTAssertEqual(value.compatibility.minimumReaderVersion, 1)
        XCTAssertEqual(value.compatibility.maximumReaderVersion, 1)

        // Exercise the unchanged default initializer as well as the decoding entry.
        let defaultValue = try ContractManifestV1(
            manifestID: value.manifestID, manifestVersion: value.manifestVersion,
            codec: value.codec, compatibility: value.compatibility,
            objects: value.objects, enums: value.enums,
            reportSectionRegistry: value.reportSectionRegistry
        )
        XCTAssertEqual(defaultValue, value)
        let reencoded = try encode(value)
        XCTAssertEqual(try canonicalJSON(source), try canonicalJSON(reencoded))
        XCTAssertEqual(try encode(defaultValue), reencoded)
        XCTAssertEqual(try JSONDecoder().decode(ContractManifestV1.self, from: reencoded), value)

        for definition in value.enums { XCTAssertNil(definition.knownIntegerValues) }
        for object in value.objects {
            for field in object.fields {
                XCTAssertNil(field.minimumUnsignedInteger, field.fieldID)
                XCTAssertNil(field.maximumUnsignedInteger, field.fieldID)
                XCTAssertNil(field.maximumKeyUTF8Bytes, field.fieldID)
                XCTAssertNotEqual(field.kind, .unsignedInteger)
                XCTAssertNotEqual(field.kind, .referenceDateSeconds)
                XCTAssertNotEqual(field.kind, .preservedString)
                XCTAssertNotEqual(field.kind, .stringMap)
                XCTAssertNotEqual(field.arrayElementKind, .unsignedInteger)
                XCTAssertNotEqual(field.arrayElementKind, .referenceDateSeconds)
                XCTAssertNotEqual(field.arrayElementKind, .preservedString)
                XCTAssertNotEqual(field.arrayElementKind, .stringMap)
            }
        }
        let text = try XCTUnwrap(String(data: reencoded, encoding: .utf8))
        XCTAssertFalse(text.contains("\"minimumUnsignedInteger\""))
        XCTAssertFalse(text.contains("\"maximumUnsignedInteger\""))
        XCTAssertFalse(text.contains("\"maximumKeyUTF8Bytes\""))
        XCTAssertFalse(text.contains("\"knownIntegerValues\""))
        XCTAssertFalse(text.contains("UNSIGNED_INTEGER"))
        XCTAssertFalse(text.contains("REFERENCE_DATE_SECONDS"))
        XCTAssertFalse(text.contains("PRESERVED_STRING"))
        XCTAssertFalse(text.contains("STRING_MAP"))
    }

    func testUnsignedBoundsRoundTripPreservesEntireUInt64Domain() throws {
        let full = try ContractFieldDefinitionV1(
            fieldID: "a-full", jsonName: "full", kind: .unsignedInteger, required: true,
            minimumUnsignedInteger: 0, maximumUnsignedInteger: UInt64.max
        )
        let highest = try ContractFieldDefinitionV1(
            fieldID: "b-highest", jsonName: "highest", kind: .unsignedInteger, required: true,
            minimumUnsignedInteger: UInt64.max - 1, maximumUnsignedInteger: UInt64.max
        )
        let unbounded = try ContractFieldDefinitionV1(
            fieldID: "c-unbounded", jsonName: "unbounded", kind: .unsignedInteger, required: true
        )
        let value = try manifest(fields: [full, highest, unbounded])
        let encoded = try encode(value)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(text.contains("\"minimumUnsignedInteger\":18446744073709551614"))
        XCTAssertTrue(text.contains("\"maximumUnsignedInteger\":18446744073709551615"))
        XCTAssertTrue(text.contains("\"minimumUnsignedInteger\":0"))
        let decoded = try JSONDecoder().decode(ContractManifestV1.self, from: encoded)
        try decoded.validate()
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.objects[0].fields[0].minimumUnsignedInteger, 0)
        XCTAssertEqual(decoded.objects[0].fields[0].maximumUnsignedInteger, UInt64.max)
        XCTAssertEqual(decoded.objects[0].fields[1].minimumUnsignedInteger, UInt64.max - 1)
        XCTAssertEqual(decoded.objects[0].fields[1].maximumUnsignedInteger, UInt64.max)
        XCTAssertEqual(try encode(decoded), encoded)
        let unboundedText = try XCTUnwrap(String(data: encode(unbounded), encoding: .utf8))
        XCTAssertFalse(unboundedText.contains("minimumUnsignedInteger"))
        XCTAssertFalse(unboundedText.contains("maximumUnsignedInteger"))

        // This expected numeric token is literal, independent of the Swift encoder.
        let exactRaw = rawField(extra: ",\"minimumUnsignedInteger\":18446744073709551615,\"maximumUnsignedInteger\":18446744073709551615")
        let exact = try JSONDecoder().decode(ContractManifestV1.self, from: rawManifest(fields: [exactRaw]))
        XCTAssertEqual(exact.objects[0].fields[0].minimumUnsignedInteger, UInt64.max)
        XCTAssertEqual(exact.objects[0].fields[0].maximumUnsignedInteger, UInt64.max)
        let exactText = try XCTUnwrap(String(data: encode(exact), encoding: .utf8))
        XCTAssertTrue(exactText.contains("\"minimumUnsignedInteger\":18446744073709551615"))
        XCTAssertTrue(exactText.contains("\"maximumUnsignedInteger\":18446744073709551615"))
    }

    func testSignedDomainAndMixedWrongKindOrInvertedBounds() throws {
        let signed = try ContractFieldDefinitionV1(
            fieldID: "signed", jsonName: "signed", kind: .integer, required: true,
            minimumInteger: Int64.min, maximumInteger: Int64.max
        )
        let value = try manifest(fields: [signed])
        let encoded = try encode(value)
        XCTAssertEqual(try JSONDecoder().decode(ContractManifestV1.self, from: encoded), value)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(text.contains("\"minimumInteger\":-9223372036854775808"))
        XCTAssertTrue(text.contains("\"maximumInteger\":9223372036854775807"))
        XCTAssertThrowsError(try ContractFieldDefinitionV1(
            fieldID: "revision", jsonName: "revision", kind: .unsignedInteger, required: true,
            minimumInteger: 0, maximumUnsignedInteger: UInt64.max
        ))
        XCTAssertThrowsError(try ContractFieldDefinitionV1(
            fieldID: "revision", jsonName: "revision", kind: .integer, required: true,
            minimumInteger: 0, maximumUnsignedInteger: UInt64.max
        ))
        XCTAssertThrowsError(try ContractFieldDefinitionV1(
            fieldID: "revision", jsonName: "revision", kind: .unsignedInteger, required: true,
            minimumUnsignedInteger: 2, maximumUnsignedInteger: 1
        ))

        let invalidFields: [String] = [
            rawField(extra: ",\"minimumInteger\":0"),
            rawField(extra: ",\"maximumInteger\":1,\"minimumUnsignedInteger\":0"),
            rawField(kind: "INTEGER", extra: ",\"minimumUnsignedInteger\":0"),
            rawField(kind: "INTEGER", extra: ",\"minimumInteger\":0,\"maximumUnsignedInteger\":1"),
            rawField(kind: "STRING", extra: ",\"minimumUnsignedInteger\":0"),
            rawField(kind: "REFERENCE_DATE_SECONDS", extra: ",\"maximumUnsignedInteger\":1"),
            rawField(kind: "ARRAY", extra: ",\"arrayElementKind\":\"UNSIGNED_INTEGER\",\"maximumItems\":2,\"minimumUnsignedInteger\":0"),
            rawField(extra: ",\"minimumUnsignedInteger\":2,\"maximumUnsignedInteger\":1"),
            rawField(kind: "INTEGER", extra: ",\"minimumInteger\":2,\"maximumInteger\":1")
        ]
        for field in invalidFields {
            let data = try rawManifest(fields: [field])
            XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: data), field)
        }
    }

    func testManifestVersionsRequireMatchingCodecAndReader() throws {
        let field = try ContractFieldDefinitionV1(
            fieldID: "name", jsonName: "name", kind: .string, required: true
        )
        let legacy = try manifest(fields: [field], schemaVersion: 1, codecVersion: 1,
                                  minimumReaderVersion: 1, maximumReaderVersion: 1)
        XCTAssertEqual(legacy.schemaVersion, 1)
        XCTAssertNoThrow(try legacy.validate())
        let extended = try manifest(fields: [field])
        XCTAssertEqual(extended.schemaVersion, 2)
        XCTAssertNoThrow(try extended.validate())
        XCTAssertNoThrow(try manifest(fields: [field], minimumReaderVersion: 3, maximumReaderVersion: 3))

        let invalid: [(schema: Int, codec: Int, minimum: Int, maximum: Int)] = [
            (0, 1, 1, 1), (3, 2, 2, 2), (1, 2, 2, 2), (2, 1, 2, 2),
            (2, 2, 1, 2), (2, 2, 0, 2), (2, 2, 2, 1), (2, 0, 2, 2), (2, 3, 2, 2)
        ]
        for item in invalid {
            XCTAssertThrowsError(try manifest(
                fields: [field], schemaVersion: item.schema, codecVersion: item.codec,
                minimumReaderVersion: item.minimum, maximumReaderVersion: item.maximum
            ), "\(item)")
            let data = try rawManifest(
                fields: [rawField(kind: "STRING")], schemaVersion: item.schema,
                codecVersion: item.codec, minimumReaderVersion: item.minimum,
                maximumReaderVersion: item.maximum
            )
            XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: data), "\(item)")
        }
    }

    func testExtendedScalarAndArrayKindsRequireManifestTwo() throws {
        let fields: [ContractFieldDefinitionV1] = try [
            ContractFieldDefinitionV1(fieldID: "a-time", jsonName: "time",
                                      kind: .referenceDateSeconds, required: true),
            ContractFieldDefinitionV1(fieldID: "b-revision", jsonName: "revision",
                                      kind: .unsignedInteger, required: true),
            ContractFieldDefinitionV1(fieldID: "c-times", jsonName: "times", kind: .array,
                                      arrayElementKind: .referenceDateSeconds, required: true,
                                      maximumItems: 4, ordered: true),
            ContractFieldDefinitionV1(fieldID: "d-revisions", jsonName: "revisions", kind: .array,
                                      arrayElementKind: .unsignedInteger, required: true,
                                      maximumItems: 4, ordered: true),
            ContractFieldDefinitionV1(fieldID: "e-preserved", jsonName: "preserved",
                                      kind: .preservedString, required: true, maximumUTF8Bytes: 512),
            ContractFieldDefinitionV1(fieldID: "f-map", jsonName: "map",
                                      kind: .stringMap, required: true, maximumUTF8Bytes: 512,
                                      maximumKeyUTF8Bytes: 256),
            ContractFieldDefinitionV1(fieldID: "g-preserved-array", jsonName: "preservedArray", kind: .array,
                                      arrayElementKind: .preservedString, required: true,
                                      maximumItems: 4, ordered: true)
        ]
        let value = try manifest(fields: fields)
        let encoded = try encode(value)
        let decoded = try JSONDecoder().decode(ContractManifestV1.self, from: encoded)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.objects[0].fields, fields)
        XCTAssertEqual(ContractScalarKindV1.referenceDateSeconds.rawValue, "REFERENCE_DATE_SECONDS")
        XCTAssertEqual(ContractScalarKindV1.unsignedInteger.rawValue, "UNSIGNED_INTEGER")
        XCTAssertEqual(ContractScalarKindV1.preservedString.rawValue, "PRESERVED_STRING")
        XCTAssertEqual(ContractScalarKindV1.stringMap.rawValue, "STRING_MAP")
        XCTAssertEqual(decoded.codec.timeEncoding, extendedTimeEncoding)

        for field in fields {
            XCTAssertThrowsError(try manifest(fields: [field], schemaVersion: 1, codecVersion: 1,
                                             minimumReaderVersion: 1, maximumReaderVersion: 1))
            let fieldJSON = try XCTUnwrap(String(data: encode(field), encoding: .utf8))
            let data = try rawManifest(fields: [fieldJSON], schemaVersion: 1, codecVersion: 1,
                                       minimumReaderVersion: 1, maximumReaderVersion: 1)
            XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: data), field.fieldID)
        }
        let bounded = rawField(extra: ",\"minimumUnsignedInteger\":0,\"maximumUnsignedInteger\":1")
        let legacyData = try rawManifest(fields: [bounded], schemaVersion: 1, codecVersion: 1,
                                         minimumReaderVersion: 1, maximumReaderVersion: 1)
        XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: legacyData))
    }

    func testManifestDecoderRejectsInvalidNumericBoundsWithoutRounding() throws {
        let unsignedTokens = ["-1", "18446744073709551616", "1.5", "1e400"]
        for key in ["minimumUnsignedInteger", "maximumUnsignedInteger"] {
            for token in unsignedTokens {
                let field = rawField(extra: ",\"\(key)\":\(token)")
                let data = try rawManifest(fields: [field])
                XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: data), "\(key)=\(token)")
            }
        }
        let signedTokens = ["9223372036854775808", "-9223372036854775809", "1.5", "1e400"]
        for key in ["minimumInteger", "maximumInteger"] {
            for token in signedTokens {
                let field = rawField(kind: "INTEGER", extra: ",\"\(key)\":\(token)")
                let data = try rawManifest(fields: [field])
                XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: data), "\(key)=\(token)")
            }
        }
    }

    func testManifestDecoderRejectsUnknownMalformedAndExplicitNullFields() throws {
        let absent = try rawManifest(fields: [rawField()])
        let accepted = try JSONDecoder().decode(ContractManifestV1.self, from: absent)
        XCTAssertNil(accepted.objects[0].fields[0].minimumUnsignedInteger)
        XCTAssertNil(accepted.objects[0].fields[0].maximumUnsignedInteger)
        for key in ["minimumUnsignedInteger", "maximumUnsignedInteger"] {
            for token in ["null", "true", "\"1\"", "[]", "{}"] {
                let data = try rawManifest(fields: [rawField(extra: ",\"\(key)\":\(token)")])
                XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: data), "\(key)=\(token)")
            }
        }
        let invalidFields: [String] = [
            rawField(extra: ",\"futureBound\":1"),
            rawField(extra: ",\"minimumInteger\":null"),
            rawField(extra: ",\"maximumInteger\":null"),
            rawField(extra: ",\"arrayElementKind\":null"),
            rawField(extra: ",\"referencedTypeID\":null"),
            rawField(kind: "FUTURE_KIND"),
            rawField(kind: "ARRAY", extra: ",\"arrayElementKind\":\"FUTURE_KIND\",\"maximumItems\":2"),
            rawField(kind: "ARRAY", extra: ",\"arrayElementKind\":null,\"maximumItems\":2")
        ]
        for field in invalidFields {
            let data = try rawManifest(fields: [field])
            XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: data), field)
        }
        let replacements: [(String, String)] = [
            ("\"manifestID\":", "\"unexpectedManifestField\":true,\"manifestID\":"),
            ("\"codecVersion\":2", "\"codecVersion\":2,\"unexpectedCodecField\":true"),
            ("\"minimumReaderVersion\":2", "\"minimumReaderVersion\":2,\"unexpectedCompatibilityField\":true"),
            ("\"typeID\":\"completed-profile-v2\"", "\"typeID\":\"completed-profile-v2\",\"unexpectedObjectField\":true"),
            ("\"schemaVersion\":2", "\"schemaVersion\":null"),
            ("\"schemaVersion\":2", "\"schemaVersion\":\"2\""),
            ("\"kind\":\"UNSIGNED_INTEGER\"", "\"kind\":null"),
            ("\"required\":true,\"nullable\":false", "\"required\":null,\"nullable\":false"),
            ("\"codecVersion\":2", "\"codecVersion\":null"),
            ("\"minimumReaderVersion\":2", "\"minimumReaderVersion\":null")
        ]
        for (original, replacement) in replacements {
            let data = try replacingOnce(absent, original, with: replacement)
            XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: data), replacement)
        }
    }

    func testCodecTwoKeepsExistingRulesAndClosesVersionSpecificTimeMetadata() throws {
        let first = try ContractCodecRuleV1(codecVersion: 1)
        let second = try ContractCodecRuleV1(codecVersion: 2)
        XCTAssertEqual(first.timeEncoding, "UTC_RFC3339_MILLISECONDS_Z")
        XCTAssertEqual(second.timeEncoding, extendedTimeEncoding)
        XCTAssertEqual(second.canonicalJSON, first.canonicalJSON)
        XCTAssertEqual(second.integerEncoding, first.integerEncoding)
        XCTAssertEqual(second.nullEncoding, first.nullEncoding)
        XCTAssertEqual(second.binaryEncoding, first.binaryEncoding)
        XCTAssertEqual(first.stringNormalization, "NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED")
        XCTAssertEqual(second.stringNormalization, extendedStringNormalization)
        XCTAssertEqual(second.formatAssertion, first.formatAssertion)
        XCTAssertFalse(second.formatAssertion)
        let data = try rawManifest(fields: [rawField()])
        let wrongTime = try replacingOnce(data, extendedTimeEncoding, with: first.timeEncoding)
        XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: wrongTime))
        let legacy = try rawManifest(fields: [rawField(kind: "STRING")], schemaVersion: 1,
                                    codecVersion: 1, minimumReaderVersion: 1, maximumReaderVersion: 1)
        let wrongLegacyTime = try replacingOnce(legacy, first.timeEncoding, with: extendedTimeEncoding)
        XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: wrongLegacyTime))
        let wrongNormalization = try replacingOnce(data, extendedStringNormalization, with: first.stringNormalization)
        XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: wrongNormalization))
        let wrongLegacyNormalization = try replacingOnce(legacy, first.stringNormalization, with: extendedStringNormalization)
        XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: wrongLegacyNormalization))
        let replacements: [(String, String)] = [
            ("\"canonicalJSON\":\"UTF8_SORTED_KEYS_NO_INSIGNIFICANT_WHITESPACE\"", "\"canonicalJSON\":\"FUTURE\""),
            ("\"integerEncoding\":\"BASE10_INTEGER_NO_EXPONENT\"", "\"integerEncoding\":\"FUTURE\""),
            ("\"nullEncoding\":\"EXPLICIT_NULL_ONLY_WHEN_REQUIRED_NULLABLE\"", "\"nullEncoding\":\"FUTURE\""),
            ("\"binaryEncoding\":\"RFC4648_BASE64_PADDED\"", "\"binaryEncoding\":null"),
            ("\"stringNormalization\":\"PER_FIELD_NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED_OR_PRESERVED_SOURCE_UNICODE\"", "\"stringNormalization\":\"FUTURE\""),
            ("\"formatAssertion\":false", "\"formatAssertion\":true")
        ]
        for (original, replacement) in replacements {
            let invalid = try replacingOnce(data, original, with: replacement)
            XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: invalid), replacement)
        }
    }

    func testPreservedStringAndStringMapMetadataRoundTripWithoutInventedCountLimit() throws {
        let preserved = try ContractFieldDefinitionV1(
            fieldID: "a-preserved", jsonName: "preserved", kind: .preservedString,
            required: true, maximumUTF8Bytes: 512
        )
        // These are the source-defined AssessmentScopeSnapshotV1 map bounds.
        // Metadata describes its strings; it does not validate source map values.
        let reasons = try ContractFieldDefinitionV1(
            fieldID: "b-excluded-reasons", jsonName: "excludedCriterionReasons", kind: .stringMap,
            required: true, maximumUTF8Bytes: 512, maximumKeyUTF8Bytes: 256
        )
        let boundedMap = try ContractFieldDefinitionV1(
            fieldID: "c-bounded-map", jsonName: "boundedMap", kind: .stringMap,
            required: true, maximumUTF8Bytes: 64, maximumItems: 8, maximumKeyUTF8Bytes: 32
        )
        let unboundedMap = try ContractFieldDefinitionV1(
            fieldID: "d-unbounded-map", jsonName: "unboundedMap", kind: .stringMap, required: true
        )
        let value = try manifest(fields: [preserved, reasons, boundedMap, unboundedMap])
        let encoded = try encode(value)
        let decoded = try JSONDecoder().decode(ContractManifestV1.self, from: encoded)
        try decoded.validate()
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(try encode(decoded), encoded)
        XCTAssertEqual(decoded.objects[0].fields[0].kind, .preservedString)
        XCTAssertEqual(decoded.objects[0].fields[0].maximumUTF8Bytes, 512)
        XCTAssertEqual(decoded.objects[0].fields[1].maximumUTF8Bytes, 512)
        XCTAssertEqual(decoded.objects[0].fields[1].maximumKeyUTF8Bytes, 256)
        XCTAssertNil(decoded.objects[0].fields[1].maximumItems)
        XCTAssertEqual(decoded.objects[0].fields[2].maximumItems, 8)
        XCTAssertEqual(decoded.objects[0].fields[2].maximumKeyUTF8Bytes, 32)
        XCTAssertNil(decoded.objects[0].fields[3].maximumKeyUTF8Bytes)
        XCTAssertNil(decoded.objects[0].fields[3].maximumUTF8Bytes)
        XCTAssertNil(decoded.objects[0].fields[3].maximumItems)

        let reasonsJSON = try XCTUnwrap(String(data: encode(reasons), encoding: .utf8))
        XCTAssertTrue(reasonsJSON.contains("\"maximumKeyUTF8Bytes\":256"))
        XCTAssertTrue(reasonsJSON.contains("\"maximumUTF8Bytes\":512"))
        XCTAssertFalse(reasonsJSON.contains("maximumItems"))
        let unboundedJSON = try XCTUnwrap(String(data: encode(unboundedMap), encoding: .utf8))
        XCTAssertFalse(unboundedJSON.contains("maximumKeyUTF8Bytes"))
        XCTAssertFalse(unboundedJSON.contains("maximumUTF8Bytes"))
        XCTAssertFalse(unboundedJSON.contains("maximumItems"))

        let literalField = rawField(kind: "STRING_MAP", extra: ",\"maximumKeyUTF8Bytes\":256,\"maximumUTF8Bytes\":512")
        let literal = try JSONDecoder().decode(ContractManifestV1.self, from: rawManifest(fields: [literalField]))
        XCTAssertEqual(literal.objects[0].fields[0].kind, .stringMap)
        XCTAssertEqual(literal.objects[0].fields[0].maximumKeyUTF8Bytes, 256)
        XCTAssertEqual(literal.objects[0].fields[0].maximumUTF8Bytes, 512)
        XCTAssertNil(literal.objects[0].fields[0].maximumItems)
    }

    func testStringMapMetadataRejectsInvalidBoundsShapesAndArrayUse() throws {
        XCTAssertThrowsError(try ContractFieldDefinitionV1(
            fieldID: "map", jsonName: "map", kind: .stringMap, required: true,
            maximumKeyUTF8Bytes: 0
        ))
        XCTAssertThrowsError(try ContractFieldDefinitionV1(
            fieldID: "text", jsonName: "text", kind: .preservedString, required: true,
            maximumKeyUTF8Bytes: 256
        ))
        XCTAssertThrowsError(try ContractFieldDefinitionV1(
            fieldID: "map", jsonName: "map", kind: .stringMap, required: true, ordered: true
        ))
        XCTAssertThrowsError(try ContractFieldDefinitionV1(
            fieldID: "maps", jsonName: "maps", kind: .array,
            arrayElementKind: .stringMap, required: true, maximumItems: 2
        ))
        for token in ["0", "-1", "1.5", "18446744073709551616", "null", "true", "\"256\"", "[]", "{}"] {
            let field = rawField(kind: "STRING_MAP", extra: ",\"maximumKeyUTF8Bytes\":\(token)")
            let data = try rawManifest(fields: [field])
            XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: data), token)
        }
        let invalidFields: [String] = [
            rawField(kind: "STRING", extra: ",\"maximumKeyUTF8Bytes\":256"),
            rawField(kind: "PRESERVED_STRING", extra: ",\"maximumKeyUTF8Bytes\":256"),
            rawField(kind: "STRING_MAP", extra: ",\"maximumUTF8Bytes\":0"),
            rawField(kind: "PRESERVED_STRING", extra: ",\"maximumUTF8Bytes\":0"),
            rawField(kind: "STRING_MAP", extra: ",\"maximumItems\":0"),
            rawField(kind: "STRING_MAP", extra: ",\"maximumItems\":-1"),
            rawField(kind: "STRING_MAP", extra: ",\"maximumItems\":null"),
            rawField(kind: "PRESERVED_STRING", extra: ",\"maximumItems\":2"),
            rawField(kind: "STRING_MAP", extra: ",\"referencedTypeID\":\"completed-profile-v2\""),
            rawField(kind: "STRING_MAP", extra: ",\"arrayElementKind\":\"PRESERVED_STRING\""),
            rawField(kind: "STRING_MAP", extra: ",\"minimumInteger\":0"),
            rawField(kind: "STRING_MAP", extra: ",\"maximumInteger\":1"),
            rawField(kind: "STRING_MAP", extra: ",\"minimumUnsignedInteger\":0"),
            rawField(kind: "STRING_MAP", extra: ",\"maximumUnsignedInteger\":1"),
            rawField(kind: "STRING_MAP", extra: ",\"maximumKeyUTF8Byte\":256"),
            rawField(kind: "ARRAY", extra: ",\"arrayElementKind\":\"STRING_MAP\",\"maximumItems\":2"),
            rawField(kind: "ARRAY", extra: ",\"arrayElementKind\":\"PRESERVED_STRING\",\"maximumItems\":2,\"maximumKeyUTF8Bytes\":256"),
            rawField(kind: "ARRAY", extra: ",\"arrayElementKind\":\"PRESERVED_STRING\""),
            rawField(kind: "ARRAY", extra: ",\"arrayElementKind\":\"PRESERVED_STRING\",\"maximumItems\":0")
        ]
        for field in invalidFields {
            let data = try rawManifest(fields: [field])
            XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: data), field)
        }
        for property in ["ordered", "uniqueItems"] {
            let field = rawField(kind: "STRING_MAP")
            let original = "\"\(property)\":false"
            let replacement = "\"\(property)\":true"
            let invalidField = field.replacingOccurrences(of: original, with: replacement)
            let data = try rawManifest(fields: [invalidField])
            XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: data), property)
        }
        let legacyField = rawField(kind: "STRING", extra: ",\"maximumKeyUTF8Bytes\":256")
        let legacy = try rawManifest(fields: [legacyField], schemaVersion: 1, codecVersion: 1,
                                    minimumReaderVersion: 1, maximumReaderVersion: 1)
        XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: legacy))
    }

    private func rawNumericEnumManifest(
        integers: String = "[0,90,180,270]", knownValues: String = "[]",
        policy: String = "CLOSED", schemaVersion: Int = 2
    ) throws -> Data {
        let field = rawField(kind: "ENUM", extra: ",\"referencedTypeID\":\"plan-page-rotation-v1\"")
        let base = try rawManifest(fields: [field], schemaVersion: schemaVersion,
                                   codecVersion: schemaVersion,
                                   minimumReaderVersion: schemaVersion,
                                   maximumReaderVersion: schemaVersion)
        let definition = """
        {"typeID":"plan-page-rotation-v1","version":1,"policy":"\(policy)",
        "knownValues":\(knownValues),"knownIntegerValues":\(integers)}
        """
        return try replacingOnce(base, "\"enums\":[]", with: "\"enums\":[\(definition)]")
    }

    func testNumericEnumMetadataPreservesExactSourceRotationWireValues() throws {
        let values: [Int64] = [0, 90, 180, 270]
        let definition = try ContractEnumDefinitionV1(
            typeID: "plan-page-rotation-v1", version: 1, policy: .closed,
            knownValues: [], knownIntegerValues: values
        )
        XCTAssertEqual(try JSONDecoder().decode(ContractEnumDefinitionV1.self,
                                                from: encode(definition)), definition)
        let decoded = try JSONDecoder().decode(ContractManifestV1.self, from: rawNumericEnumManifest())
        XCTAssertEqual(decoded.enums, [definition])
        XCTAssertEqual(PlanPageRotationV1.allCases.map { Int64($0.rawValue) }, values)
        for rotation in PlanPageRotationV1.allCases {
            let bytes = try encode(rotation)
            XCTAssertEqual(bytes, Data(String(rotation.rawValue).utf8))
            XCTAssertEqual(try JSONDecoder().decode(PlanPageRotationV1.self, from: bytes), rotation)
        }
        for token in ["1", "45", "271", "\"90\""] {
            XCTAssertThrowsError(try JSONDecoder().decode(PlanPageRotationV1.self, from: Data(token.utf8)))
        }
        let endpoints = try rawNumericEnumManifest(integers: "[-9223372036854775808,9223372036854775807]")
        let fullWidth = try JSONDecoder().decode(ContractManifestV1.self, from: endpoints)
        XCTAssertEqual(fullWidth.enums[0].knownIntegerValues, [Int64.min, Int64.max])
    }

    func testNumericEnumMetadataRejectsMixedMalformedAndLegacyDefinitions() throws {
        for token in ["[]", "[90,0]", "[0,0]", "[true]", "[1.5]", "[\"90\"]",
                      "[9223372036854775808]", "[-9223372036854775809]", "null", "{}", "[null]"] {
            let data = try rawNumericEnumManifest(integers: token)
            XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: data), token)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self,
            from: rawNumericEnumManifest(knownValues: "[\"NINETY\"]")))
        XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self,
            from: rawNumericEnumManifest(policy: "PRESERVE_UNKNOWN")))
        XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self,
            from: rawNumericEnumManifest(schemaVersion: 1)))
        let unknown = try replacingOnce(rawNumericEnumManifest(), "\"knownIntegerValues\"",
                                         with: "\"knownIntegerValue\"")
        XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: unknown))
        XCTAssertThrowsError(try ContractEnumDefinitionV1(typeID: "invalid", version: 1,
            policy: .closed, knownValues: [], knownIntegerValues: []))
        XCTAssertThrowsError(try ContractEnumDefinitionV1(typeID: "invalid", version: 1,
            policy: .preserveUnknown, knownValues: [], knownIntegerValues: [0]))
        XCTAssertThrowsError(try ContractEnumDefinitionV1(typeID: "invalid", version: 1,
            policy: .closed, knownValues: ["ZERO"], knownIntegerValues: [0]))
    }

    func testClosedEmptyObjectMetadataRequiresSchemaTwoAndMatchesPoseWire() throws {
        let closed = try ContractObjectDefinitionV1(typeID: "completed-profile-v2", version: 1,
                                                   unknownFieldPolicy: .reject, fields: [])
        let accepted = try JSONDecoder().decode(ContractManifestV1.self, from: rawManifest(fields: []))
        XCTAssertEqual(accepted.objects, [closed])
        XCTAssertEqual(try JSONDecoder().decode(ContractManifestV1.self, from: encode(accepted)), accepted)
        let open = try replacingOnce(rawManifest(fields: []), "\"unknownFieldPolicy\":\"REJECT\"",
                                      with: "\"unknownFieldPolicy\":\"PRESERVE\"")
        XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: open))
        XCTAssertThrowsError(try ContractObjectDefinitionV1(typeID: "empty", version: 1,
                                                           unknownFieldPolicy: .preserve, fields: []))
        let legacy = try rawManifest(fields: [], schemaVersion: 1, codecVersion: 1,
                                     minimumReaderVersion: 1, maximumReaderVersion: 1)
        XCTAssertThrowsError(try JSONDecoder().decode(ContractManifestV1.self, from: legacy))
        XCTAssertEqual(try encode(PoseUncertaintyV1.unknown), Data("{\"unknown\":{}}".utf8))
        XCTAssertEqual(try encode(PoseReferenceFrameV1.unknown), Data("{\"unknown\":{}}".utf8))
        XCTAssertEqual(try encode(PoseReferenceFrameV1.trueBearing), Data("{\"trueBearing\":{}}".utf8))
        XCTAssertEqual(try encode(PoseReferenceFrameV1.magneticBearing), Data("{\"magneticBearing\":{}}".utf8))
    }
}
